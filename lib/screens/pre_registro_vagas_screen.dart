import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:convert';
import '../main.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;

  // Retorna true se houver uma sessão ativa, false caso contrário
  bool get estaLogado => _supabase.auth.currentSession != null;

  // Opcional: Obter o ID do usuário logado
  String? get usuarioId => _supabase.auth.currentUser?.id;
}

class RegistroPendente {
  final String id;
  final String endereco; // Mantido para exibição na lista
  final String? logradouro;
  final String? numero;
  final String? bairro;
  final String? cidade;
  final String? estado;
  final double lat;
  final double lng;

  RegistroPendente({
    required this.id,
    required this.endereco,
    this.logradouro,
    this.numero,
    this.bairro,
    this.cidade,
    this.estado,
    required this.lat,
    required this.lng,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'endereco': endereco,
    'logradouro': logradouro,
    'numero': numero,
    'bairro': bairro,
    'cidade': cidade,
    'estado': estado,
    'lat': lat,
    'lng': lng,
  };

  factory RegistroPendente.fromJson(Map<String, dynamic> json) =>
      RegistroPendente(
        id: json['id'],
        endereco: json['endereco'],
        logradouro: json['logradouro'],
        numero: json['numero'],
        bairro: json['bairro'],
        cidade: json['cidade'],
        estado: json['estado'],
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );
}

class PreRegistroVagasScreen extends StatefulWidget {
  const PreRegistroVagasScreen({super.key});

  @override
  State<PreRegistroVagasScreen> createState() => _PreRegistroVagasScreenState();
}

class _PreRegistroVagasScreenState extends State<PreRegistroVagasScreen> {
  // Dentro da classe _PreRegistroVagasScreenState
  List<RegistroPendente> _registros = [];
  final supabase = Supabase.instance.client;
  int _nivelZoom = 0;
  double _calcularDistancia(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
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

  void _removerRegistro(String id) async {
    setState(() {
      _registros.removeWhere((item) => item.id == id);
    });
    await _salvarNoSharedPreferences();
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

  Future<void> _salvarNoSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    // Converte a lista de objetos para uma String JSON
    final String dadosCodificados = jsonEncode(
      _registros.map((item) => item.toJson()).toList(),
    );
    await prefs.setString('meus_registros', dadosCodificados);
  }

  Future<void> _carregarDoSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final String? dadosString = prefs.getString('meus_registros');

    if (dadosString != null) {
      final List<dynamic> dadosDecodificados = jsonDecode(dadosString);
      setState(() {
        _registros = dadosDecodificados
            .map((item) => RegistroPendente.fromJson(item))
            .toList();
      });
    }
  }

