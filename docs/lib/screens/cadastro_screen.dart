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
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:io';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

/// Tela de cadastro de novos usuários.
///
/// Permite que o usuário se registre com e-mail e senha, ou através do
/// provedor OAuth do Google. Também oferece a opção de selecionar uma foto
/// de perfil antes de concluir o cadastro.
///
/// O fluxo principal é:
/// 1. O usuário preenche os campos e pressiona "Cadastrar".
/// 2. Um e-mail de verificação é enviado, e um timer de 60s é iniciado.
/// 3. Após verificar o e-mail, o listener de autenticação detecta a sessão
///    ativa e redireciona o usuário para a tela inicial.
class CadastroScreen extends StatefulWidget {
  const CadastroScreen({super.key});

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  /// Controladores para capturar o texto digitado em cada campo do formulário.
  final nome = TextEditingController();
  final email = TextEditingController();
  final senha = TextEditingController();
  final confirmarSenha = TextEditingController();

  /// Controla a visibilidade do texto no campo de senha (olho aberto/fechado).
  bool _senhaVisivel = false;

  /// Referência ao timer de cooldown para reenvio de e-mail.
  /// Armazenada para permitir o cancelamento explícito via [_timer?.cancel()].
  Timer? _timer;

  /// Contador regressivo em segundos exibido no botão durante o cooldown.
  /// Quando chega a 0, o botão de envio é reabilitado.
  int _segundosRestantes = 0;

  /// Indica se pelo menos uma tentativa de envio de e-mail já foi realizada
  /// nesta sessão. Muda o texto do botão de "Cadastrar" para "Reenviar".
  bool _emailEnviado = false;

  /// Armazena o e-mail utilizado no último envio bem-sucedido.
  /// Usado para detectar se o usuário corrigiu o e-mail antes de reenviar,
  /// o que requer um novo cadastro em vez de apenas um resend.
  String _ultimoEmailTentado = "";

  /// Sinaliza que uma operação assíncrona está em andamento,
  /// exibindo um indicador de progresso no botão e bloqueando novos cliques.
  bool _carregando = false;

  /// Armazena o arquivo de imagem selecionado pelo usuário da galeria.
  /// Permanece nulo até que o usuário escolha uma foto.
  File? _imagemSelecionada;

  /// Instância do seletor de imagens da galeria/câmera do dispositivo.
  final ImagePicker _picker = ImagePicker();

  /// Flag de uso único que evita que o listener de autenticação dispare
  /// múltiplas navegações caso o evento [onAuthStateChange] seja emitido
  /// mais de uma vez em sequência.
  bool _navegou = false;

  /// Subscription do stream de mudanças de estado de autenticação do Supabase.
  /// Mantida como variável de instância para ser cancelada no [dispose],
  /// prevenindo memory leaks e callbacks em widgets desmontados.
  late final StreamSubscription authSub;

  /// Instância do serviço que encapsula as chamadas ao Supabase
  /// (cadastro, upload de foto, perfil Google, etc.).
  final service = SupabaseService();

  /// Nível de zoom de acessibilidade atual (0 = padrão, 1 = médio, 2 = máximo).
  /// Persiste entre sessões via [SharedPreferences].
  int _nivelZoom = 0;

