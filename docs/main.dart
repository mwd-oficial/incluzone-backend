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
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/redefinir_senha_screen.dart';
import 'screens/cadastro_screen.dart';
import 'screens/editar_screen.dart';
import 'screens/pre_registro_vagas_screen.dart';
import 'screens/registro_vagas_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/historico_screen.dart';
import 'screens/sobre_screen.dart';

/// Ponto de entrada principal da aplicação.
///
/// A anotação `async` é necessária pois realizamos operações assíncronas
/// antes de iniciar o app, como a inicialização do Supabase.
void main() async {
  // Garante que os bindings do Flutter (comunicação com a engine nativa)
  // estejam prontos antes de qualquer chamada assíncrona ou de plugin.
  // Obrigatório quando `main()` é async e usa plugins antes do `runApp`.
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o cliente Supabase de forma global para toda a aplicação.
  // A `url` e a `anonKey` identificam e autenticam o projeto no Supabase.
  // A `anonKey` é segura para ser exposta no cliente, pois as permissões
  // de acesso real são controladas pelas Row Level Security (RLS) policies
  // configuradas no banco de dados.
  await Supabase.initialize(
    url: 'https://xyrzopysmpaziohhnyer.supabase.co',
    anonKey: 'sb_publishable_3cHH3MygneqFnUnJJtQ32Q_gjoMqtE-',
  );

  // Trava a orientação do dispositivo para apenas retrato (portrait).
  // Isso garante consistência visual do layout em toda a aplicação,
  // evitando a necessidade de tratar layouts para modo paisagem (landscape).
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Inicia a aplicação Flutter, passando a `myAppKey` global para que
  // o estado do `MyApp` possa ser acessado de qualquer ponto da árvore de widgets.
  runApp(MyApp(key: myAppKey));
}

/// Chave global que fornece acesso direto ao [MyAppState] de qualquer lugar
/// da aplicação, sem a necessidade de passar o contexto pela árvore de widgets.
///
/// Uso principal: permitir que telas filhas (ex: tela de configurações) chamem
/// `myAppKey.currentState?.atualizarEscala(novoNivel)` para alterar o zoom
/// global da aplicação em tempo real.
final GlobalKey<MyAppState> myAppKey = GlobalKey<MyAppState>();

/// Widget raiz da aplicação, responsável por configurar o [MaterialApp]
/// e gerenciar o estado global de escala de texto (acessibilidade de zoom).
///
/// É um [StatefulWidget] pois precisa reagir a mudanças no fator de escala
/// de texto, reconstruindo toda a árvore de widgets quando o zoom é alterado.
class MyApp extends StatefulWidget {
  /// A `key` é recebida e repassada ao `super` para que a [GlobalKey] declarada
  /// em [myAppKey] seja corretamente vinculada a este widget, possibilitando
  /// o acesso externo ao seu estado via `myAppKey.currentState`.
  MyApp({super.key});

  @override
  State<MyApp> createState() => MyAppState();
}

/// Estado do [MyApp], que gerencia o fator de escala de texto global.
///
/// Expõe o método público [atualizarEscala] para que outras partes da
/// aplicação possam alterar o nível de zoom e forçar a reconstrução
/// de toda a árvore de widgets com a nova escala.
class MyAppState extends State<MyApp> {
  /// Fator multiplicador aplicado ao tamanho base de todos os textos do app.
  ///
  /// Valor padrão `1.0` representa 100% (sem zoom). Cada nível de zoom
  /// acrescenta `0.2` a este fator (ex: nível 1 = 1.2x, nível 2 = 1.4x).
  double _fatorEscala = 1.0;

  @override
  void initState() {
    super.initState();
    // Carrega a preferência de zoom salva pelo usuário assim que o widget
    // é inserido na árvore, garantindo que a escala correta seja aplicada
    // desde o primeiro frame renderizado após a splash screen.
    _carregarEscala();
  }

