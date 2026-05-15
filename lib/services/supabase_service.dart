import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final client = Supabase.instance.client;

  /// USUÁRIO

  Future<void> garantirPerfilGoogle() async {
    final user = usuarioLogado;
    if (user == null) return;

    final name =
        user.userMetadata?['full_name'] ??
        user.userMetadata?['name'] ??
        'Usuário Google';

    await client.auth.updateUser(UserAttributes(data: {'name': name}));
  }

  Future<void> cadastrarUsuario(String nome, String email, String senha) async {
    await client.auth.signUp(
      email: email,
      password: senha,
      data: {'name': nome},
    );
  }

  Future<void> login(String email, String senha) async {
    await client.auth.signInWithPassword(email: email, password: senha);
  }

  User? get usuarioLogado => client.auth.currentUser;

  /// LOCAL

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

  /// VAGA

  Future<void> registrarVaga({
    required String idLocal,
    required String tipo,
  }) async {
    await client.from('vagas').insert({'id_local': idLocal, 'tipo_vaga': tipo});
  }

  /// LISTAR VAGAS AGRUPADAS

  Future<List<Map<String, dynamic>>> buscarVagas() async {
    final response = await client.from('vagas').select('*, locais(*)');

    return response;
  }

  Future<String?> getNomeUsuario() async {
    final user = usuarioLogado;
    return user?.userMetadata?['name'];
  }
}
