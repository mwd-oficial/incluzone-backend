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

/// Tela de visualização de imagem em tela cheia, com suporte a zoom (pinch-to-zoom)
/// e fundo desfocado (blur), usada para exibir a foto de uma vaga em detalhes.
class VisualizadorImagem extends StatelessWidget {
  /// URL da imagem de rede a ser exibida.
  final String url;

  const VisualizadorImagem({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Fundo semi-transparente para dar a sensação de "modal" sobre a tela anterior.
      backgroundColor: Colors.black.withOpacity(0.85),
      body: Stack(
        children: [
          // Efeito de desfoque (blur) aplicado a toda a área de fundo.
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.transparent),
            ),
          ),

          // Área de zoom que ocupa toda a tela, permitindo ao usuário
          // dar pinch-to-zoom e arrastar a imagem.
          SizedBox.expand(
            child: InteractiveViewer(
              clipBehavior: Clip.none,
              minScale: 1.0,
              maxScale: 5.0,
              child: Hero(
                // Tag única baseada na URL, usada para a animação de transição
                // (Hero animation) entre a miniatura e a imagem em tela cheia.
                tag: url,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  // Builder chamado quando ocorre erro ao carregar a imagem
                  // (ex: URL inválida ou sem conexão).
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.grey,
                      size: 40,
                    ),
                  ),
                  // Builder exibido enquanto a imagem ainda está sendo baixada.
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                ),
              ),
            ),
          ),

          // Botão de fechar (X), posicionado sobre todo o restante da UI.
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 20,
            child: SafeArea(
              // SafeArea garante que o botão não fique sob a barra de status/notch.
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

/// Tela principal (Home) do app, responsável por exibir o mapa interativo
/// com as vagas especiais (Idoso, Autista, Gestante, PcD), gerenciar a
/// localização do usuário, o cache offline de tiles/marcadores e a
/// sincronização em tempo real (Realtime) com o Supabase.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  /// Instância do serviço que encapsula as chamadas ao Supabase.
  final service = SupabaseService();
  // Canal de Realtime do Supabase usado para escutar mudanças na tabela 'vagas'.
  RealtimeChannel? _realtimeSubscription;

  // Assinatura do stream de conectividade, usada para detectar quando o
  // dispositivo fica online/offline.
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  // Indica se o app está atualmente sem conexão com a internet.
  bool _estaOffline = false;

  /// Nome do usuário autenticado, ou null se for visitante.
  String? nomeUsuario;
  /// Indica se o usuário fez login via conta Google (afeta opções do menu).
  bool isGoogle = false;

  // Controlador de mapa com suporte a animações (ex: animar até a localização do usuário).
  late final AnimatedMapController _animatedMapController;
  // Flag que indica que o app está esperando o usuário voltar das configurações
  // do sistema após conceder permissão de localização.
  bool _aguardandoPermissao = false;
  // Última posição conhecida do usuário (do GPS, cache ou fallback).
  LatLng? _posicaoAtual;
  // Nível de zoom inicial do mapa (varia conforme a posição é fallback ou real).
  double _zoomAtual = 13.0; // Valor padrão inicial
  // Variável de controle (não utilizada para alterar o fluxo, mantida como está).
  final bool _carregandoLocalizacaoReal = true;
  // Stream de atualizações contínuas de posição do GPS (segue o usuário).
  StreamSubscription<Position>? _positionStream;
  // Armazenamento em disco usado para cachear os tiles do mapa (modo offline).
  late CacheStore _cacheStore;
  // Indica se o cache de tiles já foi inicializado.
  bool _cacheInitialized = false;
  // Indica se o mapa está pronto para ser renderizado (já temos uma posição definida).
  bool _mapReady = false;
  // Indica se o GPS está ativo e com permissão concedida.
  bool _gpsAtivoEPermitido = false; // Nova variável
  // Posição padrão (São Paulo) usada quando não há GPS nem cache de localização.
  final LatLng _fallback = LatLng(-23.5505, -46.6333);
  // Lista de marcadores atualmente exibidos no mapa (já filtrados).
  List<Marker> _markers = [];
  // Conjunto de tipos de vaga que estão atualmente habilitados no filtro.
  Set<String> _filtrosAtivos = {'Idoso', 'Autista', 'Gestante', 'PcD'};
  // Lista bruta (sem filtro) de todos os locais retornados pelo backend/cache.
  List<Map<String, dynamic>> _todosOsLocais = [];
  // Controla se o menu de filtros está expandido ou recolhido.
  bool _menuAberto = false;
  // Nível de zoom da escala de fonte/elementos do app (0, 1 ou 2), persistido em disco.
  int _nivelZoom = 0;

  @override
  void initState() {
    super.initState();
    // Carrega o nível de zoom de acessibilidade salvo anteriormente.
    _carregarConfiguracoesIniciais();
    // Registra este State como observador do ciclo de vida do app
    // (necessário para detectar quando o app volta do background).
    WidgetsBinding.instance.addObserver(this);
    _initCache(); // Inicializa o banco de dados do mapa (cache de tiles)
    // Dispara o fluxo principal de carregamento de dados/localização/marcadores.
    carregar();
    // Configura a escuta de mudanças em tempo real na tabela de vagas.
    _configurarEscutaRealtime();
    // Começa a monitorar mudanças no estado da conexão com a internet.
    _ouvirConexao();
    // Inicializa o controlador de mapa com animações suaves.
    _animatedMapController = AnimatedMapController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
    // Escuta mudanças no status do serviço de localização do dispositivo
    // (ex: usuário ligou/desligou o GPS manualmente).
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
    // Remove o observador de ciclo de vida para evitar vazamentos de memória.
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel(); // Para de seguir o usuário ao sair da tela
    // Fecha a conexão com o banco de cache de tiles do mapa.
    _cacheStore.close();
    // Remove a inscrição do canal Realtime, se existir, para evitar vazamento de conexão.
    if (_realtimeSubscription != null) {
      Supabase.instance.client.removeChannel(_realtimeSubscription!);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Quando o app volta a ficar em primeiro plano (resumed)...
    if (state == AppLifecycleState.resumed) {
      // ...e estávamos esperando o usuário conceder permissão de localização
      // (ele foi para as configurações do sistema)...
      if (_aguardandoPermissao) {
        _atualizarLocalizacao(); // Centraliza
        _aguardandoPermissao = false; // Reseta
      }
    }
  }

  /// Aumenta ou diminui o nível de zoom de acessibilidade (escala de texto/UI),
  /// limitado entre 0 e 2, persiste o valor em disco e notifica o widget
  /// raiz do app ([myAppKey]) para aplicar a nova escala globalmente.
  Future<void> _atualizarZoom(bool aumentar) async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      // Só incrementa se ainda não atingiu o limite máximo (2).
      if (aumentar && _nivelZoom < 2) {
        _nivelZoom++;
      // Só decrementa se ainda não atingiu o limite mínimo (0).
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

  /// Carrega o nível de zoom de acessibilidade salvo anteriormente em disco
  /// (ou usa 0 como padrão se não houver valor salvo).
  Future<void> _carregarConfiguracoesIniciais() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    });
  }

  /// Verifica se o dispositivo possui conexão de rede E acesso real à internet.
  ///
  /// Primeiro checa o tipo de conectividade (wifi/dados/nenhum); se houver
  /// alguma conexão, faz uma checagem adicional de DNS para confirmar que
  /// existe acesso real à internet (e não apenas conexão local sem internet).
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

  /// Registra um listener para o stream de mudanças de conectividade.
  ///
  /// Sempre que a conectividade muda, valida se há internet de fato (via DNS).
  /// Se o app passar a ficar offline, pausa o Realtime e exibe um aviso fixo
  /// (SnackBar com duração de 1 dia) informando que os dados exibidos são locais.
  /// Se voltar a ficar online, reconfigura o Realtime, recarrega os marcadores
  /// e exibe uma confirmação temporária de reconexão.
  void _ouvirConexao() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      // Verifica se existe alguma interface de rede ativa (wifi/dados/etc).
      bool temConexaoLayer = !results.contains(ConnectivityResult.none);
      bool temInternetReal = false;

      // Só faz a checagem de DNS se já existir alguma camada de conexão,
      // para evitar chamadas desnecessárias quando claramente está offline.
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

      // Só atualiza a UI/estado se o status de offline realmente mudou,
      // evitando rebuilds e snackbars desnecessários.
      if (_estaOffline != !temInternetReal) {
        setState(() {
          _estaOffline = !temInternetReal;
        });

        if (_estaOffline) {
          // Ao ficar offline, encerra o canal Realtime para não tentar
          // reconectar inutilmente enquanto não há rede.
          if (_realtimeSubscription != null) {
            Supabase.instance.client.removeChannel(_realtimeSubscription!);
            _realtimeSubscription = null;
            debugPrint("Realtime pausado: Sem internet.");
          }

          // Exibe um aviso persistente (1 dia de duração) informando
          // que o app está exibindo dados salvos localmente.
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
          // Ao voltar a ficar online: remove o aviso de offline,
          // reativa o Realtime, recarrega os marcadores do servidor
          // e mostra uma confirmação rápida de reconexão.
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

  /// Inicializa o armazenamento (cache) de tiles do mapa em um banco
  /// de dados local, permitindo a navegação offline pelo mapa.
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

  /// Persiste a última posição conhecida do usuário em [SharedPreferences],
  /// para que o app possa abrir o mapa centralizado nessa posição na
  /// próxima inicialização, mesmo sem GPS disponível.
  Future<void> _salvarUltimaLocalizacao(LatLng posicao) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ultima_lat', posicao.latitude);
    await prefs.setDouble('ultima_lng', posicao.longitude);
  }

  /// Recupera a última posição salva em [SharedPreferences].
  ///
  /// Retorna a posição salva (latitude/longitude) caso exista, ou a posição
  /// de fallback ([_fallback], São Paulo) caso seja a primeira vez que o
  /// app é executado neste dispositivo.
  Future<LatLng> _recuperarUltimaLocalizacao() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('ultima_lat');
    final lng = prefs.getDouble('ultima_lng');

    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }
    return _fallback; // Retorna São Paulo apenas na primeira vez da vida do app
  }

  /// Fluxo principal de inicialização da tela:
  /// 1. Recupera os filtros de vagas salvos pelo usuário.
  /// 2. Verifica se há internet e avisa o usuário caso esteja offline.
  /// 3. Carrega os dados do usuário autenticado (nome, se é login Google).
  /// 4. Recupera a última localização salva (cache) como posição inicial.
  /// 5. Tenta obter a localização real via GPS (com timeout de 4s); se
  ///    conseguir, atualiza a posição, salva no cache e começa a seguir
  ///    o usuário; se falhar, mantém a posição do cache/fallback e trata
  ///    o erro de permissão/GPS.
  /// 6. Libera a renderização do mapa ([_mapReady] = true), definindo o
  ///    zoom inicial conforme a posição seja real ou fallback.
  /// 7. Carrega os marcadores (vagas) do backend/cache.
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
        // Verifica entre os provedores de identidade do usuário se algum é o Google.
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

  /// Atualiza a posição do usuário sob demanda (ex: ao reativar o GPS),
  /// movendo a câmera do mapa até a nova posição com zoom 17.
  ///
  /// Não exibe diálogos de erro (evita spam de pop-ups): se a permissão
  /// estiver negada ou o serviço de localização desligado, simplesmente
  /// retorna sem fazer nada.
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

  /// Inicia um stream contínuo de posições do GPS, atualizando a posição
  /// do usuário no mapa sempre que ele se deslocar pelo menos 15 metros
  /// (definido por [LocationSettings.distanceFilter]).
  ///
  /// Cada nova posição também é persistida em cache. Caso ocorra erro
  /// no stream (ex: GPS desligado durante o uso), marca o GPS como inativo.
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

  /// Move a câmera do mapa para a posição atual do usuário (zoom 17),
  /// caso o GPS esteja ativo e com permissão. Caso contrário, tenta
  /// reativar/solicitar a localização novamente.
  void _centralizarNoUsuario() {
    if (_posicaoAtual != null && _gpsAtivoEPermitido) {
      _animatedMapController.animateTo(dest: _posicaoAtual!, zoom: 17);
    } else {
      // Caso o GPS esteja desligado, tenta reativar/solicitar
      _atualizarLocalizacao();
    }
  }

  /// Verifica e, se necessário, solicita as permissões de localização
  /// e o status do serviço de GPS do dispositivo.
  ///
  /// Lança exceções específicas conforme o problema encontrado, para que
  /// [_tratarErroLocalizacao] possa exibir o diálogo apropriado:
  /// - `GPS_DESATIVADO`: o serviço de localização do aparelho está desligado.
  /// - `PERMISSAO_NEGADA`: o usuário negou a permissão (pode perguntar de novo).
  /// - `PERMISSAO_PERMANENTE`: o usuário negou permanentemente (precisa ir
  ///   nas configurações do sistema).
  ///
  /// Se tudo estiver OK, marca [_gpsAtivoEPermitido] como true.
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

  /// Interpreta a string de erro lançada por [_verificarPermissoes] e
  /// decide qual diálogo (se algum) deve ser exibido ao usuário:
  /// - GPS desativado -> exibe diálogo para abrir as configurações de localização.
  /// - Permissão negada (permanente ou não) -> exibe diálogo explicativo
  ///   pedindo para abrir as configurações do app.
  /// - Outros erros -> apenas registra no log, sem incomodar o usuário.
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

  /// Exibe um diálogo explicando por que o app precisa da localização e
  /// oferece um atalho para abrir as configurações do app no sistema
  /// (necessário quando a permissão foi negada permanentemente).
  ///
  /// Só exibe o diálogo se esta tela ([HomeScreen]) for a rota atual,
  /// evitando empilhar diálogos sobre outras telas.
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
                // Marca que estamos esperando o usuário voltar das
                // configurações para então tentar centralizar o mapa.
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

  /// Exibe um diálogo informando que o serviço de localização (GPS) do
  /// dispositivo está desligado, com atalho para abrir as configurações
  /// de localização do sistema operacional.
  ///
  /// Só exibe o diálogo se esta tela for a rota atual.
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

  /// Exibe um diálogo genérico de informação/erro com [titulo] e [mensagem],
  /// contendo apenas um botão "OK". Só exibe se esta tela for a rota atual.
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

  /// Exibe um diálogo simples de informação/erro relacionado à edição de
  /// uma vaga, com [titulo] e [mensagem], contendo apenas um botão "OK".
  /// Diferente de [_mostrarDialogo], não verifica se a rota é a atual.
  void _mostrarDialogoEditarVaga(String titulo, String mensagem) {
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

  // Instância usada para login/logout/desconexão da conta Google.
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// Fluxo de exclusão de conta do usuário:
  /// 1. Pede confirmação via diálogo (com aviso de ação irreversível).
  /// 2. Revoga o acesso do app à conta Google (se aplicável).
  /// 3. Chama a Edge Function 'delete-user' do Supabase para apagar os
  ///    dados do usuário no backend.
  /// 4. Faz logout da sessão local do Supabase.
  /// 5. Redireciona o usuário para a rota raiz, removendo todo o histórico
  ///    de navegação.
  ///
  /// Em caso de erro em qualquer etapa do backend, exibe um diálogo de erro.
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

  /// Constrói o widget visual que representa a posição do usuário no mapa:
  /// um círculo azul com borda branca e leve sombra.
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

  /// Configura (ou reconfigura) a inscrição no canal Realtime do Supabase
  /// para a tabela `vagas`.
  ///
  /// Se não houver internet, não tenta se inscrever (evita erros de conexão).
  /// Se já existir uma inscrição anterior, ela é removida antes de criar a
  /// nova, para evitar inscrições duplicadas. Sempre que houver qualquer
  /// alteração (insert/update/delete) na tabela `vagas`, os marcadores são
  /// recarregados automaticamente.
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

  /// Retorna o [File] correspondente ao arquivo local usado para cachear
  /// a lista de marcadores (vagas) em formato JSON, dentro do diretório
  /// de documentos do app.
  Future<File> _getMarkersCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/markers_cache.json');
  }

  /// Busca a lista de locais com vagas a partir da view `locais_com_vagas`
  /// no Supabase (com timeout de 5 segundos).
  ///
  /// Em caso de sucesso, salva o resultado em um arquivo JSON local para
  /// uso offline futuro e retorna a lista.
  ///
  /// Em caso de falha (ex: sem internet), tenta ler a lista do cache local.
  /// Se nem o cache existir, retorna uma lista vazia.
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

  /// Converte a lista bruta de [locais] (já filtrada por tipo de vaga) em
  /// uma lista de [Marker]s para o [FlutterMap].
  ///
  /// Para cada local, é criado um marcador separado para CADA tipo de vaga
  /// distinto presente naquele local (ex: se um local tem vagas de Idoso e
  /// PcD, são gerados dois marcadores na mesma coordenada, um para cada tipo).
  /// A chave de cada marcador combina latitude, longitude e tipo de vaga,
  /// permitindo identificar o tipo posteriormente (ex: em [_obterImagemDoCluster]).
  List<Marker> gerarMarcadores(List<Map<String, dynamic>> locais) {
    final List<Marker> markers = [];

    for (final local in locais) {
      final lat = (local['latitude'] as num).toDouble();
      final lng = (local['longitude'] as num).toDouble();
      final vagas = local['vagas'] as List<dynamic>;
      // Obtém os tipos de vaga únicos presentes neste local (evita marcadores duplicados).
      final tiposUnicos = vagas.map((v) => v['tipo_vaga']).toSet();

      for (final tipo in tiposUnicos) {
        markers.add(
          Marker(
            // Chave codifica latitude, longitude e tipo, separados por "|",
            // usada depois para extrair o tipo em _obterImagemDoCluster.
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

  /// Busca a lista atualizada de locais com vagas (via [_buscarMarcadores]),
  /// armazena em [_todosOsLocais] (lista bruta, sem filtro) e em seguida
  /// aplica o filtro de tipos de vaga ativos ([_aplicarFiltro]).
  Future<void> _carregarMarcadores() async {
    final locais = await _buscarMarcadores();
    _todosOsLocais = locais; // Salva a lista bruta
    _aplicarFiltro();
  }

  /// Aplica o filtro de tipos de vaga atualmente ativos ([_filtrosAtivos])
  /// sobre a lista bruta de locais ([_todosOsLocais]).
  ///
  /// Para cada local, mantém apenas as vagas cujo `tipo_vaga` está no
  /// conjunto de filtros ativos. Locais que ficarem sem nenhuma vaga após
  /// o filtro são removidos da lista. Por fim, gera os marcadores
  /// correspondentes e atualiza [_markers] via [setState].
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

  /// Persiste em [SharedPreferences] o conjunto de tipos de vaga atualmente
  /// selecionados pelo usuário no filtro, para que sejam restaurados na
  /// próxima vez que o app for aberto.
  Future<void> _salvarFiltrosNoCache() async {
    final prefs = await SharedPreferences.getInstance();
    // Convertemos o Set em List para o SharedPreferences aceitar
    await prefs.setStringList('filtros_usuarios', _filtrosAtivos.toList());
  }

  /// Recupera de [SharedPreferences] os filtros de tipo de vaga salvos
  /// anteriormente pelo usuário e atualiza [_filtrosAtivos], caso existam.
  /// Se não houver nada salvo, mantém o valor padrão (todos os filtros ativos).
  Future<void> _recuperarFiltrosDoCache() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? filtrosSalvos = prefs.getStringList('filtros_usuarios');

    if (filtrosSalvos != null && filtrosSalvos.isNotEmpty) {
      setState(() {
        _filtrosAtivos = filtrosSalvos.toSet();
      });
    }
  }

  /// Constrói o widget de filtro customizado exibido sobre o mapa.
  ///
  /// É composto por um cabeçalho clicável ("Filtrar") que expande/recolhe
  /// (via [AnimatedCrossFade]) uma lista de checkboxes para cada tipo de
  /// vaga (Idoso, Autista, Gestante, PcD). Ao tocar fora do widget
  /// ([TapRegion.onTapOutside]), o menu é automaticamente fechado.
  /// Cada item da lista, ao ser tocado, alterna seu estado em
  /// [_filtrosAtivos], persiste a alteração e reaplica o filtro nos marcadores.
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

  /// Retorna o widget de ícone (imagem) correspondente ao [tipo] de vaga
  /// informado (Idoso, Autista, Gestante ou PcD).
  ///
  /// Se o tipo não corresponder a nenhum dos casos conhecidos, retorna um
  /// ícone genérico que representa todos os tipos combinados.
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

  /// Determina qual imagem (ícone) deve representar um cluster de marcadores
  /// agrupados, com base nos tipos de vaga presentes nesse cluster.
  ///
  /// 1. Extrai o tipo de vaga de cada marcador a partir de sua [ValueKey]
  ///    (formato "lat|lng|tipo"), montando um conjunto de tipos únicos.
  /// 2. Ordena os tipos alfabeticamente (case-insensitive) para garantir
  ///    que combinações equivalentes (ex: PcD+Idoso e Idoso+PcD) sempre
  ///    gerem o mesmo nome de arquivo.
  /// 3. Caso o cluster esteja vazio ou contenha todos os 4 tipos, retorna
  ///    o ícone "completo" (todos os tipos).
  /// 4. Caso contrário, monta o nome do arquivo concatenando os tipos
  ///    ordenados em minúsculas separados por "_" (ex: "autista_idoso.webp").
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

  /// Exibe um [BottomSheet] arrastável (DraggableScrollableSheet) com os
  /// detalhes de uma vaga específica do [local], correspondente ao tipo
  /// [tipoClicado] (o usuário tocou no marcador desse tipo).
  ///
  /// O conteúdo exibido inclui: cabeçalho com ícone e tipo da vaga, botão
  /// de edição (que verifica conexão e login antes de navegar para a tela
  /// de registro de vagas), lista de contribuintes que cadastraram a vaga,
  /// endereço completo, quantidade de vagas disponíveis e, se houver, a
  /// foto da vaga (com possibilidade de abrir em tela cheia via
  /// [VisualizadorImagem]).
  ///
  /// Se a vaga do tipo [tipoClicado] não for encontrada na lista de vagas
  /// do [local], a função retorna sem exibir nada.
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
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: Colors.blueAccent,
                              ),
                              onPressed: () async {
                                // Bloqueia a edição se não houver conexão com a internet.
                                if (!(await _temInternet())) {
                                  if (mounted) {
                                    _mostrarDialogoEditarVaga(
                                      "Sem Conexão",
                                      "Parece que você está offline. Verifique sua conexão com a internet e tente novamente.",
                                    );
                                  }
                                  return; // Interrompe a execução aqui
                                }

                                // Se o usuário estiver logado, vai direto para
                                // a tela de registro; caso contrário, pede login antes.
                                if (service.estaLogado) {
                                  // Aguarda o usuário terminar o registro na outra tela
                                  await Navigator.pushNamed(
                                    context,
                                    '/registro_vagas',
                                    arguments: local,
                                  );
                                } else {
                                  Navigator.pushNamed(context, '/login');
                                }
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // --- SEÇÃO DE CONTRIBUINTES ---
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Contribuintes deste local",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Builder(
                              builder: (context) {
                                final List<dynamic> contribuintes =
                                    local['contribuintes'] ?? [];

                                // Se não houver nenhum contribuinte registrado,
                                // exibe uma mensagem informativa em vez da lista.
                                if (contribuintes.isEmpty) {
                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      "Nenhuma contribuição registrada ainda.",
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  );
                                }

                                // Gera a lista vertical de usuários usando uma Column
                                return Column(
                                  children: contribuintes.map<Widget>((
                                    contrib,
                                  ) {
                                    final String? avatarUrl = contrib['avatar'];
                                    final String nome =
                                        contrib['nome'] ?? "Usuário Anônimo";

                                    return Container(
                                      margin: const EdgeInsets.only(
                                        bottom: 8,
                                      ), // Espaçamento entre usuários
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor:
                                                Colors.grey.shade300,
                                            // Usa a imagem de rede do avatar, se houver;
                                            // caso contrário, exibe um avatar padrão local.
                                            backgroundImage:
                                                (avatarUrl != null &&
                                                    avatarUrl.isNotEmpty)
                                                ? NetworkImage(avatarUrl)
                                                : null,
                                            child:
                                                (avatarUrl == null ||
                                                    avatarUrl.isEmpty)
                                                ? ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          18,
                                                        ),
                                                    child: Image.asset(
                                                      'assets/images/avatar.webp',
                                                      fit: BoxFit.cover,
                                                      width: double.infinity,
                                                      height: double.infinity,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              nome,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.black87,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
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
                          style: const TextStyle(fontSize: 12),
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
                        // Só exibe a seção de foto se houver uma URL de foto cadastrada.
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
                              // Abre a imagem em tela cheia usando uma rota
                              // transparente (opaque: false) para manter o
                              // efeito de transição com Hero por cima da tela atual.
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
              // Saudação personalizada se o usuário estiver logado, ou genérica para visitantes.
              nomeUsuario != null
                  ? "Seja bem-vindo, $nomeUsuario!"
                  : "Seja bem-vindo, visitante!",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                // Só renderiza o mapa quando já temos uma posição definida
                // (real, do cache ou fallback) para evitar "saltos" visuais.
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
                        // Usa o cache local de tiles para permitir navegação offline.
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

                          // Define o ícone exibido para cada cluster, baseado
                          // na combinação de tipos de vaga presentes nele.
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

                          // Define o comportamento ao tocar em um cluster:
                          // - Se todos os marcadores estiverem na mesma coordenada
                          //   (sobrepostos), apenas dá zoom para ativar o "spiderfy".
                          // - Caso contrário, ajusta a câmera para enquadrar todos
                          //   os marcadores do cluster, com uma margem extra de
                          //   "respiro" e um teto de zoom de 17.
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
                          // Exibe o marcador de localização do usuário apenas
                          // quando o mapa estiver pronto, houver posição
                          // conhecida e o GPS estiver ativo/permitido.
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

                // Botão flutuante para centralizar o mapa na localização do usuário.
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

                // Tela de carregamento exibida enquanto o mapa ainda não
                // está pronto (aguardando posição inicial ser definida).
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
                    // Itens visíveis apenas para usuários não autenticados.
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
                    // Itens visíveis apenas para usuários autenticados.
                    if (nomeUsuario != null) ...[
                      // "Editar conta" só aparece para contas que não são do Google
                      // (contas Google têm seus dados gerenciados pelo provedor).
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
                      // "Excluir conta" só é exibido para contas Google,
                      // pois exige a revogação do acesso via Google Sign-In.
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
      // Botões flutuantes de acessibilidade para diminuir/aumentar a escala
      // de fonte/elementos do app, respeitando os limites de _nivelZoom (0 a 2).
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