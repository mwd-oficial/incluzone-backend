import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final senha = TextEditingController();
  bool _senhaVisivel = false;
  bool _navegou = false;
  Timer? _timer;
  int _segundosRestantes = 0;
  bool _emailEnviado = false; // Para saber se trocamos o texto do botão
  bool _carregandoRecuperacao = false; // Nova variável
  late final StreamSubscription authSub;
  int _nivelZoom = 0;

  final service = SupabaseService();

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
    authSub = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) async {
      final session = data.session;
      final event = data.event;

      if (event == AuthChangeEvent.passwordRecovery && !_navegou) {
        _navegou = true;

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/redefinir_senha');
        }
        return;
      }

      if (session != null && !_navegou) {
        _navegou = true;

        await service.garantirPerfilGoogle();

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/');
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    authSub.cancel();
    email.dispose();
    senha.dispose();
    super.dispose();
  }

  Future<void> _atualizarZoom(bool aumentar) async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      if (aumentar && _nivelZoom < 2) {
        _nivelZoom++;
      } else if (!aumentar && _nivelZoom > 0) {
        _nivelZoom--;
      }
    });

    // Salva no disco
    await prefs.setInt('nivel_zoom', _nivelZoom);

    // ESTA É A PARTE QUE FALTA:
    // Acessa o estado do MyApp através da chave global e chama o método de atualização
    myAppKey.currentState?.atualizarEscala(_nivelZoom);
  }

  Future<void> _carregarConfiguracoesIniciais() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    });
  }

  Future<bool> _temInternet() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return false;
    }
    // Opcional: Checagem real de DNS
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

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

  Future<void> _fazerLogin() async {
    final emailText = email.text.trim();
    final senhaText = senha.text.trim();

    if (!(await _temInternet())) {
      if (mounted) {
        _mostrarDialogo(
          "Sem Conexão",
          "Parece que você está offline. Verifique sua conexão com a internet e tente novamente.",
        );
      }
      return; // Interrompe a execução aqui
    }

    if (emailText.isEmpty || senhaText.isEmpty) {
      _mostrarDialogo("Campos obrigatórios", "Preencha o email e a senha.");
      return;
    }

    try {
      await service.login(emailText, senhaText);
    } catch (e) {
      _mostrarDialogo("Erro no login", "Email ou senha inválidos.");
    }
  }

  void _iniciarTimer() {
    setState(() {
      _segundosRestantes = 60;
      _emailEnviado = true;
    });

    _timer?.cancel(); // Cancela timer anterior se existir
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_segundosRestantes == 0) {
        timer.cancel();
        setState(() {
          // Opcional: manter _emailEnviado como true para o texto ser "Reenviar"
          // em vez de "Esqueci a senha"
        });
      } else {
        setState(() {
          _segundosRestantes--;
        });
      }
    });
  }

  Future<void> _recuperarSenha() async {
    final emailText = email.text.trim();

    if (emailText.isEmpty) {
      _mostrarDialogo(
        "Email obrigatório",
        "Digite seu email para recuperar a senha.",
      );
      return;
    }

    // Inicia o carregamento
    setState(() => _carregandoRecuperacao = true);

    try {
      final bool existe = await Supabase.instance.client.rpc(
        'verificar_email_existe',
        params: {'email_input': emailText},
      );

      if (!existe) {
        setState(() => _carregandoRecuperacao = false); // Para o loader
        _mostrarDialogo("Erro", "E-mail não cadastrado.");
        return;
      }

      await Supabase.instance.client.auth.resetPasswordForEmail(
        emailText,
        redirectTo: 'io.supabase.flutter://login-callback',
      );

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
      // Finaliza o carregamento independente de sucesso ou erro
      if (mounted) {
        setState(() => _carregandoRecuperacao = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text("Login")),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: "Email"),
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
                      onPressed: () {
                        setState(() {
                          _senhaVisivel = !_senhaVisivel;
                        });
                      },
                    ),
                  ),
                ),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    // Desabilita se estiver carregando ou se o timer estiver rodando
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

                ElevatedButton(
                  onPressed: _fazerLogin,
                  child: const Text("Entrar"),
                ),

                const SizedBox(height: 20),
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
          Positioned(
            bottom: 25, // Margem do fundo
            left: 25, // Margem da esquerda
            child: Image.asset('assets/images/titulo.webp', width: 150),
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Botão A-
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

          // Botão A+
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
