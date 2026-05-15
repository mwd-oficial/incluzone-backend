import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Mantenha seus imports de telas aqui...
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://xyrzopysmpaziohhnyer.supabase.co',
    anonKey: 'sb_publishable_3cHH3MygneqFnUnJJtQ32Q_gjoMqtE-',
  );

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(MyApp(key: myAppKey));
}

// 1. Criamos uma chave global para acessar o estado do MyApp de qualquer lugar
final GlobalKey<MyAppState> myAppKey = GlobalKey<MyAppState>();

class MyApp extends StatefulWidget {
  // 2. IMPORTANTE: Passe a chave para o super construtor aqui!
  MyApp({super.key});

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  double _fatorEscala = 1.0;

  @override
  void initState() {
    super.initState();
    _carregarEscala();
  }

  // 2. Método para carregar a escala inicial
  Future<void> _carregarEscala() async {
    final prefs = await SharedPreferences.getInstance();
    final nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    setState(() {
      _fatorEscala = 1.0 + (nivelZoom * 0.2);
    });
  }

  // 3. Método público que as outras telas vão chamar
  void atualizarEscala(int nivelZoom) {
    setState(() {
      _fatorEscala = 1.0 + (nivelZoom * 0.2);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IncluZone DB Test',
      initialRoute: '/splash',
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
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(_fatorEscala)),
          child: child!,
        );
      },
    );
  }
}