  @override
  void initState() {
    super.initState();
    // Carrega o nível de zoom salvo anteriormente para sincronizar a UI.
    _carregarConfiguracoesIniciais();

    // Escuta as mudanças de estado de autenticação em tempo real.
    // Este listener é a peça central do fluxo pós-cadastro: quando o usuário
    // clica no link de verificação de e-mail, o Supabase emite uma sessão ativa
    // aqui, e só então a navegação para a tela principal é executada.
    authSub = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) async {
      final session = data.session;

      // Só procede se houver uma sessão válida E se ainda não navegou,
      // evitando o problema de navegação dupla.
      if (session != null && !_navegou) {
        _navegou = true;

        // Garante que usuários vindos pelo Google tenham um nome de perfil
        // definido, pois o Google fornece um displayName que precisa ser
        // espelhado na tabela de perfis do Supabase.
        await service.garantirPerfilGoogle();

        // Se o usuário havia selecionado uma foto ANTES de verificar o e-mail,
        // o upload só é feito AQUI, pois o Supabase Storage exige uma sessão
        // autenticada ativa para autorizar a gravação do arquivo.
        if (_imagemSelecionada != null) {
          try {
            await service.uploadFotoPerfil(_imagemSelecionada!);
          } catch (e) {
            // Falha no upload de foto não é considerada crítica: o usuário
            // é redirecionado mesmo assim e pode alterar a foto depois.
            print("Erro ao subir foto no pós-cadastro: $e");
          }
        }

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/');
        }
      }
    });
  }

  @override
  void dispose() {
    // Cancela a subscription do stream para evitar que callbacks sejam
    // disparados após o widget ser removido da árvore, o que causaria erros
    // de "setState called after dispose".
    authSub.cancel();
    nome.dispose();
    email.dispose();
    senha.dispose();
    confirmarSenha.dispose();
    super.dispose();
  }

  /// Atualiza o nível de zoom de acessibilidade e persiste a escolha.
  ///
  /// Incrementa ou decrementa [_nivelZoom] dentro dos limites permitidos
  /// (0 a 2), salva o novo valor em [SharedPreferences] e notifica o
  /// widget raiz [MyApp] para que a escala global seja recalculada.
  ///
  /// - [aumentar]: `true` para aumentar a fonte, `false` para diminuir.
  Future<void> _atualizarZoom(bool aumentar) async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      if (aumentar && _nivelZoom < 2) {
        _nivelZoom++;
      } else if (!aumentar && _nivelZoom > 0) {
        _nivelZoom--;
      }
    });

    // Persiste o nível escolhido para que seja restaurado na próxima abertura.
    await prefs.setInt('nivel_zoom', _nivelZoom);

    // Acessa o estado do MyApp através da chave global e chama o método de
    // atualização, propagando a mudança de escala para toda a aplicação
    // sem precisar reiniciar ou recriar a árvore de widgets.
    myAppKey.currentState?.atualizarEscala(_nivelZoom);
  }

  /// Lê o nível de zoom previamente salvo em [SharedPreferences] e
  /// atualiza o estado local para que os botões A+/A- reflitam a
  /// configuração atual ao abrir a tela.
  Future<void> _carregarConfiguracoesIniciais() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    });
  }

  /// Abre o seletor de imagens da galeria do dispositivo e armazena
  /// o arquivo selecionado em [_imagemSelecionada].
  ///
  /// A qualidade é limitada a 70% para reduzir o tamanho do arquivo
  /// antes do upload para o Supabase Storage, economizando banda e
  /// espaço de armazenamento sem perda visual perceptível ao usuário.
  Future<void> _selecionarImagem() async {
    final XFile? imagem = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (imagem != null) {
      setState(() {
        _imagemSelecionada = File(imagem.path);
      });
    }
  }

  /// Inicia o timer de cooldown de 60 segundos para reenvio de e-mail.
  ///
  /// Cancela qualquer timer anterior ativo antes de criar um novo,
  /// garantindo que múltiplos envios rápidos não criem timers concorrentes.
  /// A cada segundo, decrementa [_segundosRestantes] e chama [setState]
  /// para atualizar o contador exibido no botão.
  void _iniciarTimer() {
    setState(() {
      _segundosRestantes = 60;
      _emailEnviado = true;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_segundosRestantes == 0) {
        // Quando o timer zera, cancela a si mesmo. O botão será reabilitado
        // pelo próximo [setState] disparado em qualquer outra interação,
        // ou pela chamada explícita de [setState] abaixo.
        timer.cancel();
        if (mounted) setState(() {});
      } else {
        if (mounted) {
          setState(() {
            _segundosRestantes--;
          });
        }
      }
    });
  }

  /// Verifica se o dispositivo possui acesso real à internet.
  ///
  /// A checagem é feita em duas etapas para maior confiabilidade:
  /// 1. Verifica o estado da interface de rede via [Connectivity] (rápido,
  ///    mas pode ser enganoso em redes sem acesso externo, como captive portals).
  /// 2. Realiza uma resolução de DNS para `google.com` para confirmar que
  ///    há acesso real à internet, não apenas conexão local.
  ///
  /// Retorna `true` se a conexão estiver disponível, `false` caso contrário.
  Future<bool> _temInternet() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return false;
    }
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Exibe um diálogo de alerta modal com um título e uma mensagem.
  ///
  /// Utilizado para todos os feedbacks de erro e confirmação da tela,
  /// centralizando a lógica de exibição e evitando repetição de código.
  ///
  /// - [context]: O contexto do widget pai para ancoragem do diálogo.
  /// - [titulo]: Texto exibido em destaque no topo do diálogo.
  /// - [mensagem]: Corpo explicativo do diálogo.
  void _mostrarDialogo(BuildContext context, String titulo, String mensagem) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK"),
          ),
        ],
      ),
    );
  }

  /// Valida todos os campos do formulário antes de tentar o cadastro.
  ///
  /// As regras de validação aplicadas são:
  /// - Nenhum campo pode estar vazio.
  /// - O e-mail deve conter "@" e ".".
  /// - A senha deve ter no mínimo 8 caracteres, uma letra maiúscula,
  ///   um número e um caractere especial (política de senha forte).
  /// - Os campos "senha" e "confirmar senha" devem ser idênticos.
  ///
  /// Exibe um diálogo de erro descritivo ao primeiro critério que falhar.
  ///
  /// Retorna `true` se todos os campos forem válidos, `false` caso contrário.
  bool _validarCampos(BuildContext context) {
    if (nome.text.trim().isEmpty ||
        email.text.trim().isEmpty ||
        senha.text.trim().isEmpty) {
      _mostrarDialogo(context, "Erro", "Todos os campos são obrigatórios.");
      return false;
    }

    if (!email.text.contains("@") || !email.text.contains(".")) {
      _mostrarDialogo(context, "Erro", "Digite um e-mail válido.");
      return false;
    }

    final senhaValue = senha.text;

    // Expressões regulares para checar cada critério de complexidade da senha.
    final temMaiuscula = RegExp(r'[A-Z]').hasMatch(senhaValue);
    final temNumero = RegExp(r'[0-9]').hasMatch(senhaValue);
    final temEspecial = RegExp(
      r'[!@#\$&*~%^()_\-+=<>?/\\|{}[\]:;.,]',
    ).hasMatch(senhaValue);

    if (senha.text.length < 8 || !temMaiuscula || !temNumero || !temEspecial) {
      _mostrarDialogo(
        context,
        "Senha fraca",
        "A senha deve ter:\n"
            "- Pelo menos 8 caracteres\n"
            "- Pelo menos 1 letra maiúscula\n"
            "- Pelo menos 1 número\n"
            "- Pelo menos 1 caractere especial",
      );
      return false;
    }

    if (senha.text != confirmarSenha.text) {
      _mostrarDialogo(context, "Erro", "As senhas não coincidem.");
      return false;
    }

    return true;
  }

  /// Ponto de entrada central para as ações do botão principal da tela.
  ///
  /// Este método gerencia dois cenários distintos baseados no estado [_emailEnviado]:
  ///
  /// **Cenário 1 - Primeiro envio ([_emailEnviado] == false):**
  /// Valida os campos, chama o serviço de cadastro e inicia o timer de cooldown.
  ///
  /// **Cenário 2 - Reenvio ([_emailEnviado] == true):**
  /// Verifica se o e-mail foi alterado desde o último envio.
  /// - Se mudou: cria um novo registro de usuário com o e-mail corrigido,
  ///   pois o Supabase não permite atualizar o e-mail de um usuário não confirmado.
  /// - Se não mudou: usa o endpoint `resend` do Supabase, que apenas
  ///   reencaminha o link de verificação sem criar um novo usuário.
  ///
  /// A flag [_carregando] garante que o método não seja chamado em paralelo
  /// caso o usuário toque rapidamente no botão múltiplas vezes.
  Future<void> _processarAcaoEmail() async {
    if (_carregando) return;

    final emailAtual = email.text.trim();

    if (emailAtual.isEmpty) {
      _mostrarDialogo(context, "Erro", "Digite o e-mail.");
      return;
    }

    if (!(await _temInternet())) {
      _mostrarDialogo(context, "Sem Conexão", "Verifique sua internet.");
      return;
    }

    setState(() => _carregando = true);

    try {
      if (!_emailEnviado) {
        // --- LÓGICA DE CADASTRO INICIAL ---
        if (!_validarCampos(context)) {
          // Interrompe o fluxo se a validação local falhar,
          // sem chegar a fazer qualquer chamada de rede.
          setState(() => _carregando = false);
          return;
        }
        await service.cadastrarUsuario(nome.text, emailAtual, senha.text);
        _ultimoEmailTentado = emailAtual;

        // Encerra o loading ANTES de iniciar o timer para evitar que o botão
        // fique brevemente habilitado entre os dois setState.
        setState(() => _carregando = false);
        _iniciarTimer();

        _mostrarDialogo(
          context,
          "Verifique seu e-mail",
          "Link enviado para $emailAtual",
        );
      } else {
        try {
          if (emailAtual != _ultimoEmailTentado) {
            // O e-mail foi corrigido pelo usuário. Não é possível atualizar
            // o e-mail de um usuário "fantasma" (não confirmado) no Supabase,
            // então a solução é criar um novo registro com o endereço correto.
            await service.cadastrarUsuario(nome.text, emailAtual, senha.text);
            _ultimoEmailTentado = emailAtual;
            _mostrarDialogo(
              context,
              "E-mail Corrigido",
              "Novo link enviado para $emailAtual",
            );
          } else {
            // O e-mail não mudou: usa o `resend` do Supabase, que é um
            // endpoint leve que só reenvia o OTP de confirmação de signup
            // sem necessidade de uma sessão autenticada.
            await Supabase.instance.client.auth.resend(
              type: OtpType.signup,
              email: emailAtual,
            );
            _mostrarDialogo(
              context,
              "E-mail Reenviado",
              "Confira sua caixa de entrada.",
            );
          }

          setState(() => _carregando = false);
          _iniciarTimer();
        } catch (e) {
          setState(() => _carregando = false);
          // Cobre o caso em que o usuário tenta "corrigir" para um e-mail
          // que já possui uma conta confirmada, o que geraria um erro de
          // duplicidade no Supabase.
          _mostrarDialogo(
            context,
            "Erro",
            "Não foi possível reenviar. Verifique os dados.",
          );
        }
      }
    } on AuthException catch (e) {
      setState(() => _carregando = false);
      // Delega o tratamento de erros específicos do Supabase Auth para
      // um método dedicado, mantendo este método mais legível.
      _tratarErroAuth(e);
    } catch (e) {
      setState(() => _carregando = false);
      _mostrarDialogo(context, "Erro", "Falha na operação.");
    } finally {
      // Cláusula de segurança: garante que [_carregando] seja sempre
      // revertido para `false`, mesmo que algum caminho de código acima
      // tenha lançado uma exceção não prevista antes de resetar o estado.
      if (mounted && _carregando) setState(() => _carregando = false);
    }
  }

  /// Trata exceções do tipo [AuthException] lançadas pelo Supabase.
  ///
  /// Interpreta a mensagem de erro para apresentar um feedback mais
  /// amigável e contextualizado ao usuário em vez da mensagem técnica
  /// retornada pela API.
  ///
  /// - [e]: A exceção de autenticação capturada no bloco `catch`.
  void _tratarErroAuth(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('already') || msg.contains('registered')) {
      _mostrarDialogo(
        context,
        "Conta já existe",
        "Este e-mail já está cadastrado.",
      );
    } else {
      _mostrarDialogo(context, "Erro", e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Impede que o layout seja redimensionado quando o teclado virtual
      // aparece, evitando overflow em telas menores.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text("Cadastro")),
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                const SizedBox(height: 10),

                // --- COMPONENTE DO AVATAR COM ÍCONE DE CÂMERA ---
                // Um único GestureDetector envolve todo o componente de avatar
                // para unificar o comportamento de toque: se não há imagem,
                // abre a galeria; se há imagem, remove-a. Isso evita a
                // necessidade de dois detectores separados e conflitantes.
                Center(
                  child: GestureDetector(
                    onTap: () {
                      if (_imagemSelecionada != null) {
                        // Se já tem imagem, o clique (na foto ou no X) remove e volta ao início
                        setState(() {
                          _imagemSelecionada = null;
                        });
                      } else {
                        // Se não tem imagem, abre o seletor
                        _selecionarImagem();
                      }
                    },
                    child: Stack(
                      children: [
                        // Avatar principal: exibe a imagem selecionada pelo usuário
                        // ou o avatar padrão da aplicação como fallback.
                        CircleAvatar(
                          radius: 60,
                          backgroundImage: _imagemSelecionada != null
                              ? FileImage(_imagemSelecionada!)
                              : null,
                          child: _imagemSelecionada == null
                              ? ClipOval(
                                  child: Image.asset(
                                    'assets/images/avatar.webp',
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : null,
                        ),
                        // Ícone de ação sobreposto no canto inferior direito do avatar.
                        // Muda para vermelho com ícone "X" quando há imagem selecionada,
                        // sinalizando visualmente ao usuário que o próximo toque irá removê-la.
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            backgroundColor: _imagemSelecionada != null
                                ? Colors.red
                                : Theme.of(context).primaryColor,
                            radius: 20,
                            child: Icon(
                              _imagemSelecionada != null
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
                  decoration: InputDecoration(labelText: "Nome"),
                ),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: "Email"),
                ),
                TextField(
                  controller: senha,
                  obscureText: !_senhaVisivel,
                  decoration: InputDecoration(
                    labelText: "Senha",
                    suffixIcon: IconButton(
                      icon: Icon(
                        _senhaVisivel ? Icons.visibility_off : Icons.visibility,
                      ),
                      // Alterna a flag [_senhaVisivel], forçando a reconstrução
                      // do TextField com [obscureText] invertido.
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
                  decoration: InputDecoration(labelText: "Confirmar senha"),
                ),

                SizedBox(height: 20),

                // BOTÃO PRINCIPAL DE AÇÃO (CADASTRAR / REENVIAR)
                // O botão é desabilitado (onPressed: null) em dois casos:
                // 1. Durante uma operação assíncrona ([_carregando] == true).
                // 2. Durante o cooldown do timer ([_segundosRestantes] > 0).
                // O conteúdo visual muda dinamicamente para refletir o estado atual.
                SizedBox(
                  child: ElevatedButton(
                    onPressed: (_segundosRestantes == 0 && !_carregando)
                        ? _processarAcaoEmail
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
                                : (_emailEnviado ? "Reenviar" : "Cadastrar"),
                          ),
                  ),
                ),

                const SizedBox(height: 20),
                // Link de navegação para a tela de login, usando [pushReplacementNamed]
                // para remover a tela de cadastro da pilha de navegação, impedindo
                // que o usuário retorne a ela pelo botão "voltar".
                GestureDetector(
                  onTap: () {
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                  child: Text.rich(
                    TextSpan(
                      text: "Já tem conta? ",
                      style: const TextStyle(color: Colors.black87),
                      children: [
                        TextSpan(
                          text: "Faça o login",
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Divisor visual "ou" para separar as opções de cadastro
                // (e-mail/senha vs. OAuth), seguindo padrões de UX comuns
                // em telas de autenticação.
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: const [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text("ou", style: TextStyle(color: Colors.grey)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                ),

                // Botão de autenticação via Google OAuth.
                // O [redirectTo] aponta para o deep link registrado no Supabase
                // e no manifesto do app, garantindo que o callback de autenticação
                // retorne para dentro do aplicativo Flutter após o fluxo no browser.
                ElevatedButton.icon(
                  icon: Image.asset(
                    'assets/images/google_logo.webp',
                    width: 24,
                    height: 24,
                  ),
                  label: const Text("Continuar com Google"),
                  onPressed: () async {
                    await Supabase.instance.client.auth.signInWithOAuth(
                      OAuthProvider.google,
                      redirectTo: 'io.supabase.flutter://login-callback',
                    );
                  },
                ),
              ],
            ),
          ),
          // Logo da aplicação posicionada de forma absoluta no canto inferior
          // esquerdo da tela, fora do fluxo de rolagem da Column principal.
          Positioned(
            bottom: 25,
            left: 25,
            child: Image.asset('assets/images/titulo.webp', width: 150),
          ),
        ],
      ),
      // Botões flutuantes de acessibilidade para ajuste de zoom (A- e A+).
      // Cada botão é desabilitado e fica cinza quando atinge o limite do
      // seu respectivo extremo (0 para diminuir, 2 para aumentar), fornecendo
      // feedback visual claro de que o limite foi alcançado.
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "btn_diminuir",
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

          FloatingActionButton(
            heroTag: "btn_aumentar",
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