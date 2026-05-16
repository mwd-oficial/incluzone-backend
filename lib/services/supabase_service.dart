import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final client = Supabase.instance.client;

  User? get usuarioLogado => client.auth.currentUser;
  bool get estaLogado => client.auth.currentUser != null;

  /// Faz o upload da foto para o Storage e atualiza o Auth do Usuário
  Future<String?> uploadFotoPerfil(File imagem) async {
    final user = usuarioLogado;
    if (user == null) return null;

    try {
      // Define um nome único para o arquivo usando o ID do usuário
      final fileExt = imagem.path.split('.').last;
      final fileName = '${user.id}/avatar.$fileExt';

      // 1. Upload para o bucket 'usuarios_images' (Certifique-se de criar este bucket no Supabase)
      // Use upsert: true para sobrescrever caso ele mude de foto depois
      await client.storage
          .from('usuarios_images')
          .upload(
            fileName,
            imagem,
            fileOptions: const FileOptions(upsert: true),
          );

      // 2. Pegar a URL pública da imagem
      final String publicUrl = client.storage
          .from('usuarios_images')
          .getPublicUrl(fileName);

      // 3. Atualizar o avatar_url nos metadados do Auth do Supabase
      await client.auth.updateUser(
        UserAttributes(data: {'avatar_url': publicUrl}),
      );

      return publicUrl;
    } catch (e) {
      print('Erro no upload da foto: $e');
      rethrow;
    }
  }

  /// Atualiza a foto de perfil deletando a antiga do bucket e subindo a nova
  Future<String?> atualizarFotoPerfil(File novaImagem) async {
    final user = usuarioLogado;
    if (user == null) return null;

    try {
      // 1. Verificar se já existe um avatar antigo para deletar
      final String? urlAntiga = user.userMetadata?['avatar_url'];

      if (urlAntiga != null && urlAntiga.contains('usuarios_images')) {
        try {
          // Extrai o caminho do arquivo a partir da URL pública
          // Exemplo: .../storage/v1/object/public/usuarios_images/USER_ID/avatar_123.jpg
          final uri = Uri.parse(urlAntiga);
          final segmentos = uri.pathSegments;
          // Pega tudo o que vem após o nome do bucket ('usuarios_images')
          final indiceBucket = segmentos.indexOf('usuarios_images');

          if (indiceBucket != -1 && indiceBucket < segmentos.length - 1) {
            final pathAntigo = segmentos.sublist(indiceBucket + 1).join('/');

            // Deleta o arquivo antigo do Storage
            await client.storage.from('usuarios_images').remove([pathAntigo]);
          }
        } catch (e) {
          // Log de aviso, mas não interrompe o fluxo se a imagem antiga não existir mais
          print('Aviso: Não foi possível deletar a imagem antiga: $e');
        }
      }

      // 2. Definir um nome único para a nova imagem (usando timestamp evita cache agressivo do app)
      final fileExt = novaImagem.path.split('.').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${user.id}/avatar_$timestamp.$fileExt';

      // 3. Upload da nova imagem
      await client.storage
          .from('usuarios_images')
          .upload(
            fileName,
            novaImagem,
            fileOptions: const FileOptions(upsert: true),
          );

      // 4. Pegar a nova URL pública
      final String publicUrl = client.storage
          .from('usuarios_images')
          .getPublicUrl(fileName);

      // Nota: Não atualizamos o auth aqui dentro para deixar que a tela
      // envie junto com o Nome/E-mail no método principal.
      return publicUrl;
    } catch (e) {
      print('Erro ao atualizar foto de perfil: $e');
      rethrow;
    }
  }

  Future<void> garantirPerfilGoogle() async {
    final user = usuarioLogado;
    if (user == null) return;

    final name =
        user.userMetadata?['full_name'] ??
        user.userMetadata?['name'] ??
        'Usuário Google';

    final avatarUrl =
        user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'];

    await client.auth.updateUser(
      UserAttributes(
        data: {'name': name, if (avatarUrl != null) 'avatar_url': avatarUrl},
      ),
    );
  }

  Future<void> cadastrarUsuario(String nome, String email, String senha) async {
    await client.auth.signUp(
      email: email,
      password: senha,
      data: {
        'name': nome,
      }, // O avatar_url vai ser inserido após o login/confirmação
    );
  }

  Future<void> login(String email, String senha) async {
    await client.auth.signInWithPassword(email: email, password: senha);
  }

  // --- RESTO DOS SEUS MÉTODOS (LOCAL, VAGA, etc.) ---
  Future<void> registrarLocal({
    required String cidade,
    required String estado,
    required String referencia,
  }) async {
    final user = usuarioLogado;
    await client.from('locais').insert({
      'cidade': cidade,
      'estado': estado,
      'referencia': referencia,
      'latitude': 0,
      'longitude': 0,
      'id_usuario_criador': user?.id,
    });
  }

  Future<void> registrarVaga({
    required String idLocal,
    required String tipo,
  }) async {
    await client.from('vagas').insert({'id_local': idLocal, 'tipo_vaga': tipo});
  }

  Future<List<Map<String, dynamic>>> buscarVagas() async {
    return await client.from('vagas').select('*, locais(*)');
  }

  Future<String?> getNomeUsuario() async {
    return usuarioLogado?.userMetadata?['name'];
  }
}
