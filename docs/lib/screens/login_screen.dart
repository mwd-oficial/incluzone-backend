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
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tela de login do aplicativo.
///
/// Permite autenticação via email/senha, login social com Google,
/// recuperação de senha e ajuste do nível de zoom/escala da interface.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// Controlador do campo de texto de email.
  final email = TextEditingController();

  /// Controlador do campo de texto de senha.
  final senha = TextEditingController();

  /// Controla se a senha está visível (texto puro) ou oculta (pontos/asteriscos).
  bool _senhaVisivel = false;

  /// Garante que a navegação automática (após login/recuperação) ocorra apenas uma vez,
  /// evitando múltiplas chamadas de Navigator caso o stream emita vários eventos.
  bool _navegou = false;

  /// Timer utilizado para controlar a contagem regressiva do botão de reenvio
  /// do email de recuperação de senha.
  Timer? _timer;

  /// Quantidade de segundos restantes até liberar o botão de reenvio do email
  /// de recuperação de senha.
  int _segundosRestantes = 0;

  /// Indica se o email de recuperação de senha já foi enviado ao menos uma vez,
  /// usado para alterar o texto do botão entre "Esqueci a senha" e "Reenviar email".
  bool _emailEnviado = false;

  /// Indica se a requisição de recuperação de senha está em andamento,
  /// usado para exibir um indicador de carregamento e desabilitar o botão.
  bool _carregandoRecuperacao = false;

  /// Inscrição no stream de mudanças de estado de autenticação do Supabase.
  late final StreamSubscription authSub;

  /// Nível atual de zoom/escala da interface (0, 1 ou 2).
  int _nivelZoom = 0;

  /// Instância do serviço que encapsula as chamadas ao Supabase.
  final service = SupabaseService();

  @override
  void initState() {
    super.initState();

    // Carrega o nível de zoom salvo previamente pelo usuário.
    _carregarConfiguracoesIniciais();

    // Escuta mudanças no estado de autenticação (login, recuperação de senha, etc).
    authSub = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) async {
      final session = data.session;
      final event = data.event;

      // Caso o evento seja de recuperação de senha (usuário clicou no link do email),
      // redireciona para a tela de redefinição de senha.
      if (event == AuthChangeEvent.passwordRecovery && !_navegou) {
        _navegou = true;

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/redefinir_senha');
        }
        return;
      }

      // Caso exista uma sessão válida (login bem-sucedido, incluindo via Google),
      // garante que o perfil do usuário exista e navega para a tela principal.
      if (session != null && !_navegou) {
        _navegou = true;

        // Garante que, ao logar via Google pela primeira vez, o perfil do usuário
        // seja criado/atualizado no banco de dados.
        await service.garantirPerfilGoogle();

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/');
        }
      }
    });
  }

  @override
  void dispose() {
    // Libera os recursos para evitar vazamentos de memória.
    _timer?.cancel();
    authSub.cancel();
    email.dispose();
    senha.dispose();
    super.dispose();
  }

  /// Aumenta ou diminui o nível de zoom/escala da interface.
  ///
  /// [aumentar] define a direção: `true` para aumentar (limite máximo 2)
  /// e `false` para diminuir (limite mínimo 0).
  ///
  /// O novo valor é persistido em [SharedPreferences] e propagado para o
  /// estado global do aplicativo através da chave global [myAppKey], que
  /// aplica a nova escala em toda a árvore de widgets.
  Future<void> _atualizarZoom(bool aumentar) async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      if (aumentar && _nivelZoom < 2) {
        _nivelZoom++;
      } else if (!aumentar && _nivelZoom > 0) {
        _nivelZoom--;
      }
    });

    // Persiste o nível de zoom escolhido para que seja restaurado em futuras sessões.
    await prefs.setInt('nivel_zoom', _nivelZoom);

    // Acessa o estado do MyApp através da chave global e aplica a nova escala
    // de fonte/layout em todo o aplicativo.
    myAppKey.currentState?.atualizarEscala(_nivelZoom);
  }

  /// Carrega as configurações salvas anteriormente (nível de zoom) ao iniciar a tela.
  Future<void> _carregarConfiguracoesIniciais() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    });
  }

  /// Verifica se o dispositivo possui conexão ativa com a internet.
  ///
  /// Primeiro checa o status de conectividade do dispositivo (Wi-Fi/dados móveis)
  /// e, em seguida, realiza uma checagem real de DNS resolvendo o domínio
  /// "google.com" para confirmar que há acesso efetivo à internet (e não apenas
  /// uma conexão local sem saída para a web).
  ///
  /// Retorna `true` se houver internet disponível, `false` caso contrário.
  Future<bool> _temInternet() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return false;
    }
    // Checagem real de DNS para confirmar que a conexão tem acesso à internet.
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Exibe um diálogo simples de alerta com [titulo] e [mensagem],
  /// contendo apenas um botão "OK" para fechar.
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

  /// Realiza o processo de login com email e senha.
  ///
  /// Antes de tentar autenticar, valida se há conexão com a internet e se
  /// os campos obrigatórios foram preenchidos. Em caso de erro nas
  /// credenciais, exibe um diálogo informando que o email ou a senha
  /// são inválidos.
  Future<void> _fazerLogin() async {
    final emailText = email.text.trim();
    final senhaText = senha.text.trim();

    // Verifica conectividade antes de tentar a requisição, evitando erros
    // genéricos quando o usuário está offline.
    if (!(await _temInternet())) {
      if (mounted) {
        _mostrarDialogo(
          "Sem Conexão",
          "Parece que você está offline. Verifique sua conexão com a internet e tente novamente.",
        );
      }
      return; // Interrompe a execução aqui
    }

    // Validação básica de campos obrigatórios.
    if (emailText.isEmpty || senhaText.isEmpty) {
      _mostrarDialogo("Campos obrigatórios", "Preencha o email e a senha.");
      return;
    }

    try {
      await service.login(emailText, senhaText);
    } catch (e) {
      // Mensagem genérica para não expor detalhes técnicos do erro de autenticação.
      _mostrarDialogo("Erro no login", "Email ou senha inválidos.");
    }
  }

  /// Inicia (ou reinicia) o contador regressivo de 60 segundos que controla
  /// quando o usuário poderá solicitar um novo email de recuperação de senha.
  void _iniciarTimer() {
    setState(() {
      _segundosRestantes = 60;
      _emailEnviado = true;
    });

    _timer?.cancel(); // Cancela timer anterior se existir, evitando múltiplos timers ativos
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_segundosRestantes == 0) {
        timer.cancel();
        setState(() {
          // Mantém _emailEnviado como true para que o texto do botão
          // permaneça como "Reenviar email" em vez de "Esqueci a senha".
        });
      } else {
        setState(() {
          _segundosRestantes--;
        });
      }
    });
  }

  /// Inicia o fluxo de recuperação de senha para o email informado.
  ///
  /// Primeiro valida se o campo de email foi preenchido. Em seguida,
  /// verifica via RPC no Supabase (`verificar_email_existe`) se o email
  /// está cadastrado, evitando enviar emails de recuperação para endereços
  /// inexistentes. Se o email existir, dispara o envio do link de redefinição
  /// de senha e inicia o contador de reenvio.
  Future<void> _recuperarSenha() async {
    final emailText = email.text.trim();

    if (emailText.isEmpty) {
      _mostrarDialogo(
        "Email obrigatório",
        "Digite seu email para recuperar a senha.",
      );
      return;
    }

    // Ativa o indicador de carregamento enquanto a operação está em andamento.
    setState(() => _carregandoRecuperacao = true);

    try {
      // Verifica no banco de dados se o email informado está cadastrado
      // antes de prosseguir com o envio do link de recuperação.
      final bool existe = await Supabase.instance.client.rpc(
        'verificar_email_existe',
        params: {'email_input': emailText},
      );

      if (!existe) {
        setState(() => _carregandoRecuperacao = false); // Para o loader
        _mostrarDialogo("Erro", "E-mail não cadastrado.");
        return;
      }

      // Solicita ao Supabase o envio do email com o link de redefinição de senha,
      // configurando o redirecionamento de volta para o app via deep link.
      await Supabase.instance.client.auth.resetPasswordForEmail(
        emailText,
        redirectTo: 'io.supabase.flutter://login-callback',
      );

      // Inicia a contagem regressiva para liberar um novo reenvio.
      _iniciarTimer();

      if (mounted) {
        _mostrarDialogo(
          "Verifique seu email",
          "Enviamos um link para redefinir sua senha.",
        );
      }
    } catch (e) {
      if (mounted) {
        _mostrarDialogo(
          "Erro",
          "Não foi possível enviar o email de recuperação.",
        );
      }
    } finally {
      // Finaliza o carregamento independentemente do resultado (sucesso ou erro).
      if (mounted) {
        setState(() => _carregandoRecuperacao = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Evita que o layout seja redimensionado quando o teclado aparece,
      // mantendo o posicionamento fixo dos elementos (ex: imagem no canto inferior).
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text("Login")),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Campo de entrada do email.
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: "Email"),
                ),

                // Campo de entrada da senha, com botão para alternar visibilidade.
                TextField(
                  controller: senha,
                  obscureText: !_senhaVisivel,
                  decoration: InputDecoration(
                    labelText: "Senha",
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

                // Botão "Esqueci a senha" / "Reenviar email", que fica desabilitado
                // enquanto o timer de 60 segundos está ativo ou durante o carregamento.
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    // Desabilita se estiver carregando ou se o timer estiver rodando.
                    onPressed:
                        (_segundosRestantes == 0 && !_carregandoRecuperacao)
                        ? _recuperarSenha
                        : null,
                    child: _carregandoRecuperacao
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.blue,
                            ),
                          )
                        : Text(
                            // Exibe a contagem regressiva, ou alterna entre
                            // "Esqueci a senha" e "Reenviar email" conforme
                            // se o email já foi enviado anteriormente.
                            _segundosRestantes > 0
                                ? "Reenviar email em ${_segundosRestantes}s"
                                : (_emailEnviado
                                      ? "Reenviar email"
                                      : "Esqueci a senha"),
                            style: TextStyle(
                              color: _segundosRestantes > 0
                                  ? Colors.grey
                                  : Colors.blue,
                            ),
                          ),
                  ),
                ),

                // Botão principal de login.
                ElevatedButton(
                  onPressed: _fazerLogin,
                  child: const Text("Entrar"),
                ),

                const SizedBox(height: 20),

                // Link para a tela de cadastro, para usuários que ainda não têm conta.
                GestureDetector(
                  onTap: () {
                    Navigator.pushReplacementNamed(context, '/cadastro');
                  },
                  child: Text.rich(
                    TextSpan(
                      text: "Ainda não tem conta? ",
                      style: const TextStyle(color: Colors.black87),
                      children: [
                        TextSpan(
                          text: "Cadastre-se",
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

                // Divisor visual "ou" entre o login tradicional e o login social.
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

                // Botão de login social via Google, utilizando OAuth do Supabase.
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

          // Logo/título do aplicativo posicionado no canto inferior esquerdo da tela.
          Positioned(
            bottom: 25, // Margem do fundo
            left: 25, // Margem da esquerda
            child: Image.asset('assets/images/titulo.webp', width: 150),
          ),
        ],
      ),

      // Botões flutuantes para ajuste de zoom/escala da interface (acessibilidade).
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Botão para diminuir o zoom (A-).
          FloatingActionButton(
            heroTag: "btn_diminuir",
            // Desabilita o botão (definindo onPressed como null) ao atingir o limite mínimo (0).
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

          // Botão para aumentar o zoom (A+).
          FloatingActionButton(
            heroTag: "btn_aumentar",
            // Desabilita o botão (definindo onPressed como null) ao atingir o limite máximo (2).
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