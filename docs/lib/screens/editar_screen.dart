/*
////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////



ESTE CÓDIGO É APENAS PARA CONSULTA E NÃO DEVE SER EDITADO!!!!!!!!!!!!!!!!!!!



/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
*/

import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import 'dart:async';
import '../main.dart';
import 'package:image_picker/image_picker.dart';

/// Tela de edição de perfil do usuário.
///
/// Permite ao usuário atualizar seu nome, e-mail, senha e foto de perfil,
/// além de oferecer a opção de excluir a conta permanentemente.
/// Gerencia o fluxo de confirmação de e-mail via timer e listener de autenticação.
class EditarScreen extends StatefulWidget {
  const EditarScreen({super.key});

  @override
  State<EditarScreen> createState() => _EditarScreenState();
}

class _EditarScreenState extends State<EditarScreen> {
  // Controladores de texto para os campos do formulário
  final nome = TextEditingController();
  final email = TextEditingController();
  final senha = TextEditingController();
  final confirmarSenha = TextEditingController();

  /// Instância do serviço do Supabase, usado para operações como upload de foto.
  final SupabaseService _supabaseService = SupabaseService();

  /// Timer responsável pela contagem regressiva após a solicitação de troca de e-mail.
  /// Evita que o usuário reenvie o pedido repetidamente em curto intervalo.
  Timer? _timer;

  /// Quantidade de segundos restantes no contador de espera.
  /// Enquanto maior que 0, o botão de salvar permanece desabilitado.
  int _segundosRestantes = 0;

  /// Flag que indica se existe uma troca de e-mail pendente de confirmação.
  /// É true quando o Supabase enviou o link de confirmação mas o usuário ainda não clicou.
  bool _emailAlteradoPendente = false;

  /// Armazena o novo e-mail que o usuário tentou cadastrar.
  /// Usado para comparar com o e-mail atual do usuário e detectar quando a confirmação ocorre.
  String _ultimoEmailTentaAlterar = "";

  /// Controla a exibição do indicador de carregamento e desabilita ações simultâneas.
  bool _carregando = false;

  /// Arquivo de imagem selecionado localmente pelo usuário, antes do upload.
  File? _imagemSelecionada;

  /// URL da imagem de perfil já salva no Supabase Storage.
  /// É exibida como fallback enquanto nenhuma imagem nova for selecionada.
  String? _urlImagemExistente;

  /// Instância do seletor de imagens da galeria do dispositivo.
  final ImagePicker _picker = ImagePicker();

  /// Subscription do stream de mudanças de estado de autenticação do Supabase.
  /// Necessário guardar a referência para cancelá-la corretamente no [dispose].
  late final StreamSubscription<AuthState> _authSubscription;

  /// Controla a visibilidade do texto no campo de senha (mostrar/ocultar).
  bool _senhaVisivel = false;

  /// Nível de zoom da interface, variando de 0 (padrão) a 2 (máximo).
  /// Persistido em [SharedPreferences] e aplicado globalmente via [myAppKey].
  int _nivelZoom = 0;

