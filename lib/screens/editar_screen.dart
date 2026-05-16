import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import 'dart:async';
import '../main.dart';
import 'package:image_picker/image_picker.dart';

class EditarScreen extends StatefulWidget {
  const EditarScreen({super.key});

  @override
  State<EditarScreen> createState() => _EditarScreenState();
}

class _EditarScreenState extends State<EditarScreen> {
  final nome = TextEditingController();
  final email = TextEditingController();
  final senha = TextEditingController();
  final confirmarSenha = TextEditingController();
  final SupabaseService _supabaseService = SupabaseService();
  Timer? _timer;
  int _segundosRestantes = 0;
  bool _emailAlteradoPendente = false;
  String _ultimoEmailTentaAlterar = "";
  bool _carregando = false;
  File? _imagemSelecionada;
  String? _urlImagemExistente;
  final ImagePicker _picker = ImagePicker();
  late final StreamSubscription<AuthState> _authSubscription;

  bool _senhaVisivel = false;
  int _nivelZoom = 0;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
    _carregarDadosUsuario();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      final user = data.session?.user;
      // Se o email atual for igual ao que tentamos alterar e não houver mais 'newEmail' pendente
      if (user != null &&
          user.email == _ultimoEmailTentaAlterar &&
          user.newEmail == null &&
          _emailAlteradoPendente) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("E-mail confirmado com sucesso!")),
          );
          Navigator.pushReplacementNamed(context, '/');
        }
      }
    });
  }

  @override
  void dispose() {
    nome.dispose();
    email.dispose();
    senha.dispose();
    confirmarSenha.dispose();
    _authSubscription.cancel();
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

  Future<void> _carregarConfiguracoesIniciais() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    });
  }

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

          if (_emailAlteradoPendente &&
              user.email == _ultimoEmailTentaAlterar) {
            _emailAlteradoPendente = false;
          }
        });
      }
    } catch (e) {
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

  void _iniciarTimer() {
    setState(() {
      _segundosRestantes = 60;
    });
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_segundosRestantes == 0) {
        timer.cancel();
        // Opcional: resetar estado pendente se o tempo acabar sem confirmação
      } else {
        if (mounted) {
          setState(() => _segundosRestantes--);

          // A cada 5 segundos, verificamos no Supabase se o email foi confirmado
          if (_segundosRestantes % 3 == 0 && _emailAlteradoPendente) {
            try {
              // Força a atualização da sessão e busca dados do servidor
              final response = await Supabase.instance.client.auth.getUser();
              final user = response.user;

              // Se o email atual for o novo e o campo 'newEmail' sumiu, confirmou!
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

  Future<void> _atualizar() async {
    if (_carregando || _segundosRestantes > 0) return;
    if (!_validarCampos()) return;

    if (!(await _temInternet())) {
      _mostrarDialogo("Sem Conexão", "Verifique sua internet.");
      return;
    }

    setState(() => _carregando = true);

    try {
      String? novaUrlAvatar = _urlImagemExistente;

      if (_imagemSelecionada != null) {
        novaUrlAvatar = await _supabaseService.atualizarFotoPerfil(
          _imagemSelecionada!,
        );
      }

      final auth = Supabase.instance.client.auth;
      final userAntes = auth.currentUser;
      final emailNovo = email.text.trim();

      final Map<String, dynamic> userMetadata = {'name': nome.text.trim()};
      if (novaUrlAvatar != null) {
        userMetadata['avatar_url'] = novaUrlAvatar;
      }

      // 1. Faz a atualização
      await auth.updateUser(
        UserAttributes(
          email: emailNovo,
          password: senha.text.isNotEmpty ? senha.text : null,
          data: userMetadata,
        ),
        emailRedirectTo: 'io.supabase.flutter://login-callback',
      );

      // 2. Busca o estado atualizado do usuário para ver se o e-mail entrou em "espera"
      final response = await auth.getUser();
      final userDepois = response.user;

      // Verificamos se existe um 'new_email' no objeto do usuário.
      // O Supabase preenche esse campo enquanto o link não é clicado.
      bool trocaDeEmailPendente = userDepois?.newEmail != null;

      if (trocaDeEmailPendente) {
        setState(() {
          _emailAlteradoPendente = true;
          _ultimoEmailTentaAlterar = emailNovo;
        });
        _iniciarTimer();

        _mostrarDialogo(
          "Confirme seu e-mail",
          "Para concluir a alteração para $emailNovo, você deve clicar no link enviado para o seu e-mail.",
        );
      } else {
        // 3. SÓ LEVA PARA HOME SE NÃO HOUVER E-MAIL PENDENTE
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Perfil atualizado com sucesso!")),
          );
          // Só volta para a home se não estivermos esperando confirmação de e-mail
          Navigator.pushReplacementNamed(context, '/');
        }
      }
    } on AuthException catch (e) {
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

    if (confirmar != true) return;

    try {
      // 🔥 chama Edge Function (você precisa criar no Supabase)
      final user = Supabase.instance.client.auth.currentUser;

      await Supabase.instance.client.functions.invoke(
        'delete-user',
        body: {'userId': user?.id},
      );

      await Supabase.instance.client.auth.signOut();

      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      _mostrarDialogo("Erro", "Não foi possível excluir a conta: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      // Verifica se existe alguma imagem sendo exibida (local ou do Supabase)
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
                        // Avatar Principal
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
                        // Botão do Canto (Dinâmico)
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

                // 🔴 BOTÃO EXCLUIR CONTA
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
