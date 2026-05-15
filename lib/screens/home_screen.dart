import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_db_store/dio_cache_interceptor_db_store.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'dart:ui';
import '../main.dart';

class VisualizadorImagem extends StatelessWidget {
  final String url;

  const VisualizadorImagem({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.85),
      body: Stack(
        children: [
          // Efeito de desfoque ao fundo
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.transparent),
            ),
          ),

          // Área de Zoom expandida para a tela toda
          SizedBox.expand(
            child: InteractiveViewer(
              clipBehavior: Clip.none,
              minScale: 1.0,
              maxScale: 5.0,
              child: Hero(
                tag: url,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  // Este construtor é chamado quando ocorre um erro de carregamento
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.grey,
                      size: 40,
                    ),
                  ),
                  // Opcional: Mostra algo enquanto a imagem está baixando
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                ),
              ),
            ),
          ),

          // Botão Fechar fixo por cima de tudo
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 20,
            child: SafeArea(
              // Garante que o X não fique debaixo do notch/bateria
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: CircleAvatar(
                  backgroundColor: Colors.black.withOpacity(0.4),
                  radius: 20,
                  child: const Icon(Icons.close, color: Colors.white, size: 25),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final service = SupabaseService();
  // Adicione esta variável para controlar a inscrição
  RealtimeChannel? _realtimeSubscription;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _estaOffline = false;

  String? nomeUsuario;
  bool isGoogle = false;

  late final AnimatedMapController _animatedMapController;
  bool _aguardandoPermissao = false;
  LatLng? _posicaoAtual;
  double _zoomAtual = 13.0; // Valor padrão inicial
  final bool _carregandoLocalizacaoReal = true;
  StreamSubscription<Position>? _positionStream;
  late CacheStore _cacheStore;
  bool _cacheInitialized = false;
  bool _mapReady = false;
  bool _gpsAtivoEPermitido = false; // Nova variável
  final LatLng _fallback = LatLng(-23.5505, -46.6333);
  List<Marker> _markers = [];
  Set<String> _filtrosAtivos = {'Idoso', 'Autista', 'Gestante', 'PcD'};
  List<Map<String, dynamic>> _todosOsLocais = [];
  bool _menuAberto = false;
  int _nivelZoom = 0;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
    WidgetsBinding.instance.addObserver(this);
    _initCache(); // Inicializa o banco de dados do mapa
    carregar();
    _configurarEscutaRealtime();
    _ouvirConexao();
    _animatedMapController = AnimatedMapController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
    Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      setState(() {
        _gpsAtivoEPermitido = (status == ServiceStatus.enabled);
      });

      if (_gpsAtivoEPermitido) {
        _atualizarLocalizacao(); // Tenta pegar a posição se ele ligou agora
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel(); // Para de seguir o usuário ao sair da tela
    _cacheStore.close();
    if (_realtimeSubscription != null) {
      Supabase.instance.client.removeChannel(_realtimeSubscription!);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_aguardandoPermissao) {
        _atualizarLocalizacao(); // Centraliza
        _aguardandoPermissao = false; // Reseta
      }
    }
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
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _ouvirConexao() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      bool temConexaoLayer = !results.contains(ConnectivityResult.none);
      bool temInternetReal = false;

      if (temConexaoLayer) {
        try {
          final result = await InternetAddress.lookup(
            'google.com',
          ).timeout(const Duration(seconds: 3));
          temInternetReal =
              result.isNotEmpty && result[0].rawAddress.isNotEmpty;
        } catch (_) {
          temInternetReal = false;
        }
      }

      if (_estaOffline != !temInternetReal) {
        setState(() {
          _estaOffline = !temInternetReal;
        });

        if (_estaOffline) {
          if (_realtimeSubscription != null) {
            Supabase.instance.client.removeChannel(_realtimeSubscription!);
            _realtimeSubscription = null;
            debugPrint("Realtime pausado: Sem internet.");
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.cloud_off, color: Colors.white),
                  SizedBox(width: 10),
                  Text("Você está offline. Exibindo dados salvos."),
                ],
              ),
              backgroundColor: Color.fromARGB(255, 65, 65, 65),
              duration: Duration(days: 1), // Fica visível até voltar a rede
            ),
          );
        } else {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          _configurarEscutaRealtime();
          _carregarMarcadores();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Conexão restabelecida!"),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          debugPrint("Realtime reativado: Internet voltou.");
        }
      }
    });
  }

  // Função para inicializar o local de salvamento do mapa
  Future<void> _initCache() async {
    final dir = await getTemporaryDirectory();
    _cacheStore = DbCacheStore(
      databasePath: dir.path,
      databaseName: "map_cache_pcd",
    );
    setState(() {
      _cacheInitialized = true;
    });
  }

  // Salva a última localização conhecida
  Future<void> _salvarUltimaLocalizacao(LatLng posicao) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ultima_lat', posicao.latitude);
    await prefs.setDouble('ultima_lng', posicao.longitude);
  }

  // Recupera a localização salva ou retorna o fallback se não houver nada
  Future<LatLng> _recuperarUltimaLocalizacao() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('ultima_lat');
    final lng = prefs.getDouble('ultima_lng');

    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }
    return _fallback; // Retorna São Paulo apenas na primeira vez da vida do app
  }

  void carregar() async {
    await _recuperarFiltrosDoCache();

    // 1. Verificação de Internet
    if (!(await _temInternet())) {
      if (mounted) {
        // Verifica se esta tela é a que o usuário está vendo no momento
        _mostrarDialogo(
          "Sem Conexão",
          "Parece que você está offline. Exibindo dados salvos localmente.",
        );
      }
    }

    // 2. Carregar dados do usuário (Supabase)
    final nome = await service.getNomeUsuario();
    final user = Supabase.instance.client.auth.currentUser;

    if (mounted) {
      setState(() {
        nomeUsuario = nome;
        isGoogle =
            user?.identities?.any((i) => i.provider == 'google') ?? false;
      });
    }

    // --- LÓGICA DE LOCALIZAÇÃO OTIMIZADA ---

    // 3. Tenta recuperar do cache local (SharedPreferences)
    final localizacaoSalva = await _recuperarUltimaLocalizacao();

    // Definimos a posição inicial (ou cache ou fallback de SP),
    // mas ainda não mostramos o mapa (_mapReady continua false)
    _posicaoAtual = localizacaoSalva;

    // 4. PASSO DE ATUALIZAÇÃO: Tentar obter a posição real via GPS
    try {
      await _verificarPermissoes();

      // Tenta pegar a posição atual com um timeout de 4 segundos
      Position atual = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );

      final novaPosicao = LatLng(atual.latitude, atual.longitude);
      _posicaoAtual = novaPosicao;

      // Salva essa nova posição no cache para a próxima vez
      await _salvarUltimaLocalizacao(novaPosicao);

      // Inicia a escuta para seguir o usuário se ele se mover
      _iniciarEscutaLocalizacao();

      setState(() {
        _gpsAtivoEPermitido = true;
      });
    } catch (e) {
      // Se o GPS falhar (permissão negada ou timeout), mantemos o _posicaoAtual
      // como o cache (ou SP se o cache retornou SP).
      debugPrint("GPS não disponível, usando fallback/cache: $e");

      setState(() {
        _gpsAtivoEPermitido = false;
      });

      // Se o usuário negou a permissão permanentemente, mostramos o diálogo
      _tratarErroLocalizacao(e.toString());
    } finally {
      // 5. LIBERAÇÃO FINAL: Agora que temos o melhor local possível,
      // renderizamos o mapa de uma vez.
      if (mounted) {
        setState(() {
          // Se a posição for igual ao fallback (SP), zoom 13. Caso contrário, zoom 17.
          if (_posicaoAtual != null &&
              _posicaoAtual!.latitude == _fallback.latitude &&
              _posicaoAtual!.longitude == _fallback.longitude) {
            _zoomAtual = 13.0;
          } else {
            _zoomAtual = 17.0;
          }
          _mapReady = true;
        });
      }
    }

    // 6. Carregar os marcadores (Vagas)
    try {
      await _carregarMarcadores();
    } catch (e) {
      debugPrint("Erro ao carregar marcadores: $e");
    }
  }

  Future<void> _atualizarLocalizacao() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          !serviceEnabled) {
        return; // 🚫 evita spam
      }

      Position atual = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;

      final novaPosicao = LatLng(atual.latitude, atual.longitude);

      setState(() {
        _posicaoAtual = novaPosicao;
        _gpsAtivoEPermitido = true;
      });

      _animatedMapController.animateTo(dest: novaPosicao, zoom: 17);
    } catch (e) {
      debugPrint("Erro ao atualizar localização: $e");
    }
  }

  void _iniciarEscutaLocalizacao() {
    // Define as configurações do Stream
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15, // <--- Aqui definimos a atualização a cada 15m
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            final novaPosicao = LatLng(position.latitude, position.longitude);
            _salvarUltimaLocalizacao(novaPosicao);
            setState(() {
              _posicaoAtual = novaPosicao;
              _gpsAtivoEPermitido = true; // Se recebeu posição, está ativo
            });
          },
          onError: (error) {
            // Se o usuário desativar o GPS ou permissão, entra aqui
            setState(() {
              _gpsAtivoEPermitido = false;
            });
          },
        );
  }

  void _centralizarNoUsuario() {
    if (_posicaoAtual != null && _gpsAtivoEPermitido) {
      _animatedMapController.animateTo(dest: _posicaoAtual!, zoom: 17);
    } else {
      // Caso o GPS esteja desligado, tenta reativar/solicitar
      _atualizarLocalizacao();
    }
  }

  Future<void> _verificarPermissoes() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _gpsAtivoEPermitido = false);
      throw Exception('GPS_DESATIVADO');
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      setState(() => _gpsAtivoEPermitido = false);
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      setState(() => _gpsAtivoEPermitido = false);
      throw Exception('PERMISSAO_NEGADA');
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _gpsAtivoEPermitido = false);
      throw Exception('PERMISSAO_PERMANENTE');
    }

    setState(() => _gpsAtivoEPermitido = true);
  }

  // Função para tratar os erros e mostrar os diálogos
  void _tratarErroLocalizacao(String erro) {
    if (erro.contains('GPS_DESATIVADO')) {
      _mostrarDialogoGpsDesativado();
    } else if (erro.contains('PERMISSAO_PERMANENTE') ||
        erro.contains('PERMISSAO_NEGADA')) {
      // Só mostramos o diálogo de "Abrir Configurações" se estiver bloqueado no sistema
      _mostrarDialogoExplicacao();
    } else {
      // Caso seja apenas um erro genérico ou o usuário negou uma vez,
      // talvez apenas um log ou uma mensagem discreta (SnackBar) seja melhor.
      debugPrint("Erro de localização: $erro");
    }
  }

  void _mostrarDialogoExplicacao() {
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Localização necessária'),
          content: const Text(
            'Precisamos da sua localização para mostrar vagas especiais perto de você.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                _aguardandoPermissao = true;
                Navigator.pop(context);
                await Geolocator.openAppSettings();
              },
              child: const Text('Abrir configurações'),
            ),
          ],
        ),
      );
    }
  }

  void _mostrarDialogoGpsDesativado() {
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(children: [Text('GPS Desativado')]),
          content: const Text(
            'O serviço de localização do seu aparelho parece estar desligado. Por favor, ative-o para continuar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                // Abre a tela de configurações de localização do Android/iOS
                await Geolocator.openLocationSettings();
              },
              child: const Text('Abrir Configurações'),
            ),
          ],
        ),
      );
    }
  }

  void _mostrarDialogo(String titulo, String mensagem) {
    if (ModalRoute.of(context)?.isCurrent ?? false) {
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
  }

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<void> _excluirConta() async {
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
      final user = Supabase.instance.client.auth.currentUser;

      // 🔥 1. Revoga acesso do Google no app
      try {
        await _googleSignIn.disconnect(); // remove permissão do Google
      } catch (_) {
        // pode falhar se não estiver logado via Google, então ignoramos
      }

      // 🔥 2. Deleta usuário no backend (Supabase Edge Function)
      await Supabase.instance.client.functions.invoke(
        'delete-user',
        body: {'userId': user?.id},
      );

      // 🔥 3. Faz logout do Supabase
      await Supabase.instance.client.auth.signOut();

      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      _mostrarDialogo("Erro", "Não foi possível excluir a conta: $e");
    }
  }

  Widget _buildUserLocationMarker() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blueAccent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  Future<void> _configurarEscutaRealtime() async {
    if (!(await _temInternet())) {
      debugPrint("Sem internet: pulando configuração de Realtime.");
      return;
    }
    if (_realtimeSubscription != null) {
      await Supabase.instance.client.removeChannel(_realtimeSubscription!);
    }
    _realtimeSubscription = Supabase.instance.client
        .channel('alteracoes_mapa')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vagas',
          callback: (payload) async {
            debugPrint('Mudança detectada via Realtime: ${payload.eventType}');
            await _carregarMarcadores();
          },
        );
    _realtimeSubscription!.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint('Conectado ao Realtime com sucesso!');
      }
      if (status == RealtimeSubscribeStatus.channelError) {
        debugPrint('Erro no canal Realtime: $error');
        // Opcional: tentar novamente após alguns segundos
      }
    });
  }

  Future<File> _getMarkersCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/markers_cache.json');
  }

  Future<List<Map<String, dynamic>>> _buscarMarcadores() async {
    try {
      // Tenta buscar do Supabase
      final response = await Supabase.instance.client
          .from('locais_com_vagas')
          .select()
          .timeout(const Duration(seconds: 5));

      final lista = List<Map<String, dynamic>>.from(response);

      // Salva o resultado no cache local para uso offline futuro
      final file = await _getMarkersCacheFile();
      await file.writeAsString(jsonEncode(lista));

      return lista;
    } catch (e) {
      debugPrint("Erro ao buscar do Supabase, tentando cache local: $e");

      // Se falhar (offline), tenta ler do arquivo local
      final file = await _getMarkersCacheFile();
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final List<dynamic> dadosLocal = jsonDecode(jsonString);
        return List<Map<String, dynamic>>.from(dadosLocal);
      }

      // Se não houver cache nem internet, retorna vazio
      return [];
    }
  }

  List<Marker> gerarMarcadores(List<Map<String, dynamic>> locais) {
    final List<Marker> markers = [];

    for (final local in locais) {
      final lat = (local['latitude'] as num).toDouble();
      final lng = (local['longitude'] as num).toDouble();
      final vagas = local['vagas'] as List<dynamic>;
      final tiposUnicos = vagas.map((v) => v['tipo_vaga']).toSet();

      for (final tipo in tiposUnicos) {
        markers.add(
          Marker(
            key: ValueKey<String>("$lat|$lng|$tipo"),
            point: LatLng(lat, lng),
            width: 50,
            height: 50,
            rotate: true,
            alignment: const Alignment(0.0, -1.0),
            child: GestureDetector(
              onTap: () =>
                  _mostrarDetalhesLocal(local, tipo), // <--- CHAMA A ABA AQUI
              child: _iconePorTipo(tipo),
            ),
          ),
        );
      }
    }
    return markers;
  }

  Future<void> _carregarMarcadores() async {
    final locais = await _buscarMarcadores();
    _todosOsLocais = locais; // Salva a lista bruta
    _aplicarFiltro();
  }

  void _aplicarFiltro() {
    if (!mounted) return;
    // Filtra a lista bruta baseada nos tipos selecionados no Set
    final locaisFiltrados = _todosOsLocais
        .map((local) {
          final novasVagas = (local['vagas'] as List)
              .where((v) => _filtrosAtivos.contains(v['tipo_vaga']))
              .toList();

          return {...local, 'vagas': novasVagas};
        })
        .where((local) => (local['vagas'] as List).isNotEmpty)
        .toList();

    setState(() {
      _markers = gerarMarcadores(locaisFiltrados);
    });
  }

  // Salva os filtros ativos no disco
  Future<void> _salvarFiltrosNoCache() async {
    final prefs = await SharedPreferences.getInstance();
    // Convertemos o Set em List para o SharedPreferences aceitar
    await prefs.setStringList('filtros_usuarios', _filtrosAtivos.toList());
  }

  // Recupera os filtros salvos
  Future<void> _recuperarFiltrosDoCache() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? filtrosSalvos = prefs.getStringList('filtros_usuarios');

    if (filtrosSalvos != null && filtrosSalvos.isNotEmpty) {
      setState(() {
        _filtrosAtivos = filtrosSalvos.toSet();
      });
    }
  }

  Widget _buildFiltroCustom() {
    final tipos = ['Idoso', 'Autista', 'Gestante', 'PcD'];
    const double larguraBase = 120.0;

    return TapRegion(
      // Esta função dispara quando você clica em qualquer lugar FORA deste widget
      onTapOutside: (event) {
        if (_menuAberto) {
          setState(() {
            _menuAberto = false;
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 16, left: 16),
        constraints: const BoxConstraints(
          minWidth: larguraBase,
          maxWidth: 160, // Limite máximo para não cobrir a tela toda
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => setState(() => _menuAberto = !_menuAberto),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: _menuAberto
                      ? const BorderRadius.vertical(top: Radius.circular(15))
                      : BorderRadius.circular(15),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 4),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(
                      Icons.filter_list,
                      size: 18,
                      color: Colors.blueAccent,
                    ),
                    const Flexible(
                      // <--- Adicione isso para o texto não empurrar os ícones
                      child: Text(
                        "Filtrar",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(
                      _menuAberto ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
            ),

            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: tipos.map((tipo) {
                    final ativo = _filtrosAtivos.contains(tipo);
                    return InkWell(
                      onTap: () {
                        setState(() {
                          if (ativo) {
                            _filtrosAtivos.remove(tipo);
                          } else {
                            _filtrosAtivos.add(tipo);
                          }
                        });
                        _salvarFiltrosNoCache();
                        _aplicarFiltro();
                      },

                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade100),
                          ),
                          color: ativo
                              ? Colors.blueAccent.withOpacity(0.05)
                              : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              ativo ? Icons.check : Icons.close,
                              size: 18,
                              color: ativo
                                  ? Colors.blueAccent
                                  : Colors.grey.shade300,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              tipo,
                              style: TextStyle(
                                fontSize: 13,
                                color: ativo
                                    ? Colors.blueAccent
                                    : Colors.black87,
                                fontWeight: ativo
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              crossFadeState: _menuAberto
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconePorTipo(String tipo) {
    switch (tipo) {
      case 'Idoso':
        return Image.asset(
          'assets/images/vaga_icons/idoso.webp',
          width: 50,
          height: 50,
        );

      case 'Autista':
        return Image.asset(
          'assets/images/vaga_icons/autista.webp',
          width: 50,
          height: 50,
        );

      case 'Gestante':
        return Image.asset(
          'assets/images/vaga_icons/gestante.webp',
          width: 50,
          height: 50,
        );

      case 'PcD':
        return Image.asset(
          'assets/images/vaga_icons/pcd.webp',
          width: 50,
          height: 50,
        );
      default:
        return Image.asset(
          'assets/images/vaga_icons/pcd_autista_idoso_gestante.webp',
          width: 50,
          height: 50,
        );
    }
  }

  String _obterImagemDoCluster(List<Marker> clusterMarkers) {
    // 1. Extrai os tipos únicos
    final tiposSet = clusterMarkers.map((m) {
      final keyString = (m.key as ValueKey).value.toString();
      return keyString.split('|').last;
    }).toSet();

    // 2. Transforma em lista e ordena alfabeticamente
    // Isso garante que 'PcD' e 'Idoso' sempre resultem em 'idoso_pcd'
    final listaOrdenada = tiposSet.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // 3. Caso especial: Se vazio ou se tiver todos (4 tipos), retorna o ícone completo
    if (listaOrdenada.isEmpty || listaOrdenada.length == 4) {
      return 'assets/images/vaga_icons/autista_gestante_idoso_pcd.webp';
    }

    // 4. Gera o nome do arquivo juntando os itens da lista ordenada
    // Ex: ['Autista', 'Idoso'] -> 'autista_idoso'
    final nomeArquivo = listaOrdenada.map((s) => s.toLowerCase()).join('_');

    return 'assets/images/vaga_icons/$nomeArquivo.webp';
  }

  void _mostrarDetalhesLocal(Map<String, dynamic> local, String tipoClicado) {
    final dadosVaga = (local['vagas'] as List).firstWhere(
      (v) => v['tipo_vaga'] == tipoClicado,
      orElse: () => null,
    );

    if (dadosVaga == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  // Barra visual de arraste
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cabeçalho com Ícone e Tipo
                        Row(
                          children: [
                            _iconePorTipo(tipoClicado),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Vaga para $tipoClicado",
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Endereço
                        const Text(
                          "Endereço",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text("${local['logradouro']}, ${local['numero']}"),
                        Text(
                          "${local['bairro']} - ${local['cidade']}/${local['estado']}",
                        ),
                        Text(
                          "Referência: ${local['referencia'] != null && local['referencia'].isNotEmpty ? local['referencia'] : 'Não registrada'}",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),

                        const Divider(height: 32),

                        // Info de Quantidade
                        const Text(
                          "Vagas Disponíveis",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text("Quantidade no local: ${dadosVaga['quantidade']}"),

                        const Divider(height: 32),

                        // 📸 SEÇÃO DE IMAGEM (Simplificada)
                        if (dadosVaga['foto_url'] != null &&
                            dadosVaga['foto_url'].toString().isNotEmpty) ...[
                          const Text(
                            "Foto da Vaga",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  opaque: false,
                                  barrierDismissible: true,
                                  pageBuilder: (context, _, _) =>
                                      VisualizadorImagem(
                                        url: dadosVaga['foto_url'],
                                      ),
                                ),
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              height: 300,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE7E7E7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    Hero(
                                      tag: dadosVaga['foto_url'],
                                      child: Image.network(
                                        dadosVaga['foto_url'],
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.contain,
                                        loadingBuilder:
                                            (context, child, loadingProgress) {
                                              if (loadingProgress == null)
                                                return child;
                                              return const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              );
                                            },
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const Center(
                                                  child: Icon(
                                                    Icons.broken_image,
                                                    color: Colors.grey,
                                                    size: 40,
                                                  ),
                                                ),
                                      ),
                                    ),
                                    // Indicador visual de que a imagem é expansível
                                    Positioned(
                                      right: 8,
                                      bottom: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black45,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.fullscreen,
                                          color: Colors.white,
                                          size: 30,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          // Opcional: Feedback visual se não houver foto
                          const Text(
                            "Nenhuma foto cadastrada para esta vaga.",
                            style: TextStyle(
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Home")),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              nomeUsuario != null
                  ? "Seja bem-vindo, $nomeUsuario!"
                  : "Seja bem-vindo, visitante!",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (_mapReady && _posicaoAtual != null)
                  FlutterMap(
                    mapController: _animatedMapController.mapController,
                    options: MapOptions(
                      initialCenter: _posicaoAtual ?? _fallback,
                      initialZoom: _zoomAtual,
                      maxZoom: 19.0,
                      minZoom: 12.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'br.com.incluzone.backend',
                        tileDisplay: const TileDisplay.fadeIn(
                          duration: Duration(milliseconds: 500),
                        ),
                        tileProvider: CachedTileProvider(store: _cacheStore),
                      ),

                      // 🔵 CLUSTER DOS MARKERS DO SUPABASE
                      MarkerClusterLayerWidget(
                        options: MarkerClusterLayerOptions(
                          maxClusterRadius: 100,
                          size: const Size(70, 70),
                          markers: _markers,
                          rotate: true,
                          alignment: const Alignment(0.0, -1.0),
                          spiderfyCluster: true,
                          zoomToBoundsOnClick: false,
                          maxZoom: 19,
                          spiderfyCircleRadius: 70,

                          builder: (context, clusterMarkers) {
                            final caminhoImagem = _obterImagemDoCluster(
                              clusterMarkers,
                            );

                            return Transform.translate(
                              offset: const Offset(0, 10),
                              child: Image.asset(
                                caminhoImagem,
                                width: 80,
                                height: 80,
                              ),
                            );
                          },

                          onClusterTap: (cluster) async {
                            final camera =
                                _animatedMapController.mapController.camera;

                            // 1. Verificar se todos os marcadores estão na mesma coordenada
                            final primeiraCoordenada =
                                cluster.markers.first.point;
                            final todosNaMesmaCoordenada = cluster.markers
                                .every(
                                  (m) =>
                                      m.point.latitude ==
                                          primeiraCoordenada.latitude &&
                                      m.point.longitude ==
                                          primeiraCoordenada.longitude,
                                );

                            if (todosNaMesmaCoordenada) {
                              // Para pontos sobrepostos, mantemos o zoom alto para o spiderfy
                              await _animatedMapController.animateTo(
                                dest: primeiraCoordenada,
                                zoom: 18.0,
                              );
                            } else {
                              // 2. Calculamos o enquadramento ideal
                              final cameraFit = CameraFit.bounds(
                                bounds: cluster.bounds,
                                padding: const EdgeInsets.all(
                                  50,
                                ), // Margem interna em pixels
                              );

                              final fitOutput = cameraFit.fit(camera);

                              // 3. A MÁGICA: Subtraímos 0.5 do zoom calculado para dar o "respiro" extra
                              double zoomComMargem = fitOutput.zoom - 0.5;

                              // 4. Aplicamos a trava de segurança (ex: não passar de 17)
                              if (zoomComMargem > 17.0) {
                                zoomComMargem = 17.0;
                              }

                              await _animatedMapController.animateTo(
                                dest: fitOutput.center,
                                zoom: zoomComMargem,
                              );
                            }
                          },
                        ),
                      ),

                      // 🟢 USUÁRIO FORA DO CLUSTER (SEPARADO)
                      MarkerLayer(
                        markers: [
                          if (_mapReady &&
                              _posicaoAtual != null &&
                              _gpsAtivoEPermitido)
                            Marker(
                              point: _posicaoAtual!,
                              width: 22,
                              height: 22,
                              child: _buildUserLocationMarker(),
                            ),
                        ],
                      ),
                    ],
                  ),

                Positioned(top: 0, left: 0, child: _buildFiltroCustom()),

                if (_mapReady)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: FloatingActionButton(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blueAccent,
                      elevation: 4,
                      onPressed: _centralizarNoUsuario,
                      child: const Icon(Icons.my_location),
                    ),
                  ),

                if (!_mapReady)
                  Container(
                    color: Colors.white,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            "Localizando...",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),

      drawer: Drawer(
        child: Column(
          children: [
            // O Expanded faz o ListView ocupar todo o espaço disponível no topo e meio
            Expanded(
              child: SafeArea(
                child: ListView(
                  // Remova o padding padrão do ListView para não dar conflito com o topo
                  padding: EdgeInsets.zero,
                  children: [
                    ListTile(
                      title: const Text("Sobre o IncluZone"),
                      leading: const Icon(Icons.info_outline),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/sobre');
                      },
                    ),
                    if (nomeUsuario == null) ...[
                      ListTile(
                        title: const Text("Login"),
                        leading: const Icon(Icons.login),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/login');
                        },
                      ),
                      ListTile(
                        title: const Text("Cadastrar"),
                        leading: const Icon(Icons.person_add_outlined),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/cadastro');
                        },
                      ),
                    ],
                    ListTile(
                      title: const Text("Pré-registrar Vagas"),
                      leading: const Icon(Icons.location_on_outlined),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/pre_registro_vagas');
                      },
                    ),
                    if (nomeUsuario != null) ...[
                      if (!isGoogle) ...[
                        ListTile(
                          title: const Text("Editar conta"),
                          leading: const Icon(Icons.edit_outlined),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/editar');
                          },
                        ),
                      ],
                      ListTile(
                        title: const Text("Histórico"),
                        leading: const Icon(Icons.history),
                        onTap: () async {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/historico');
                        },
                      ),
                      ListTile(
                        title: const Text("Sair"),
                        leading: const Icon(Icons.logout),
                        onTap: () async {
                          Navigator.pop(context);
                          await service.client.auth.signOut();
                          setState(() => nomeUsuario = null);
                          Navigator.pushReplacementNamed(context, '/');
                        },
                      ),
                      if (isGoogle) ...[
                        ListTile(
                          title: const Text(
                            "Excluir conta",
                            style: TextStyle(color: Colors.red),
                          ),
                          leading: const Icon(Icons.delete, color: Colors.red),
                          onTap: _excluirConta,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),

            // Rodapé centralizado
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Image.asset('assets/images/titulo.webp', width: 150),
              ),
            ),
          ],
        ),
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
