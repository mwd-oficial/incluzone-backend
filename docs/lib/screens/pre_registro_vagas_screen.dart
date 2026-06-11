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

/// Serviço auxiliar que encapsula o cliente do Supabase e expõe
/// informações de autenticação do usuário atual.
class SupabaseService {
  final _supabase = Supabase.instance.client;

  /// Retorna `true` se houver uma sessão ativa (usuário autenticado),
  /// ou `false` caso contrário.
  bool get estaLogado => _supabase.auth.currentSession != null;

  /// Retorna o ID do usuário logado, ou `null` se não houver sessão ativa.
  String? get usuarioId => _supabase.auth.currentUser?.id;
}

/// Representa uma localização capturada pelo usuário em campo, ainda
/// pendente de finalização (registro completo da vaga de estacionamento).
///
/// Esses registros são persistidos localmente (via [SharedPreferences])
/// até que o usuário complete o cadastro na tela de registro de vagas.
class RegistroPendente {
  /// Identificador único do registro (gerado a partir do timestamp).
  final String id;

  /// Endereço resumido, usado apenas para exibição na lista de pendentes.
  final String endereco;

  /// Nome da rua/logradouro obtido via geocodificação reversa (pode ser nulo se offline).
  final String? logradouro;

  /// Número do imóvel mais próximo, obtido via geocodificação reversa.
  final String? numero;

  /// Bairro obtido via geocodificação reversa.
  final String? bairro;

  /// Cidade obtida via geocodificação reversa.
  final String? cidade;

  /// Estado (UF) obtido via geocodificação reversa.
  final String? estado;

  /// Latitude do ponto capturado pelo GPS.
  final double lat;

  /// Longitude do ponto capturado pelo GPS.
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

  /// Converte o objeto em um [Map] serializável em JSON, usado para
  /// salvar a lista de registros pendentes no [SharedPreferences].
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

  /// Reconstrói um [RegistroPendente] a partir de um [Map] previamente
  /// salvo (via [toJson]) e recuperado do [SharedPreferences].
  factory RegistroPendente.fromJson(Map<String, dynamic> json) =>
      RegistroPendente(
        id: json['id'],
        endereco: json['endereco'],
        logradouro: json['logradouro'],
        numero: json['numero'],
        bairro: json['bairro'],
        cidade: json['cidade'],
        estado: json['estado'],
        // Garante a conversão correta para double, já que o JSON pode
        // retornar int ou double dependendo da serialização.
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );
}

/// Tela responsável por permitir que o usuário, estando em campo,
/// pré-registre localizações de vagas de estacionamento (capturando
/// coordenadas GPS e fotos), para finalizar o cadastro completo depois,
/// quando estiver em casa.
class PreRegistroVagasScreen extends StatefulWidget {
  const PreRegistroVagasScreen({super.key});

  @override
  State<PreRegistroVagasScreen> createState() => _PreRegistroVagasScreenState();
}

class _PreRegistroVagasScreenState extends State<PreRegistroVagasScreen> {
  /// Lista de registros pendentes (localizações capturadas, mas ainda
  /// não finalizadas), persistida localmente no dispositivo.
  List<RegistroPendente> _registros = [];

  final supabase = Supabase.instance.client;

  /// Nível de zoom/escala da interface (0 a 2), usado para acessibilidade
  /// (aumentar/diminuir o tamanho dos elementos visuais do app).
  int _nivelZoom = 0;

  /// Calcula a distância em metros entre dois pontos geográficos
  /// (usado para evitar registros duplicados muito próximos).
  double _calcularDistancia(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }

  /// Incrementa ou decrementa o nível de zoom global do app (entre 0 e 2),
  /// persiste a preferência no [SharedPreferences] e notifica o widget
  /// raiz ([MyApp], via [myAppKey]) para atualizar a escala da interface.
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

