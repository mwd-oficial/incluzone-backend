import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pre_registro_vagas_screen.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../main.dart';
import '../services/gemini_service.dart';

class RegistroVagasScreen extends StatefulWidget {
  const RegistroVagasScreen({super.key});

  @override
  State<RegistroVagasScreen> createState() => _RegistroVagasScreenState();
}

class _VagaSelecionada {
  String tipo;
  int quantidade;
  int quantidadeExistente;
  File? foto;
  String? urlFotoExistente; // Adicionado para fotos vindas do banco
  dynamic idVaga; // Para saber se vamos atualizar ou inserir
  bool validando = false;
  String? erroValidacao;

  _VagaSelecionada({
    required this.tipo,
    this.quantidade = 1,
    this.quantidadeExistente = 1,
    this.urlFotoExistente,
    this.idVaga,
  });
}

class _RegistroVagasScreenState extends State<RegistroVagasScreen> {
  final supabase = Supabase.instance.client;
  late final TextEditingController referenciaController;
  RegistroPendente? dados;
  bool carregando = false;
  int _nivelZoom = 0;
  String? idLocalExistente;
  List<String> idsParaDeletar =
      []; // Armazena os IDs das vagas que serão removidas

  // Lista de tipos de vagas disponíveis (Enum do banco)
  final List<String> tiposDisponiveis = ["Idoso", "PcD", "Gestante", "Autista"];