  @override
  void initState() {
    super.initState();
    // Carrega as preferências salvas (zoom) e os dados do usuário autenticado ao abrir a tela
    _carregarConfiguracoesIniciais();
    _carregarDadosUsuario();

    // Escuta em tempo real as mudanças de sessão/autenticação.
    // É o mecanismo principal para detectar a confirmação de e-mail sem que o usuário
    // precise sair e voltar ao aplicativo.
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      final user = data.session?.user;

      // A confirmação ocorreu quando: o usuário existe, o e-mail atual já é o novo e-mail,
      // e o campo 'newEmail' (que indica pendência) desapareceu do objeto do usuário.
      if (user != null &&
          user.email == _ultimoEmailTentaAlterar &&
          user.newEmail == null &&
          _emailAlteradoPendente) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("E-mail confirmado com sucesso!")),
          );
          // Redireciona para a home após a confirmação bem-sucedida
          Navigator.pushReplacementNamed(context, '/');
        }
      }
    });
  }

  @override
  void dispose() {
    // Libera os controladores de texto para evitar vazamentos de memória
    nome.dispose();
    email.dispose();
    senha.dispose();
    confirmarSenha.dispose();
    // Cancela a subscription do stream de autenticação para não receber eventos em widgets desmontados
    _authSubscription.cancel();
    super.dispose();
  }

  /// Incrementa ou decrementa o nível de zoom da interface e persiste a preferência.
  ///
  /// [aumentar] — se `true`, aumenta o zoom; se `false`, diminui.
  /// O nível é limitado entre 0 (mínimo) e 2 (máximo).
  /// Após alterar, notifica o estado global do [MyApp] para re-renderizar com a nova escala.
  Future<void> _atualizarZoom(bool aumentar) async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      if (aumentar && _nivelZoom < 2) {
        _nivelZoom++;
      } else if (!aumentar && _nivelZoom > 0) {
        _nivelZoom--;
      }
    });

    // Persiste o nível de zoom no armazenamento local do dispositivo
    await prefs.setInt('nivel_zoom', _nivelZoom);

    // Propaga a mudança de escala para o widget raiz do app através da GlobalKey,
    // garantindo que toda a árvore de widgets seja reconstruída com o novo fator de escala.
    myAppKey.currentState?.atualizarEscala(_nivelZoom);
  }

  /// Abre a galeria do dispositivo para o usuário escolher uma nova foto de perfil.
  ///
  /// A imagem é comprimida com qualidade 70 antes de ser armazenada em [_imagemSelecionada],
  /// reduzindo o tamanho do arquivo para o upload posterior no Supabase Storage.
  Future<void> _selecionarImagem() async {
    final XFile? imagem = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70, // Compacta um pouco para não pesar no Supabase
    );

    if (imagem != null) {
      setState(() {
        _imagemSelecionada = File(imagem.path);
      });
    }
  }

  /// Lê o nível de zoom salvo em [SharedPreferences] e o aplica ao estado local.
  ///
  /// Usa 0 como valor padrão caso nenhuma preferência tenha sido salva anteriormente.
  Future<void> _carregarConfiguracoesIniciais() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    });
  }

  /// Busca os dados do usuário autenticado no Supabase e popula os campos do formulário.
  ///
  /// Prioriza a chamada à API ([getUser]) para obter dados frescos do servidor.
  /// Em caso de falha de rede, utiliza o cache local do cliente Supabase ([currentUser])
  /// como fallback, garantindo que a tela ainda exiba as informações disponíveis.
  Future<void> _carregarDadosUsuario() async {
    setState(() => _carregando = true);

    try {
      final response = await Supabase.instance.client.auth.getUser();
      final user = response.user;

      if (user != null) {
        setState(() {
          nome.text = user.userMetadata?['name'] ?? '';
          email.text = user.email ?? '';
          _urlImagemExistente = user.userMetadata?['avatar_url'];

          // Se o e-mail já foi confirmado enquanto o usuário navegava pela tela,
          // reseta a flag de pendência para limpar o estado de espera.
          if (_emailAlteradoPendente &&
              user.email == _ultimoEmailTentaAlterar) {
            _emailAlteradoPendente = false;
          }
        });
      }
    } catch (e) {
      // Fallback: se a chamada de rede falhar, usa os dados em cache do cliente
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        setState(() {
          nome.text = user.userMetadata?['name'] ?? '';
          email.text = user.email ?? '';
          _urlImagemExistente = user.userMetadata?['avatar_url'];
        });
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Inicia a contagem regressiva de 60 segundos após o envio do e-mail de confirmação.
  ///
  /// Durante a contagem, o botão de salvar fica desabilitado para evitar reenvios acidentais.
  /// A cada 3 segundos, consulta ativamente o Supabase para verificar se o usuário
  /// já clicou no link de confirmação, tornando o processo mais responsivo.
  void _iniciarTimer() {
    setState(() {
      _segundosRestantes = 60;
    });
    // Cancela qualquer timer anterior antes de criar um novo, evitando execuções paralelas
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_segundosRestantes == 0) {
        timer.cancel();
        // O estado pendente é mantido mesmo após o timer expirar;
        // o usuário pode reenviar clicando novamente no botão que será reabilitado.
      } else {
        if (mounted) {
          setState(() => _segundosRestantes--);

          // Polling a cada 3 segundos para verificar confirmação de e-mail no servidor.
          // Complementa o listener de [onAuthStateChange] para cenários onde
          // o evento de autenticação pode não ser propagado em tempo real.
          if (_segundosRestantes % 3 == 0 && _emailAlteradoPendente) {
            try {
              // Força a atualização da sessão e busca dados do servidor
              final response = await Supabase.instance.client.auth.getUser();
              final user = response.user;

              // Confirmação detectada: e-mail atual já é o novo e 'newEmail' foi removido
              if (user != null &&
                  user.email == _ultimoEmailTentaAlterar &&
                  user.newEmail == null) {
                timer.cancel(); // Para o contador

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("E-mail confirmado com sucesso!"),
                    ),
                  );
                  // Redireciona o usuário
                  Navigator.pushReplacementNamed(context, '/');
                }
              }
            } catch (e) {
              debugPrint("Erro na verificação automática: $e");
            }
          }
        }
      }
    });
  }

  /// Verifica a conectividade real com a internet.
  ///
  /// Primeiro checa se há uma interface de rede ativa via [Connectivity].
  /// Em seguida, realiza uma consulta DNS real para `google.com` para confirmar
  /// que o dispositivo não está apenas conectado a uma rede sem acesso externo.
  /// Retorna `true` se a internet estiver acessível, `false` caso contrário.
  Future<bool> _temInternet() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return false;
    }
    // Checagem real de DNS para validar acesso externo além da conexão local
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Exibe um [AlertDialog] genérico com um título e uma mensagem.
  ///
  /// Usado como utilitário centralizado para feedback de erros e avisos ao usuário,
  /// evitando duplicação de código de diálogo ao longo da tela.
  void _mostrarDialogo(String titulo, String mensagem) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  /// Valida os campos do formulário antes de enviar a atualização.
  ///
  /// Regras de negócio aplicadas:
  /// - Nome e e-mail são obrigatórios e não podem estar em branco.
  /// - O e-mail deve conter '@' e '.', numa verificação básica de formato.
  /// - A senha é opcional; se preenchida, deve ter no mínimo 8 caracteres,
  ///   ao menos uma letra maiúscula, um número e um caractere especial.
  /// - Se a senha for preenchida, o campo de confirmação deve ser idêntico.
  ///
  /// Retorna `true` se todos os campos válidos, `false` caso contrário
  /// (e exibe o diálogo de erro correspondente).
  bool _validarCampos() {
    if (nome.text.trim().isEmpty || email.text.trim().isEmpty) {
      _mostrarDialogo("Erro", "Nome e email são obrigatórios.");
      return false;
    }

    if (!email.text.contains("@") || !email.text.contains(".")) {
      _mostrarDialogo("Erro", "Digite um e-mail válido.");
      return false;
    }

    if (senha.text.isNotEmpty) {
      final temMaiuscula = RegExp(r'[A-Z]').hasMatch(senha.text);
      final temNumero = RegExp(r'[0-9]').hasMatch(senha.text);
      final temEspecial = RegExp(
        r'[!@#\$&*~%^()_\-+=<>?/\\|{}[\]:;.,]',
      ).hasMatch(senha.text);

      if (senha.text.length < 8 ||
          !temMaiuscula ||
          !temNumero ||
          !temEspecial) {
        _mostrarDialogo(
          "Senha fraca",
          "Senha deve ter 8+ caracteres, maiúscula, número e especial.",
        );
        return false;
      }

      if (senha.text != confirmarSenha.text) {
        _mostrarDialogo("Erro", "As senhas não coincidem.");
        return false;
      }
    }

    return true;
  }

  /// Orquestra o processo completo de atualização do perfil do usuário.
  ///
  /// Fluxo de execução:
  /// 1. Guarda de condições: impede execução se já estiver carregando ou com timer ativo.
  /// 2. Valida os campos do formulário via [_validarCampos].
  /// 3. Verifica conectividade via [_temInternet].
  /// 4. Se houver nova imagem selecionada, realiza o upload e obtém a URL pública.
  /// 5. Chama [auth.updateUser] com nome, e-mail, senha (se fornecida) e avatar.
  /// 6. Após a atualização, verifica se o Supabase criou uma entrada 'newEmail',
  ///    indicando que o e-mail está pendente de confirmação por link.
  /// 7a. Se pendente: armazena o e-mail tentado, inicia o timer e avisa o usuário.
  /// 7b. Se não pendente: exibe sucesso e redireciona para a home.
  Future<void> _atualizar() async {
    // Impede chamadas simultâneas e reenvio durante o timer de espera
    if (_carregando || _segundosRestantes > 0) return;
    if (!_validarCampos()) return;

    if (!(await _temInternet())) {
      _mostrarDialogo("Sem Conexão", "Verifique sua internet.");
      return;
    }

    setState(() => _carregando = true);

    try {
      // Mantém a URL existente como padrão; será substituída apenas se houver nova imagem
      String? novaUrlAvatar = _urlImagemExistente;

      if (_imagemSelecionada != null) {
        // Faz o upload da imagem para o Supabase Storage e obtém a URL pública
        novaUrlAvatar = await _supabaseService.atualizarFotoPerfil(
          _imagemSelecionada!,
        );
      }

      final auth = Supabase.instance.client.auth;
      final userAntes = auth.currentUser;
      final emailNovo = email.text.trim();

      // Monta o mapa de metadados que será salvo no perfil do usuário no Supabase Auth
      final Map<String, dynamic> userMetadata = {'name': nome.text.trim()};
      if (novaUrlAvatar != null) {
        userMetadata['avatar_url'] = novaUrlAvatar;
      }

      // Envia a atualização; senha nula é ignorada pelo Supabase (não altera a senha atual)
      await auth.updateUser(
        UserAttributes(
          email: emailNovo,
          password: senha.text.isNotEmpty ? senha.text : null,
          data: userMetadata,
        ),
        // Deep link para onde o Supabase redirecionará após o clique no e-mail de confirmação
        emailRedirectTo: 'io.supabase.flutter://login-callback',
      );

      // Busca o estado mais recente do usuário para verificar se o e-mail entrou em pendência
      final response = await auth.getUser();
      final userDepois = response.user;

      // O campo 'newEmail' é preenchido pelo Supabase enquanto a confirmação está pendente.
      // Se ele existir, significa que o e-mail ainda NÃO foi confirmado.
      bool trocaDeEmailPendente = userDepois?.newEmail != null;

      if (trocaDeEmailPendente) {
        setState(() {
          _emailAlteradoPendente = true;
          _ultimoEmailTentaAlterar = emailNovo;
        });
        // Inicia o timer de espera para evitar reenvios imediatos
        _iniciarTimer();

        _mostrarDialogo(
          "Confirme seu e-mail",
          "Para concluir a alteração para $emailNovo, você deve clicar no link enviado para o seu e-mail.",
        );
      } else {
        // Sem troca de e-mail pendente: atualização concluída com sucesso
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Perfil atualizado com sucesso!")),
          );
          // Só volta para a home se não estivermos esperando confirmação de e-mail
          Navigator.pushReplacementNamed(context, '/');
        }
      }
    } on AuthException catch (e) {
      // Trata erros específicos da camada de autenticação do Supabase com mensagens amigáveis
      String mensagemErro = e.message;
      if (e.message.contains(
        "New password should be different from the old password",
      )) {
        mensagemErro = "A nova senha deve ser diferente da senha atual.";
      }
      _mostrarDialogo("Erro de autenticação", mensagemErro);
    } catch (e) {
      _mostrarDialogo("Erro", "Falha ao atualizar.");
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Solicita confirmação e, se confirmado, exclui permanentemente a conta do usuário.
  ///
  /// Fluxo:
  /// 1. Verifica conectividade antes de qualquer ação.
  /// 2. Exibe um [AlertDialog] de confirmação para evitar exclusões acidentais.
  /// 3. Invoca a Edge Function 'delete-user' no Supabase, passando o ID do usuário.
  ///    A Edge Function é necessária pois a exclusão de usuários exige a service_role key,
  ///    que não pode ficar exposta no cliente mobile.
  /// 4. Realiza o logout local e redireciona para a raiz do app, limpando toda a pilha de navegação.
  Future<void> _excluirConta() async {
    if (!(await _temInternet())) {
      if (mounted) {
        _mostrarDialogo(
          "Sem Conexão",
          "Parece que você está offline. Verifique sua conexão com a internet e tente novamente.",
        );
      }
      return; // Interrompe a execução aqui
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Excluir conta"),
        content: const Text(
          "Tem certeza que deseja excluir sua conta? Essa ação não pode ser desfeita.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Excluir", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    // Aborta se o usuário cancelou ou fechou o diálogo sem confirmar
    if (confirmar != true) return;

    try {
      final user = Supabase.instance.client.auth.currentUser;

      // Chama a Edge Function do Supabase para excluir o usuário com privilégios administrativos
      await Supabase.instance.client.functions.invoke(
        'delete-user',
        body: {'userId': user?.id},
      );

      // Encerra a sessão local após a exclusão no servidor
      await Supabase.instance.client.auth.signOut();

      if (!mounted) return;

      // Remove todas as rotas da pilha de navegação e vai para a raiz,
      // impedindo que o usuário volte para telas autenticadas com o botão de voltar
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      _mostrarDialogo("Erro", "Não foi possível excluir a conta: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Impede que o layout seja redimensionado pelo teclado virtual,
      // evitando overflow em telas menores quando os campos de texto estão focados
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text("Editar conta")),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Center(
                  child: GestureDetector(
                    onTap: () {
                      // Lógica de alternância do avatar:
                      // Se qualquer imagem estiver ativa (local ou remota), o toque a remove,
                      // retornando ao avatar padrão. Se já estiver no padrão, abre a galeria.
                      final temImagemLocal = _imagemSelecionada != null;
                      final temImagemRemota =
                          _urlImagemExistente != null &&
                          _urlImagemExistente!.isNotEmpty;

                      if (temImagemLocal || temImagemRemota) {
                        // Se houver qualquer imagem, o clique limpa ambas para voltar ao padrão
                        setState(() {
                          _imagemSelecionada = null;
                          _urlImagemExistente = null;
                        });
                      } else {
                        // Se estiver no avatar padrão, abre o seletor de fotos
                        _selecionarImagem();
                      }
                    },
                    child: Stack(
                      children: [
                        // Widget principal do avatar com lógica de prioridade de imagem:
                        // 1º) Imagem local recém-selecionada (FileImage)
                        // 2º) Imagem salva no Supabase Storage (NetworkImage)
                        // 3º) Avatar padrão do asset (child com Image.asset)
                        CircleAvatar(
                          radius: 60, // Tamanho do avatar
                          backgroundColor: Colors
                              .grey
                              .shade200, // Fundo neutro enquanto carrega
                          backgroundImage: _imagemSelecionada != null
                              ? FileImage(
                                  _imagemSelecionada!,
                                ) // 1º Prioridade: Imagem nova
                              : (_urlImagemExistente != null &&
                                    _urlImagemExistente!.isNotEmpty)
                              ? NetworkImage(
                                  _urlImagemExistente!,
                                ) // 2º Prioridade: Imagem do Supabase
                              : null, // Sem imagem: usa o child abaixo
                          child:
                              // Renderiza o avatar padrão somente quando não há nenhuma imagem ativa
                              (_imagemSelecionada == null &&
                                  (_urlImagemExistente == null ||
                                      _urlImagemExistente!.isEmpty))
                              ? ClipOval(
                                  child: Image.asset(
                                    'assets/images/avatar.webp',
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : null, // Se houver imagem ativa, o child some
                        ),
                        // Botão de ação sobreposto ao avatar (canto inferior direito).
                        // Indica visualmente a ação disponível: vermelho para remover imagem,
                        // cor primária para adicionar nova foto.
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            // Se tiver imagem ativa, o botão fica vermelho indicando a remoção
                            backgroundColor:
                                (_imagemSelecionada != null ||
                                    (_urlImagemExistente != null &&
                                        _urlImagemExistente!.isNotEmpty))
                                ? Colors.red
                                : Theme.of(context).primaryColor,
                            radius: 20,
                            child: Icon(
                              // Muda o ícone dinamicamente para o "X" ou para a Câmera
                              (_imagemSelecionada != null ||
                                      (_urlImagemExistente != null &&
                                          _urlImagemExistente!.isNotEmpty))
                                  ? Icons.close
                                  : Icons.add_a_photo,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                TextField(
                  controller: nome,
                  decoration: const InputDecoration(labelText: "Nome"),
                ),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: "Email"),
                ),
                TextField(
                  controller: senha,
                  obscureText: !_senhaVisivel,
                  decoration: InputDecoration(
                    labelText: "Nova senha (opcional)",
                    suffixIcon: IconButton(
                      icon: Icon(
                        _senhaVisivel ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _senhaVisivel = !_senhaVisivel;
                        });
                      },
                    ),
                  ),
                ),
                TextField(
                  controller: confirmarSenha,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Confirmar nova senha",
                  ),
                ),

                const SizedBox(height: 20),

                // Botão principal de ação com três estados:
                // 1) Desabilitado com spinner: operação em andamento
                // 2) Desabilitado com contador: aguardando timer de confirmação de e-mail
                // 3) Habilitado: pronto para salvar ou reenviar confirmação
                ElevatedButton(
                  onPressed: (_segundosRestantes == 0 && !_carregando)
                      ? _atualizar
                      : null,
                  child: _carregando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _segundosRestantes > 0
                              ? "Aguarde ${_segundosRestantes}s"
                              : (_emailAlteradoPendente
                                    ? "Reenviar confirmação"
                                    : "Salvar alterações"),
                        ),
                ),

                // Botão destrutivo de exclusão de conta, estilizado em vermelho
                // para destacar o risco da ação irreversível
                TextButton(
                  onPressed: _excluirConta,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text(
                    "Excluir conta",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Logo do app posicionada no canto inferior esquerdo da tela,
          // sobreposta ao conteúdo via Stack para não ocupar espaço no layout
          Positioned(
            bottom: 25, // Margem do fundo
            left: 25, // Margem da esquerda
            child: Image.asset('assets/images/titulo.webp', width: 150),
          ),
        ],
      ),
      // Botões flutuantes de controle de zoom, alinhados à direita.
      // Desabilitados visualmente (cinza) quando nos limites mínimo (0) ou máximo (2).
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Botão para diminuir o zoom; desabilitado quando já está no nível mínimo (0)
          FloatingActionButton(
            heroTag: "btn_diminuir",
            // Desabilita visualmente se chegar no limite 0
            onPressed: _nivelZoom > 0 ? () => _atualizarZoom(false) : null,
            backgroundColor: _nivelZoom > 0 ? null : Colors.grey.shade300,
            shape: const CircleBorder(),
            child: Text(
              "A-",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _nivelZoom > 0 ? null : Colors.grey.shade600,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Botão para aumentar o zoom; desabilitado quando já está no nível máximo (2)
          FloatingActionButton(
            heroTag: "btn_aumentar",
            // Desabilita visualmente se chegar no limite 2
            onPressed: _nivelZoom < 2 ? () => _atualizarZoom(true) : null,
            backgroundColor: _nivelZoom < 2 ? null : Colors.grey.shade300,
            shape: const CircleBorder(),
            child: Text(
              "A+",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _nivelZoom < 2 ? null : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}