    // Acessa o estado do MyApp através da chave global e chama o método
    // responsável por aplicar a nova escala em todo o app.
    myAppKey.currentState?.atualizarEscala(_nivelZoom);
  }

  /// Remove um registro pendente da lista (pelo seu [id]) e persiste
  /// a alteração imediatamente no [SharedPreferences].
  void _removerRegistro(String id) async {
    setState(() {
      _registros.removeWhere((item) => item.id == id);
    });
    await _salvarNoSharedPreferences();
  }

  /// Verifica se o dispositivo possui conexão real com a internet.
  ///
  /// Primeiro checa o status de conectividade do sistema (Wi-Fi/dados
  /// móveis); em seguida, faz uma resolução DNS real para confirmar que
  /// a conexão está de fato funcional (e não apenas "conectada" sem acesso
  /// à internet).
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

  /// Serializa a lista [_registros] em JSON e a salva no
  /// [SharedPreferences], garantindo persistência entre sessões do app.
  Future<void> _salvarNoSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    // Converte a lista de objetos para uma String JSON
    final String dadosCodificados = jsonEncode(
      _registros.map((item) => item.toJson()).toList(),
    );
    await prefs.setString('meus_registros', dadosCodificados);
  }

  /// Carrega a lista de registros pendentes previamente salva no
  /// [SharedPreferences] (se existir) e atualiza o estado da tela.
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

  /// Carrega as configurações iniciais da tela: o nível de zoom salvo
  /// e a lista de registros pendentes persistidos localmente.
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

    // Escuta mudanças no estado de autenticação do Supabase, permitindo
    // reagir a login/logout do usuário em tempo real.
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

  /// Indica se a busca pela localização atual está em andamento,
  /// usado para exibir um indicador de carregamento e desabilitar o botão.
  bool _carregandoLocalizacao = false;

  // --- Lógica de Câmera ---

  /// Abre a câmera do dispositivo para o usuário tirar uma foto e,
  /// caso uma foto seja capturada, salva-a diretamente na galeria
  /// usando o pacote `gal`.
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

  /// Obtém a localização atual do usuário via GPS, verifica se ela já
  /// não corresponde a um registro próximo existente (para evitar
  /// duplicidade), tenta obter o endereço por geocodificação reversa
  /// (caso haja conexão com a internet) e adiciona o novo registro
  /// pendente à lista, persistindo-o localmente.
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

      // Distância mínima (em metros) para considerar duas capturas como
      // sendo do mesmo local, evitando registros duplicados.
      const double raioMinimoMetros = 20.0;

      // Verifica se já existe um registro pendente próximo o suficiente
      // (dentro do raio mínimo) da posição atual.
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
        // Converte as coordenadas GPS em um endereço legível (geocodificação
        // reversa), mas apenas se houver conexão disponível.
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

  /// Verifica os pré-requisitos necessários para obter a posição GPS
  /// (serviço de localização ativo e permissões concedidas) e, caso
  /// tudo esteja correto, retorna a posição atual com a melhor precisão
  /// disponível.
  ///
  /// Lança exceções com códigos específicos ([GPS_DESATIVADO],
  /// [PERMISSAO_NEGADA], [PERMISSAO_NEGADA_PARA_SEMPRE]) para que
  /// [_tratarErroLocalizacao] possa exibir o diálogo apropriado.
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

  /// Mapeia o tipo de erro ocorrido ao tentar obter a localização
  /// (identificado pela mensagem da exceção lançada em
  /// [_determinarPosicao]) para o diálogo correspondente que deve ser
  /// exibido ao usuário.
  void _tratarErroLocalizacao(String erro) {
    if (erro.contains('GPS_DESATIVADO')) {
      _mostrarDialogoGpsDesativado();
    } else if (erro.contains('PERMISSAO_NEGADA_PARA_SEMPRE')) {
      _mostrarDialogoConfiguracoes();
    } else {
      _mostrarDialogoExplicacao();
    }
  }

  /// Exibe um diálogo genérico de aviso/confirmação com [titulo] e
  /// [mensagem], contendo apenas um botão "OK" para fechar.
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

  /// Exibe um diálogo explicando ao usuário por que a permissão de
  /// localização é necessária, oferecendo a opção de abrir as
  /// configurações do app para concedê-la manualmente.
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

  /// Exibe um diálogo informando que a permissão de localização foi
  /// negada permanentemente, direcionando o usuário às configurações
  /// do sistema para reativá-la manualmente.
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

  /// Exibe um diálogo informando que o serviço de GPS do dispositivo
  /// está desativado, com a opção de abrir diretamente as configurações
  /// de localização do sistema operacional.
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

  /// Exibe um aviso informando que o usuário está offline e que, embora
  /// não tenha sido possível converter as coordenadas em endereço, a
  /// localização GPS foi capturada e salva normalmente.
  ///
  /// Observação: este método não está sendo chamado em nenhum lugar do
  /// fluxo atual, mas permanece disponível para uso futuro.
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
                    // Gera dinamicamente a lista numerada de instruções
                    // a partir de uma lista fixa de strings.
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
                // Botão principal: dispara a captura da localização atual.
                // Fica desabilitado e mostra um spinner enquanto a busca
                // está em andamento.
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
                // Botão de atalho para abrir a câmera e salvar a foto
                // diretamente na galeria do dispositivo.
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

            // Lista de registros pendentes capturados pelo usuário,
            // permitindo excluí-los ou avançar para a tela de finalização
            // do cadastro.
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
                              // Botão de exclusão: pede confirmação antes
                              // de remover o registro pendente da lista.
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
                              // Botão "Registrar": valida conexão com a
                              // internet e autenticação do usuário antes
                              // de navegar para a tela de finalização do
                              // cadastro da vaga. Ao retornar dessa tela,
                              // recarrega a lista de pendentes (caso o
                              // item tenha sido finalizado/removido).
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
            // Logo do app exibida no rodapé da tela.
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
      // Botões flutuantes de acessibilidade para diminuir/aumentar o
      // nível de zoom (escala) da interface do app.
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Botão A-: diminui o nível de zoom (desabilitado se já estiver
          // no nível mínimo, 0).
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

          // Botão A+: aumenta o nível de zoom (desabilitado se já estiver
          // no nível máximo, 2).
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