  // Vagas que o usuário está configurando no formulário
  List<_VagaSelecionada> vagasParaRegistro = [];

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
    referenciaController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (dados == null) {
      final args = ModalRoute.of(context)!.settings.arguments;

      if (args is RegistroPendente) {
        // Fluxo normal: vindo da captura de endereço
        dados = args;
        _verificarPontoExistente();
      } else if (args is Map<String, dynamic>) {
        // Fluxo Histórico: vindo da lista de registros já salvos
        _preencherComDadosDoHistorico(args);
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

  void _preencherComDadosDoHistorico(Map<String, dynamic> item) {
    setState(() {
      dados = RegistroPendente(
        id: item['id'].toString(),
        endereco:
            item['endereco'] ??
            "${item['logradouro'] ?? 'Rua desconhecida'} - ${item['bairro'] ?? ''}",
        logradouro: item['logradouro'] ?? '',
        numero: item['numero'] ?? '',
        bairro: item['bairro'] ?? '',
        cidade: item['cidade'] ?? '',
        estado: item['estado'] ?? '',
        lat: (item['latitude'] as num).toDouble(),
        lng: (item['longitude'] as num).toDouble(),
      );

      idLocalExistente = item['id'].toString();
      referenciaController.text = item['referencia'] ?? '';

      if (item['vagas'] != null) {
        vagasParaRegistro = (item['vagas'] as List).map((v) {
          // Captura a quantidade vinda do histórico/banco
          final qte = v['quantidade'] is int
              ? v['quantidade']
              : int.tryParse(v['quantidade'].toString()) ?? 1;

          return _VagaSelecionada(
            tipo: v['tipo_vaga']?.toString() ?? '',
            quantidade: qte,
            quantidadeExistente:
                qte, // Agora a comparação no salvar vai funcionar!
            idVaga: v['id_vaga'] ?? v['id'],
            urlFotoExistente: v['foto_url']?.toString(),
          );
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    referenciaController.dispose();
    super.dispose();
  }

  Widget _construirPreviewFoto(_VagaSelecionada vaga) {
    if (vaga.foto != null) {
      return Image.file(vaga.foto!, width: 50, height: 50, fit: BoxFit.cover);
    } else if (vaga.urlFotoExistente != null) {
      return Image.network(
        vaga.urlFotoExistente!,
        width: 50,
        height: 50,
        fit: BoxFit.cover,
      );
    }
    return const Icon(Icons.photo_library, color: Color.fromARGB(0, 0, 0, 0));
  }

  Future<void> _verificarPontoExistente() async {
    if (dados == null) return;
    setState(() => carregando = true);

    try {
      final double margemErro = 0.0003; // ~33 metros

      final localExistente = await supabase
          .from('locais_com_vagas')
          .select()
          .gte('latitude', dados!.lat - margemErro)
          .lte('latitude', dados!.lat + margemErro)
          .gte('longitude', dados!.lng - margemErro)
          .lte('longitude', dados!.lng + margemErro)
          .maybeSingle();

      if (localExistente != null) {
        idLocalExistente = localExistente['id'].toString();
        referenciaController.text = localExistente['referencia'] ?? '';

        if (localExistente['vagas'] != null) {
          setState(() {
            vagasParaRegistro = (localExistente['vagas'] as List).map((v) {
              final qte = v['quantidade'] is int
                  ? v['quantidade']
                  : int.tryParse(v['quantidade'].toString()) ?? 1;
              return _VagaSelecionada(
                tipo: v['tipo_vaga']?.toString() ?? '',
                quantidade: qte,
                quantidadeExistente: qte, // <--- Salvamos o valor original aqui
                idVaga: v['id_vaga'],
                urlFotoExistente: v['foto_url']?.toString(),
              );
            }).toList();
          });
        }
      }
    } catch (e) {
      debugPrint("Erro ao verificar ponto: $e");
    } finally {
      setState(() => carregando = false);
    }
  }

  Future<void> _limparRegistroPendente(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final String? dadosString = prefs.getString('meus_registros');

    if (dadosString != null) {
      // 1. Pega a lista atual do celular
      List<dynamic> dadosDecodificados = jsonDecode(dadosString);

      // 2. Remove o item que acabou de ser salvo no banco de dados
      dadosDecodificados.removeWhere((item) => item['id'] == id);

      // 3. Salva a lista atualizada (sem o item) de volta no celular
      await prefs.setString('meus_registros', jsonEncode(dadosDecodificados));
      print("Registro removido dos pendentes com sucesso.");
    }
  }

  Future<File?> _comprimirParaWebp(File arquivoOriginal) async {
    // Pega o diretório temporário do sistema (iOS/Android)
    final dir = await path_provider.getTemporaryDirectory();

    // Cria um caminho único para o arquivo de saída
    final outPath =
        "${dir.absolute.path}/temp_${DateTime.now().millisecondsSinceEpoch}.webp";

    var resultado = await FlutterImageCompress.compressAndGetFile(
      arquivoOriginal.absolute.path,
      outPath,
      format: CompressFormat.webp,
      quality: 10,
    );

    // No FlutterImageCompress >= 2.0.0, o retorno é do tipo XFile
    return resultado != null ? File(resultado.path) : null;
  }

  Future<void> _selecionarFoto(_VagaSelecionada vaga) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        vaga.validando = true; // Começa o carregamento específico deste card
        vaga.erroValidacao = null; // Limpa erros anteriores
      });

      try {
        File arquivoOriginal = File(pickedFile.path);
        File? arquivoWebp = await _comprimirParaWebp(arquivoOriginal);

        if (arquivoWebp != null) {
          // 1. Atualiza a foto na tela para o usuário ver
          setState(() => vaga.foto = arquivoWebp);

          // 2. Chama o Gemini para validar em tempo real
          final resultado = await GeminiService.validarVaga(
            arquivoWebp,
            vaga.tipo,
          );

          setState(() {
            if (resultado['status'] == true) {
              vaga.erroValidacao = null; // Tudo certo!
            } else {
              // Mapeia o erro
              vaga.erroValidacao = _traduzirErroGemini(resultado['message']);
              vaga.foto = null; // Opcional: remove a foto se for inválida
            }
          });
        }
      } catch (e) {
        setState(() => vaga.erroValidacao = "Erro ao processar imagem");
      } finally {
        setState(() => vaga.validando = false); // Para o carregamento do card
      }
    }
  }

  // Função auxiliar para traduzir os códigos que definimos no prompt
  String _traduzirErroGemini(String message) {
    switch (message) {
      case "NOT_A_PARKING_SPOT":
        return "Não parece uma vaga.";
      case "WRONG_TYPE":
        return "Tipo de vaga incorreto.";
      case "NO_SIGNALIZATION":
        return "Sinalização não encontrada.";
      case "POOR_QUALITY":
        return "Imagem com qualidade baixa.";
      default:
        return "Imagem inválida.";
    }
  }

  Future<void> _salvarTudo() async {
    if (vagasParaRegistro.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Selecione ao menos um tipo de vaga")),
      );
      return;
    }

    // Validar fotos: precisa de foto local OU já ter uma URL no banco
    for (var v in vagasParaRegistro) {
      if (v.foto == null && v.urlFotoExistente == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("A foto para ${v.tipo} é obrigatória")),
        );
        return;
      }
    }

    setState(() => carregando = true);

    try {
      final userId = supabase.auth.currentUser?.id;

      // 1. Salvar ou Atualizar o Local
      final localResponse = await supabase
          .from('locais')
          .upsert({
            if (idLocalExistente != null) 'id': idLocalExistente,
            'latitude': dados!.lat,
            'longitude': dados!.lng,
            'referencia': referenciaController.text,
            'logradouro': dados!.logradouro,
            'numero': dados!.numero,
            'bairro': dados!.bairro,
            'cidade': dados!.cidade,
            'estado': dados!.estado,
            if (idLocalExistente == null) 'id_usuario_criador': userId,
          })
          .select()
          .single();

      final localId = localResponse['id'];

      // 2. Deletar vagas removidas
      if (idsParaDeletar.isNotEmpty) {
        await supabase.from('vagas').delete().inFilter('id', idsParaDeletar);
      }

      // 3. Salvar cada vaga individualmente
      for (var vaga in vagasParaRegistro) {
        if (vaga.validando) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Aguarde a validação das imagens...")),
          );
          return;
        }
        if (vaga.erroValidacao != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Corrija a foto de ${vaga.tipo} antes de salvar."),
            ),
          );
          return;
        }

        String? urlParaSalvar = vaga.urlFotoExistente;

        // Lógica de Verificação de Mudança
        bool fotoMudou = vaga.foto != null;
        // Comparamos a quantidade atual com a que veio do banco (se houver)
        bool quantidadeMudou =
            vaga.idVaga != null &&
            (vaga.quantidade != vaga.quantidadeExistente);
        bool ehNovaVaga = vaga.idVaga == null;

        // SE O USUÁRIO TIROU UMA NOVA FOTO
        if (fotoMudou) {
          if (vaga.urlFotoExistente != null) {
            try {
              final String nomeArquivoAntigo = vaga.urlFotoExistente!
                  .split('/')
                  .last;
              await supabase.storage.from('vagas_images').remove([
                nomeArquivoAntigo,
              ]);
            } catch (e) {
              print("Erro ao limpar arquivo antigo: $e");
            }
          }

          final fileName = 'vaga_${DateTime.now().millisecondsSinceEpoch}.webp';
          await supabase.storage
              .from('vagas_images')
              .upload(fileName, vaga.foto!);
          urlParaSalvar = supabase.storage
              .from('vagas_images')
              .getPublicUrl(fileName);
        }

        // Preparamos o mapa de dados para o upsert
        final dadosVaga = {
          if (vaga.idVaga != null) 'id': vaga.idVaga,
          'id_local': localId,
          'tipo_vaga': vaga.tipo,
          'quantidade': vaga.quantidade,
          'foto_url': urlParaSalvar,
        };

        // Se algo mudou (ou é novo), atualizamos os campos de auditoria
        if (fotoMudou || quantidadeMudou || ehNovaVaga) {
          dadosVaga['id_usuario_ultima_alteracao'] = userId;
          dadosVaga['data_ultima_alteracao'] = DateTime.now()
              .toUtc()
              .toIso8601String();
        }

        await supabase.from('vagas').upsert(dadosVaga);
      }

      // 4. Registrar contribuição
      await supabase.from('contribuicoes').upsert({
        'id_usuario': userId,
        'id_local': localId,
        'data_contribuicao': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'id_usuario,id_local');

      if (dados != null) await _limparRegistroPendente(dados!.id);

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Dados atualizados com sucesso!")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Erro ao salvar: $e")));
    } finally {
      setState(() => carregando = false);
    }
  }

  Widget _criarLinhaDeChips(List<String> tipos) {
    return Row(
      children: tipos.map((tipo) {
        bool selecionado = vagasParaRegistro.any((v) => v.tipo == tipo);
        return Expanded(
          // Expanded faz com que ocupem o mesmo espaço na linha
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              label: Center(child: Text(tipo)),
              selected: selecionado,
              onSelected: (bool value) {
                setState(() {
                  if (value) {
                    vagasParaRegistro.add(_VagaSelecionada(tipo: tipo));
                  } else {
                    final vagaRemovida = vagasParaRegistro.firstWhere(
                      (v) => v.tipo == tipo,
                    );
                    if (vagaRemovida.idVaga != null) {
                      idsParaDeletar.add(vagaRemovida.idVaga);
                    }
                    vagasParaRegistro.removeWhere((v) => v.tipo == tipo);
                  }
                });
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enderecoCompleto = dados != null
        ? "${dados!.logradouro}, ${dados!.numero}\n${dados!.bairro}\n${dados!.cidade} - ${dados!.estado}"
        : "Dados não encontrados";

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text("Registrar Vagas")),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Endereço Identificado:",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    enderecoCompleto,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextField(
                    controller: referenciaController,
                    decoration: const InputDecoration(
                      labelText: "Ponto de Referência",
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text(
                    "Tipos de Vagas no Local:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  // Chips para selecionar tipos
                  Column(
                    children: [
                      _criarLinhaDeChips(["Idoso", "PcD"]),
                      const SizedBox(height: 8),
                      _criarLinhaDeChips(["Gestante", "Autista"]),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Lista dinâmica de detalhes das vagas
                  ...vagasParaRegistro.reversed.map(
                    (vaga) => Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  vaga.tipo,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () => setState(
                                        () => vaga.quantidade > 1
                                            ? vaga.quantidade--
                                            : null,
                                      ),
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                    ),
                                    Text(
                                      vaga.quantidade.toString(),
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          setState(() => vaga.quantidade++),
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(),
                            ListTile(
                              leading: vaga.validando
                                  ? const CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ) // Mostra progresso no lugar do ícone
                                  : Icon(
                                      vaga.foto == null 
                                          ? Icons.photo_library
                                          : (vaga.erroValidacao != null
                                                ? Icons.error
                                                : Icons.check_circle),
                                      color:
                                          vaga.foto == null 
                                          ? Colors.grey
                                          : (vaga.erroValidacao != null
                                                ? Colors.red
                                                : Colors.green),
                                    ),
                              title: Text(
                                vaga.validando
                                    ? "Validando com IA..."
                                    : (vaga.erroValidacao ??
                                          (vaga.foto == null
                                              ? "Selecionar foto"
                                              : "Foto validada")),
                                style: TextStyle(
                                  color: vaga.erroValidacao != null
                                      ? Colors.red
                                      : Colors.black,
                                ),
                              ),
                              onTap: vaga.validando
                                  ? null
                                  : () => _selecionarFoto(vaga),
                              trailing: _construirPreviewFoto(vaga),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Center(
                    child: ElevatedButton(
                      onPressed: carregando ? null : _salvarTudo,
                      child: carregando
                          ? const CircularProgressIndicator()
                          : const Text("Confirmar e Salvar"),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity, // Largura 100%
            padding: const EdgeInsets.all(25),
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
