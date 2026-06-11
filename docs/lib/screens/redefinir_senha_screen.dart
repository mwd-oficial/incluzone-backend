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
import 'dart:io';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tela responsável por permitir que o usuário defina uma nova senha
/// após acessar o aplicativo através de um link de recuperação de senha
/// enviado por e-mail (fluxo de "esqueci minha senha" do Supabase Auth).
class RedefinirSenhaScreen extends StatefulWidget {
  const RedefinirSenhaScreen({super.key});

  @override
  State<RedefinirSenhaScreen> createState() => _RedefinirSenhaScreenState();
}

class _RedefinirSenhaScreenState extends State<RedefinirSenhaScreen> {
  /// Usuário atualmente autenticado na sessão do Supabase (obtido via
  /// o link de recuperação que abriu o app).
  final user = Supabase.instance.client.auth.currentUser;

  /// Controla o campo de texto da nova senha.
  final senha = TextEditingController();

  /// Controla o campo de texto de confirmação da nova senha.
  final confirmarSenha = TextEditingController();

  /// Nível de zoom/acessibilidade aplicado à interface (0 = padrão, até 2 = máximo).
  /// É persistido localmente via SharedPreferences e refletido globalmente no app.
  int _nivelZoom = 0;

  /// Controla se a senha digitada está visível (texto puro) ou oculta (pontos/asteriscos).
  bool _senhaVisivel = false;

  /// Instância do serviço que encapsula chamadas ao Supabase.
  final service = SupabaseService();

  @override
  void initState() {
    super.initState();

    // Carrega o nível de zoom salvo anteriormente pelo usuário.
    _carregarConfiguracoesIniciais();

    // Escuta mudanças no estado de autenticação do Supabase.
    // É necessário monitorar o evento de "passwordRecovery" para confirmar
    // que o usuário chegou nesta tela através de um link válido de recuperação,
    // o que estabelece a sessão temporária usada para permitir a troca de senha.
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;

      if (event == AuthChangeEvent.passwordRecovery) {
        // usuário entrou via link de recuperação
        print("Modo recuperação ativado");
      }
    });
  }

  @override
  void dispose() {
    // Libera os recursos dos controllers para evitar vazamento de memória.
    senha.dispose();
    confirmarSenha.dispose();
    super.dispose();
  }

  /// Incrementa ou decrementa o nível de zoom da interface (limitado entre 0 e 2),
  /// persiste o novo valor em [SharedPreferences] e propaga a mudança para
  /// todo o aplicativo através da chave global [myAppKey].
  ///
  /// [aumentar] indica se o zoom deve ser aumentado (`true`) ou diminuído (`false`).
  Future<void> _atualizarZoom(bool aumentar) async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      // Garante que o nível de zoom nunca ultrapasse os limites mínimo (0) e máximo (2).
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

  /// Lê o nível de zoom previamente salvo em [SharedPreferences] (ou 0, caso
  /// não exista nenhum valor salvo) e atualiza o estado da tela.
  Future<void> _carregarConfiguracoesIniciais() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    });
  }

  /// Verifica se o dispositivo possui conexão ativa com a internet.
  ///
  /// Primeiro checa o status de conectividade do sistema (Wi-Fi/dados móveis);
  /// em seguida, faz uma checagem real resolvendo um DNS conhecido (google.com)
  /// para confirmar que a conexão de fato permite acesso à internet, evitando
  /// falsos positivos de conexões "conectadas" mas sem internet de fato.
  ///
  /// Retorna `true` se houver internet utilizável, `false` caso contrário.
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

  /// Valida as regras de negócio para a nova senha informada.
  ///
  /// A validação só é executada se o campo de senha não estiver vazio
  /// (permitindo, por exemplo, que outros fluxos que usem esta tela sem
  /// exigir troca de senha não sejam bloqueados).
  ///
  /// Regras exigidas para a senha:
  /// - Mínimo de 8 caracteres;
  /// - Pelo menos 1 letra maiúscula;
  /// - Pelo menos 1 número;
  /// - Pelo menos 1 caractere especial;
  /// - Deve ser igual ao valor digitado no campo de confirmação.
  ///
  /// Retorna `true` se os campos forem válidos (ou se a senha estiver vazia),
  /// e `false` caso alguma regra seja violada (exibindo um diálogo explicativo).
  bool _validarCampos() {
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
          "A senha deve ter:\n"
              "- Pelo menos 8 caracteres\n"
              "- Pelo menos 1 letra maiúscula\n"
              "- Pelo menos 1 número\n"
              "- Pelo menos 1 caractere especial",
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

  /// Executa o fluxo completo de atualização da senha do usuário:
  ///
  /// 1. Valida os campos preenchidos via [_validarCampos];
  /// 2. Verifica se há conexão com a internet via [_temInternet];
  /// 3. Confirma se existe uma sessão ativa válida (proveniente do link
  ///    de recuperação de senha);
  /// 4. Chama a API do Supabase para atualizar a senha do usuário;
  /// 5. Em caso de sucesso, exibe uma mensagem de confirmação, encerra
  ///    a sessão (forçando novo login com a senha atualizada) e navega
  ///    para a tela de login.
  ///
  /// Trata especificamente o erro do Supabase que ocorre quando a nova
  /// senha é igual à senha anterior, traduzindo a mensagem para o usuário.
  Future<void> _atualizar() async {
    if (!_validarCampos()) return;

    if (!(await _temInternet())) {
      if (mounted) {
        _mostrarDialogo(
          "Sem Conexão",
          "Parece que você está offline. Verifique sua conexão com a internet e tente novamente.",
        );
      }
      return; // Interrompe a execução aqui
    }

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        _mostrarDialogo("Sessão inválida", "Abra o link do email novamente.");
        return;
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: senha.text.trim()),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Senha atualizada com sucesso! Faça login."),
          ),
        );
        await Supabase.instance.client.auth.signOut();
        Navigator.pushReplacementNamed(context, '/login');
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
      _mostrarDialogo("Erro", "Falha ao atualizar: $e");
    }
  }

  /// Constrói a interface da tela de redefinição de senha, contendo:
  /// - Campos para nova senha (com opção de mostrar/ocultar) e confirmação;
  /// - Botão para salvar a nova senha;
  /// - Logo do app posicionado no canto inferior esquerdo;
  /// - Botões flutuantes (FABs) para aumentar/diminuir o nível de zoom da interface.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Evita que o teclado redimensione/empurre o layout ao abrir.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text("Redefinir Senha")),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: senha,
                  // Oculta o texto digitado quando _senhaVisivel for falso.
                  obscureText: !_senhaVisivel,
                  decoration: InputDecoration(
                    labelText: "Nova senha",
                    suffixIcon: IconButton(
                      icon: Icon(
                        _senhaVisivel ? Icons.visibility_off : Icons.visibility,
                      ),
                      // Alterna a visibilidade da senha ao tocar no ícone.
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
                  // Campo de confirmação sempre permanece oculto.
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Confirmar nova senha",
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _atualizar,
                  child: const Text("Salvar"),
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
      // Conjunto de botões flutuantes para controle de zoom/acessibilidade.
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