  /// Lê o nível de zoom persistido no armazenamento local ([SharedPreferences])
  /// e atualiza o [_fatorEscala] de acordo.
  ///
  /// Caso nenhuma preferência tenha sido salva anteriormente, o valor padrão
  /// `0` é utilizado, resultando em um fator de escala de `1.0` (sem zoom).
  Future<void> _carregarEscala() async {
    final prefs = await SharedPreferences.getInstance();
    // Recupera o nível de zoom salvo. O operador `?? 0` garante o fallback
    // para o nível 0 caso a chave 'nivel_zoom' ainda não exista no storage.
    final nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    setState(() {
      // Converte o nível inteiro (0, 1, 2...) em um fator de escala decimal.
      // A fórmula `1.0 + (nivelZoom * 0.2)` garante que o nível 0 seja
      // neutro (1.0x) e cada nível adicional aumente 20% o tamanho do texto.
      _fatorEscala = 1.0 + (nivelZoom * 0.2);
    });
  }

  /// Atualiza o fator de escala de texto globalmente e reconstrói o app.
  ///
  /// Este método é público e deve ser chamado por telas de configuração
  /// através da referência `myAppKey.currentState?.atualizarEscala(nivel)`.
  /// O [setState] garante que o [MaterialApp] seja reconstruído com o novo
  /// [_fatorEscala], propagando a mudança para todos os widgets filhos.
  ///
  /// [nivelZoom] — Nível inteiro de zoom escolhido pelo usuário.
  /// O valor `0` representa a escala padrão (100%), e cada incremento
  /// de `1` aumenta a escala em 20%.
  void atualizarEscala(int nivelZoom) {
    setState(() {
      _fatorEscala = 1.0 + (nivelZoom * 0.2);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Remove o banner vermelho de "DEBUG" exibido em builds de desenvolvimento.
      debugShowCheckedModeBanner: false,
      title: 'IncluZone DB Test',
      // Define a rota inicial como '/splash', garantindo que a SplashScreen
      // seja sempre a primeira tela exibida ao abrir o aplicativo.
      initialRoute: '/splash',
      // Mapa de rotas nomeadas da aplicação. Centralizar as rotas aqui
      // facilita a manutenção e a navegação via `Navigator.pushNamed(context, '/rota')`.
      routes: {
        '/splash': (_) => SplashScreen(),
        '/': (_) => const HomeScreen(),
        '/login': (_) => const LoginScreen(),
        '/redefinir_senha': (_) => const RedefinirSenhaScreen(),
        '/cadastro': (_) => const CadastroScreen(),
        '/editar': (_) => const EditarScreen(),
        '/pre_registro_vagas': (_) => const PreRegistroVagasScreen(),
        '/registro_vagas': (_) => const RegistroVagasScreen(),
        '/historico': (_) => const HistoricoScreen(),
        '/sobre': (_) => const SobreScreen(),
      },
      // O `builder` intercepta a construção de todo widget filho do MaterialApp,
      // permitindo envolver a árvore inteira com configurações globais.
      // Aqui é o ponto ideal para aplicar o fator de escala de texto, pois
      // qualquer tela da aplicação será automaticamente afetada pela mudança.
      builder: (context, child) {
        return MediaQuery(
          // `copyWith` preserva todos os dados originais do MediaQuery do sistema
          // (tamanho de tela, padding, etc.) e sobrescreve APENAS o `textScaler`.
          // `TextScaler.linear(_fatorEscala)` aplica um multiplicador linear e
          // uniforme a todos os textos, ignorando a escala de acessibilidade
          // definida pelo sistema operacional do usuário.
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(_fatorEscala)),
          // O operador `!` (non-null assertion) é seguro aqui pois o `child`
          // dentro do `builder` do MaterialApp nunca é nulo quando rotas estão configuradas.
          child: child!,
        );
      },
    );
  }
}