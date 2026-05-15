import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:io';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CadastroScreen extends StatefulWidget {
  const CadastroScreen({super.key});

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  final nome = TextEditingController();
  final email = TextEditingController();
  final senha = TextEditingController();
  final confirmarSenha = TextEditingController();
  bool _senhaVisivel = false;
  Timer? _timer;
  int _segundosRestantes = 0;
  bool _emailEnviado = false;
  String _ultimoEmailTentado = ""; // Para comparar se o e-mail mudou
  bool _carregando = false;

  bool _navegou = false;
  late final StreamSubscription authSub;

  final service = SupabaseService();
  int _nivelZoom = 0;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
    authSub = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) async {
      final session = data.session;

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
    authSub.cancel();
    nome.dispose();
    email.dispose();
    senha.dispose();
    confirmarSenha.dispose();
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

  void _iniciarTimer() {
    setState(() {
      _segundosRestantes = 60;
      _emailEnviado = true;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_segundosRestantes == 0) {
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

  Future<void> _processarAcaoEmail() async {
    if (_carregando) return;

    final emailAtual = email.text.trim();

    // Validação básica de campo antes de tentar qualquer coisa
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
        // --- LOGICA DE CADASTRO INICIAL ---
        if (!_validarCampos(context)) {
          setState(() => _carregando = false);
          return;
        }
        await service.cadastrarUsuario(nome.text, emailAtual, senha.text);
        _ultimoEmailTentado = emailAtual;

        // Primeiro paramos o loading, depois iniciamos o timer
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
            // Se o e-mail mudou, não tentamos atualizar o usuário "fantasma"
            // Fazemos um novo cadastro com os dados corretos
            await service.cadastrarUsuario(nome.text, emailAtual, senha.text);
            _ultimoEmailTentado = emailAtual;
            _mostrarDialogo(
              context,
              "E-mail Corrigido",
              "Novo link enviado para $emailAtual",
            );
          } else {
            // Se for o mesmo e-mail, usamos o resend (que não exige sessão)
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
          // Trate o erro de "User already registered" aqui se o usuário
          // tentar corrigir para um e-mail que já existe de verdade
          _mostrarDialogo(
            context,
            "Erro",
            "Não foi possível reenviar. Verifique os dados.",
          );
        }
      }
    } on AuthException catch (e) {
      setState(() => _carregando = false);
      _tratarErroAuth(e);
    } catch (e) {
      setState(() => _carregando = false);
      _mostrarDialogo(context, "Erro", "Falha na operação.");
    } finally {
      // Garantia final de que o load sairá da tela
      if (mounted && _carregando) setState(() => _carregando = false);
    }
  }

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
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text("Cadastro")),
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                // BOTÃO GOOGLE (AGORA NO TOPO)
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

                // TEXTO "OU" CENTRALIZADO
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

                // BOTÃO CADASTRAR
                SizedBox(
                  child: ElevatedButton(
                    onPressed: (_segundosRestantes == 0 && !_carregando)
                        ? _processarAcaoEmail
                        : null, // Desabilita o botão se estiver carregando ou no timer
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
