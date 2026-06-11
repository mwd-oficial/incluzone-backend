/*
////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////



ESTE CÓDIGO É APENAS PARA CONSULTA E NÃO DEVE SER EDITADO!!!!!!!!!!!!!!!!!!!



/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
*/

import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Serviço centralizado para todas as operações que envolvem o Supabase,
/// incluindo autenticação de usuários, gerenciamento de fotos de perfil
/// no Storage e operações de banco de dados (locais e vagas).
///
/// Esta classe age como uma camada de abstração (Service Layer) entre
/// a UI do aplicativo e o SDK do Supabase, isolando a lógica de
/// infraestrutura do restante da aplicação.
class SupabaseService {
  /// Instância singleton do cliente Supabase, inicializada globalmente
  /// via [Supabase.initialize()] na inicialização do app (geralmente em main.dart).
  /// Provê acesso a todos os módulos: Auth, Database, Storage, etc.
  final client = Supabase.instance.client;

  /// Retorna o objeto [User] do usuário atualmente autenticado,
  /// ou [null] caso nenhuma sessão ativa exista.
  User? get usuarioLogado => client.auth.currentUser;

  /// Atalho booleano para verificar se há um usuário autenticado na sessão.
  /// Evita a necessidade de checar [usuarioLogado != null] em toda a aplicação.
  bool get estaLogado => client.auth.currentUser != null;

  /// Faz o upload inicial da foto de perfil para o Supabase Storage
  /// e, em seguida, persiste a URL pública gerada nos metadados de autenticação
  /// do usuário, tornando-a acessível globalmente via [usuarioLogado.userMetadata].
  ///
  /// Utiliza um nome de arquivo fixo ([avatar.extensão]) pois é o upload
  /// inicial — para atualizações subsequentes, use [atualizarFotoPerfil],
  /// que trata a deleção da imagem antiga e evita acúmulo de arquivos órfãos.
  ///
  /// Parâmetros:
  /// - [imagem]: O arquivo de imagem local ([File]) a ser enviado.
  ///
  /// Retorna a URL pública da imagem no Storage, ou [null] se o
  /// usuário não estiver autenticado. Relança qualquer exceção de rede
  /// ou Storage para que a camada de UI possa tratar o erro adequadamente.
  Future<String?> uploadFotoPerfil(File imagem) async {
    final user = usuarioLogado;
    // Garante que a operação só prossiga com um usuário autenticado,
    // pois o ID do usuário é usado para organizar os arquivos no bucket.
    if (user == null) return null;

    try {
      // Extrai a extensão original do arquivo (ex: "jpg", "png") para
      // preservar o formato correto no Storage.
      final fileExt = imagem.path.split('.').last;

      // Organiza os arquivos no bucket usando o ID do usuário como "pasta" virtual,
      // garantindo isolamento e fácil localização dos arquivos de cada usuário.
      final fileName = '${user.id}/avatar.$fileExt';

      // Envia o arquivo para o bucket 'usuarios_images'.
      // [upsert: true] permite sobrescrever um arquivo com o mesmo caminho caso
      // este método seja chamado mais de uma vez para o mesmo usuário,
      // prevenindo erros de conflito no Storage.
      await client.storage
          .from('usuarios_images')
          .upload(
            fileName,
            imagem,
            fileOptions: const FileOptions(upsert: true),
          );

      // Obtém a URL pública e permanente do arquivo recém-enviado.
      // Esta URL é necessária para exibir o avatar em qualquer lugar do app
      // sem a necessidade de autenticação para acessar a imagem.
      final String publicUrl = client.storage
          .from('usuarios_images')
          .getPublicUrl(fileName);

      // Persiste a URL pública no campo 'avatar_url' dos metadados do usuário
      // no Supabase Auth. Isso centraliza o dado e o torna acessível via
      // [client.auth.currentUser?.userMetadata?['avatar_url']] em todo o app.
      await client.auth.updateUser(
        UserAttributes(data: {'avatar_url': publicUrl}),
      );

      return publicUrl;
    } catch (e) {
      print('Erro no upload da foto: $e');
      // Relança a exceção para que o chamador (ex: um controller ou a UI)
      // possa exibir uma mensagem de erro apropriada ao usuário.
      rethrow;
    }
  }