  Future<void> _carregarConfiguracoesIniciais() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    });
    _carregarDoSharedPreferences(); // Sua função de dados
  }

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();

    supabase.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;

      switch (event) {
        case AuthChangeEvent.signedIn:
          print("Usuário logou!");
          break;
        case AuthChangeEvent.signedOut:
          print("Usuário deslogou!");
          // Redirecionar para tela de login
          break;
        default:
          break;
      }
    });
  }

  final service = SupabaseService();
  final ImagePicker _picker = ImagePicker();

  // Variáveis para armazenar os dados obtidos
  bool _carregandoLocalizacao = false;

  // --- Lógica de Câmera ---
  Future<void> _abrirCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);

      if (photo != null) {
        await Gal.putImage(photo.path);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Foto salva na Galeria com sucesso!")),
        );
      }
    } catch (e) {
      debugPrint("Erro ao acessar câmera: $e");
    }
  }

  // --- Lógica de Localização Integrada ---
  Future<void> _obterLocalizacao() async {
    setState(() => _carregandoLocalizacao = true);

    try {
      /*
      final random = Random();
      Position posicao = Position(
        latitude: -23.5505 + (random.nextDouble() * 0.1),
        longitude: -46.6333 + (random.nextDouble() * 0.1),
        timestamp: DateTime.now(),
        accuracy: 1,
        altitude: 1,
        heading: 0,
        speed: 0,
        speedAccuracy: 1,
        altitudeAccuracy: 1,
        headingAccuracy: 1,
      );
      */
      Position posicao = await _determinarPosicao();
      const double raioMinimoMetros = 20.0;

      bool jaExiste = _registros.any((reg) {
        double distancia = _calcularDistancia(
          posicao.latitude,
          posicao.longitude,
          reg.lat,
          reg.lng,
        );
        return distancia < raioMinimoMetros;
      });

      if (jaExiste) {
        setState(() => _carregandoLocalizacao = false);
        if (mounted) {
          _mostrarDialogo(
            "Local já registrado",
            "Você já capturou a localização deste local recentemente. Verifique sua lista de registros pendentes.",
          );
        }
        return; // Interrompe a função aqui
      }
      var connectivityResult = await (Connectivity().checkConnectivity());
      bool estaOnline = !connectivityResult.contains(ConnectivityResult.none);

      // 1. Declaramos variáveis de suporte fora do escopo do IF
      String enderecoExibicao = "Localização salva offline";
      String? logradouro, numero, bairro, cidade, estado;

      if (estaOnline) {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          posicao.latitude,
          posicao.longitude,
        );

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;

          // Preenchemos as variáveis com os dados do GPS
          logradouro = place.thoroughfare;
          numero = place.subThoroughfare;
          bairro = place.subLocality;
          cidade = place.subAdministrativeArea;
          estado = place.administrativeArea;

          // Monta a string bonitinha para aparecer na lista
          enderecoExibicao =
              "${logradouro ?? 'Rua desconhecida'} - ${bairro ?? ''}";
        }
      }

      // 2. Agora o setState consegue acessar as variáveis locais
      setState(() {
        _registros.add(
          RegistroPendente(
            id: DateTime.now().millisecondsSinceEpoch
                .toString(), // ID mais limpo
            endereco: enderecoExibicao,
            logradouro: logradouro,
            numero: numero,
            bairro: bairro,
            cidade: cidade,
            estado: estado,
            lat: posicao.latitude,
            lng: posicao.longitude,
          ),
        );
        _carregandoLocalizacao = false;
      });

      await _salvarNoSharedPreferences();
    } catch (e) {
      setState(() => _carregandoLocalizacao = false);
      _tratarErroLocalizacao(e.toString());
    }
  }

  // Função auxiliar para determinar a posição
  Future<Position> _determinarPosicao() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Verifica se o GPS está ligado no aparelho
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Se o GPS estiver desligado, não adianta pedir permissão, tem que pedir para ligar o GPS
      throw Exception('GPS_DESATIVADO');
    }

    // 2. Verifica o status atual da permissão
    permission = await Geolocator.checkPermission();

    // Se o usuário negou antes, pedimos de novo
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Se ele negar na caixa de diálogo nativa do Android/iOS
        throw Exception('PERMISSAO_NEGADA');
      }
    }

    // 3. Se estiver negado permanentemente, agora sim enviamos para as configurações
    if (permission == LocationPermission.deniedForever) {
      throw Exception('PERMISSAO_NEGADA_PARA_SEMPRE');
    }

    // 4. Se chegou aqui, está tudo liberado
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best, // Ou bestForNavigation
    );
  }

  // Função para tratar os erros e mostrar os diálogos
  void _tratarErroLocalizacao(String erro) {
    if (erro.contains('GPS_DESATIVADO')) {
      _mostrarDialogoGpsDesativado();
    } else if (erro.contains('PERMISSAO_NEGADA_PARA_SEMPRE')) {
      _mostrarDialogoConfiguracoes();
    } else {
      _mostrarDialogoExplicacao();
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

  void _mostrarDialogoExplicacao() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Localização necessária'),
        content: const Text(
          'Precisamos da sua localização para registrar corretamente a vaga de estacionamento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openAppSettings();
            },
            child: const Text('Abrir configurações'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoConfiguracoes() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permissão necessária'),
        content: const Text(
          'A permissão de localização foi desativada permanentemente. Ative manualmente nas configurações.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openAppSettings();
            },
            child: const Text('Abrir configurações'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoGpsDesativado() {
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

  void _mostrarAvisoOffline() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.wifi_off, color: Colors.orange),
            SizedBox(width: 10),
            Text("Você está offline"),
          ],
        ),
        content: const Text(
          "Não foi possível converter a localização em endereço agora, mas as coordenadas exatas do GPS foram capturadas e salvas no dispositivo.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Entendido"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pré-registrar Vagas"),
        scrolledUnderElevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Card de Instrução
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Está na rua? Siga estes passos:"),
                    const SizedBox(height: 12),
                    ...[
                      "Clique no botão \"Obter localização atual\"",
                      "Tire fotos de cada tipo de vaga especial (PCD, idoso, etc.) que encontrar no local.",
                      "Conte quantas vagas existem de cada tipo.",
                      "Finalização: Quando estiver em casa e com calma, abra o app para concluir o registro.",
                    ].asMap().entries.map((entry) {
                      int idx = entry.key + 1;
                      String text = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("$idx. "),
                            Expanded(child: Text(text)),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Área de Ações
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _carregandoLocalizacao
                        ? null
                        : _obterLocalizacao,
                    icon: _carregandoLocalizacao
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: const Text("Obter localização atual"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.camera_alt),
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: _abrirCamera,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Exibição do Endereço Obtido
            // Substitua o Container estático por este bloco:
            Expanded(
              child: ListView.builder(
                itemCount: _registros.length,
                itemBuilder: (context, index) {
                  final item = _registros[index];
                  return Card(
                    // Usando Card para um visual melhor
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.endereco,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  // Abre o diálogo de confirmação
                                  showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                        title: const Text("Confirmar exclusão"),
                                        content: const Text(
                                          "Tem certeza que deseja excluir esta localização?",
                                        ),
                                        actions: [
                                          TextButton(
                                            child: const Text("Cancelar"),
                                            onPressed: () => Navigator.of(
                                              context,
                                            ).pop(), // Fecha o diálogo
                                          ),
                                          TextButton(
                                            child: const Text(
                                              "Excluir",
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                            onPressed: () {
                                              _removerRegistro(
                                                item.id,
                                              ); // Executa a função original
                                              Navigator.of(
                                                context,
                                              ).pop(); // Fecha o diálogo
                                            },
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                              TextButton(
                                // No pendente.dart, altere o botão de "Registrar" para isso:
                                onPressed: () async {
                                  if (!(await _temInternet())) {
                                    if (mounted) {
                                      _mostrarDialogo(
                                        "Sem Conexão",
                                        "Parece que você está offline. Verifique sua conexão com a internet e tente novamente.",
                                      );
                                    }
                                    return; // Interrompe a execução aqui
                                  }
                                  if (service.estaLogado) {
                                    // Aguarda o usuário terminar o registro na outra tela
                                    await Navigator.pushNamed(
                                      // Use pushNamed em vez de pushReplacementNamed para poder voltar
                                      context,
                                      '/registro_vagas',
                                      arguments: item,
                                    );
                                    // Quando ele voltar para esta tela, executa o carregamento de novo:
                                    _carregarDoSharedPreferences();
                                  } else {
                                    Navigator.pushNamed(context, '/login');
                                  }
                                },
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text("Registrar"),
                                    SizedBox(
                                      width: 8,
                                    ), // Pequeno espaço entre o texto e a seta
                                    Icon(Icons.arrow_forward),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              width: double.infinity, // Largura 100%
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment
                  .centerLeft, // Alinha a logo à esquerda (como estava no Positioned)
              child: Image.asset(
                'assets/images/titulo.webp',
                width: 150,
                fit: BoxFit.contain,
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