  /// Substitui a foto de perfil existente do usuário por uma nova imagem.
  ///
  /// Este método implementa uma estratégia de substituição em duas etapas:
  /// primeiro tenta deletar a imagem antiga do Storage para evitar o acúmulo
  /// de arquivos órfãos e controlar custos de armazenamento; depois realiza
  /// o upload da nova imagem com um nome único baseado em timestamp.
  ///
  /// O uso de timestamp no nome do arquivo ([avatar_TIMESTAMP.ext]) é uma
  /// estratégia deliberada para invalidar o cache de imagens do sistema
  /// operacional e do widget [Image], forçando o recarregamento da nova foto.
  ///
  /// Atenção: Este método retorna apenas a nova URL pública e intencionalmente
  /// NÃO atualiza os metadados de Auth. A responsabilidade de consolidar
  /// a nova URL junto com outros dados editáveis (como nome) é da tela chamadora,
  /// permitindo que tudo seja salvo em uma única chamada a [updateUser].
  ///
  /// Parâmetros:
  /// - [novaImagem]: O arquivo [File] da nova foto a ser utilizada como avatar.
  ///
  /// Retorna a URL pública da nova imagem, ou [null] se não houver usuário
  /// autenticado. Relança exceções para tratamento pela camada de UI.
  Future<String?> atualizarFotoPerfil(File novaImagem) async {
    final user = usuarioLogado;
    if (user == null) return null;

    try {
      // Recupera a URL da foto de perfil atual dos metadados do Auth para
      // poder identificar e deletar o arquivo correspondente no Storage.
      final String? urlAntiga = user.userMetadata?['avatar_url'];

      // Só tenta deletar se houver uma URL antiga e se ela realmente
      // apontar para o nosso bucket, evitando tentativas de deleção
      // em URLs de provedores externos (ex: avatar do Google).
      if (urlAntiga != null && urlAntiga.contains('usuarios_images')) {
        try {
          // O Storage não fornece um método direto para deletar por URL,
          // então é necessário extrair o caminho relativo do arquivo
          // (ex: "USER_ID/avatar_123.jpg") a partir da URL pública completa.
          final uri = Uri.parse(urlAntiga);
          final segmentos = uri.pathSegments;

          // Localiza o índice do segmento com o nome do bucket na URL para
          // identificar onde começa o caminho interno do arquivo.
          // Exemplo de URL: .../object/public/usuarios_images/USER_ID/avatar.jpg
          final indiceBucket = segmentos.indexOf('usuarios_images');

          // Valida que o bucket foi encontrado e que há segmentos após ele,
          // ou seja, que o caminho do arquivo está presente na URL.
          if (indiceBucket != -1 && indiceBucket < segmentos.length - 1) {
            // Reconstrói o caminho relativo juntando todos os segmentos
            // que vêm após o nome do bucket (ex: "USER_ID/avatar_123.jpg").
            final pathAntigo = segmentos.sublist(indiceBucket + 1).join('/');

            // Remove o arquivo antigo do bucket. A operação aceita uma lista
            // pois a API do Storage suporta deleção em lote.
            await client.storage.from('usuarios_images').remove([pathAntigo]);
          }
        } catch (e) {
          // A falha na deleção da imagem antiga é tratada como não-crítica.
          // O fluxo continua para garantir que o upload da nova foto sempre
          // seja concluído, mesmo que o arquivo antigo já não exista no Storage.
          print('Aviso: Não foi possível deletar a imagem antiga: $e');
        }
      }

      // Gera um nome de arquivo único usando o timestamp atual em milissegundos.
      // Esta abordagem é preferível ao [upsert] para este caso pois garante
      // que a nova URL seja diferente, forçando a atualização do cache de imagens
      // nos widgets que exibem o avatar.
      final fileExt = novaImagem.path.split('.').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${user.id}/avatar_$timestamp.$fileExt';

      // Realiza o upload do novo arquivo de avatar no bucket.
      await client.storage
          .from('usuarios_images')
          .upload(
            fileName,
            novaImagem,
            fileOptions: const FileOptions(upsert: true),
          );

      // Obtém a URL pública do novo arquivo para retorná-la ao chamador.
      final String publicUrl = client.storage
          .from('usuarios_images')
          .getPublicUrl(fileName);

      // Retorna apenas a URL, sem atualizar o Auth aqui.
      // A tela de edição de perfil deve consolidar esta URL com os demais
      // dados do usuário (nome, e-mail) em uma única chamada [updateUser],
      // reduzindo o número de requisições à API.
      return publicUrl;
    } catch (e) {
      print('Erro ao atualizar foto de perfil: $e');
      rethrow;
    }
  }

  /// Garante que os metadados de um usuário autenticado via Google (OAuth)
  /// estejam corretamente populados no Supabase Auth.
  ///
  /// O login social com o Google pode retornar os dados do perfil (nome e foto)
  /// em campos de metadados diferentes dependendo do provedor e da versão da API
  /// (ex: 'full_name' vs 'name', 'avatar_url' vs 'picture'). Este método
  /// normaliza esses dados, garantindo que os campos 'name' e 'avatar_url'
  /// — que são o padrão utilizado pelo restante da aplicação — estejam sempre
  /// preenchidos após o primeiro login com Google.
  Future<void> garantirPerfilGoogle() async {
    final user = usuarioLogado;
    if (user == null) return;

    // Tenta obter o nome a partir dos possíveis campos retornados pelo Google OAuth,
    // usando um valor padrão caso nenhum deles esteja disponível.
    final name =
        user.userMetadata?['full_name'] ??
        user.userMetadata?['name'] ??
        'Usuário Google';

    // O campo de foto também pode vir como 'avatar_url' ou 'picture' no token
    // do Google, portanto ambos são verificados para máxima compatibilidade.
    final avatarUrl =
        user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'];

    // Atualiza os metadados do usuário com os campos normalizados.
    // O operador spread condicional [if (avatarUrl != null) 'avatar_url': avatarUrl]
    // evita sobrescrever um 'avatar_url' já existente com um valor nulo,
    // protegendo dados de perfil eventualmente personalizados pelo usuário.
    await client.auth.updateUser(
      UserAttributes(
        data: {'name': name, if (avatarUrl != null) 'avatar_url': avatarUrl},
      ),
    );
  }

  /// Cria uma nova conta de usuário no Supabase Auth usando e-mail e senha.
  ///
  /// O [nome] é salvo imediatamente nos metadados do usuário ([data])
  /// durante o cadastro, evitando uma segunda chamada à API para populá-lo.
  /// O 'avatar_url' não é definido aqui pois o usuário ainda não tem uma
  /// foto de perfil — ela poderá ser adicionada após o login ou confirmação
  /// de e-mail, utilizando [uploadFotoPerfil].
  ///
  /// Parâmetros:
  /// - [nome]: Nome de exibição do usuário.
  /// - [email]: Endereço de e-mail, usado como identificador de login.
  /// - [senha]: Senha escolhida pelo usuário para autenticação.
  Future<void> cadastrarUsuario(String nome, String email, String senha) async {
    await client.auth.signUp(
      email: email,
      password: senha,
      data: {
        'name': nome,
      }, // O avatar_url vai ser inserido após o login/confirmação
    );
  }

  /// Autentica um usuário existente no Supabase usando e-mail e senha.
  ///
  /// Em caso de sucesso, o SDK do Supabase persiste automaticamente a sessão
  /// localmente (via SharedPreferences/SecureStorage), tornando o usuário
  /// acessível via [usuarioLogado] em chamadas futuras, mesmo após reiniciar o app.
  ///
  /// Parâmetros:
  /// - [email]: E-mail cadastrado do usuário.
  /// - [senha]: Senha correspondente à conta.
  Future<void> login(String email, String senha) async {
    await client.auth.signInWithPassword(email: email, password: senha);
  }

  /// Insere um novo registro de local físico na tabela 'locais' do banco de dados.
  ///
  /// O ID do usuário criador ([id_usuario_criador]) é vinculado ao registro
  /// para fins de auditoria e para possibilitar regras de segurança (RLS)
  /// que restrinjam edição/exclusão apenas ao criador do local.
  ///
  /// Nota: Os campos de geolocalização ([latitude] e [longitude]) são inseridos
  /// com valor 0 como placeholder. Uma implementação futura deverá populá-los
  /// com as coordenadas reais obtidas via geocoding ou GPS do dispositivo.
  ///
  /// Parâmetros:
  /// - [cidade]: Nome da cidade onde o local está situado.
  /// - [estado]: UF ou nome do estado.
  /// - [referencia]: Descrição ou ponto de referência para facilitar a identificação.
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

  /// Insere um novo registro de vaga de estacionamento na tabela 'vagas',
  /// associando-a a um local previamente cadastrado.
  ///
  /// A relação entre vaga e local é feita via chave estrangeira [id_local],
  /// permitindo que múltiplas vagas sejam vinculadas a um mesmo local.
  ///
  /// Parâmetros:
  /// - [idLocal]: O UUID do registro na tabela 'locais' ao qual esta vaga pertence.
  /// - [tipo]: Classificação da vaga (ex: "comum", "PCD", "idoso", "moto").
  Future<void> registrarVaga({
    required String idLocal,
    required String tipo,
  }) async {
    await client.from('vagas').insert({'id_local': idLocal, 'tipo_vaga': tipo});
  }

  /// Busca todas as vagas cadastradas no banco de dados, incluindo os dados
  /// completos do local associado a cada uma delas.
  ///
  /// O uso de [select('*, locais(*)')] realiza um JOIN implícito via a
  /// chave estrangeira definida no schema do banco, retornando os dados
  /// da tabela 'vagas' enriquecidos com o objeto 'locais' aninhado,
  /// eliminando a necessidade de múltiplas requisições separadas.
  ///
  /// Retorna uma [List<Map<String, dynamic>>] onde cada mapa representa
  /// uma vaga com seu local embutido no campo 'locais'.
  Future<List<Map<String, dynamic>>> buscarVagas() async {
    return await client.from('vagas').select('*, locais(*)');
  }

  /// Retorna o nome de exibição do usuário atualmente autenticado,
  /// lendo diretamente do campo 'name' nos metadados de Auth.
  ///
  /// Retorna [null] se não houver usuário logado ou se o campo 'name'
  /// não estiver populado nos metadados.
  Future<String?> getNomeUsuario() async {
    return usuarioLogado?.userMetadata?['name'];
  }
}