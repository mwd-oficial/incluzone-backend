/*
////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////



ESTE CÓDIGO É APENAS PARA CONSULTA E NÃO DEVE SER EDITADO!!!!!!!!!!!!!!!!!!!



/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
*/


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

/// Tela responsável pelo registro e edição de vagas especiais de estacionamento.
///
/// Pode ser acessada por dois fluxos distintos:
/// 1. **Fluxo normal**: Vindo da tela de captura de endereço, recebendo um [RegistroPendente].
/// 2. **Fluxo de histórico**: Vindo da lista de registros salvos, recebendo um [Map<String, dynamic>]
///    com os dados já persistidos no banco.
class RegistroVagasScreen extends StatefulWidget {
  const RegistroVagasScreen({super.key});

  @override
  State<RegistroVagasScreen> createState() => _RegistroVagasScreenState();
}

/// Modelo de dados local que representa uma vaga sendo configurada pelo usuário
/// antes de ser persistida no banco de dados.
class _VagaSelecionada {
  /// Tipo da vaga, correspondente ao Enum do banco (ex: "Idoso", "PcD").
  String tipo;

  /// Quantidade de vagas deste tipo informada pelo usuário na sessão atual.
  int quantidade;

  /// Quantidade original vinda do banco, usada para detectar se houve alteração
  /// e, assim, acionar a lógica de auditoria no salvamento.
  int quantidadeExistente;

  /// Arquivo de imagem selecionado localmente nesta sessão. Será nulo se
  /// o usuário não escolheu uma nova foto (mantendo a existente no banco).
  File? foto;

  /// URL pública da foto já salva no Storage do Supabase. Usada para exibição
  /// quando não há nova foto local selecionada.
  String? urlFotoExistente;

  /// ID da vaga no banco de dados. Se nulo, indica que é uma vaga nova (INSERT);
  /// se preenchido, indica que a operação será uma atualização (UPDATE via upsert).
  dynamic idVaga;

  /// Indica se a validação por IA (Gemini) está em andamento para esta vaga,
  /// bloqueando interações e exibindo um indicador de progresso no card.
  bool validando = false;

  /// Mensagem de erro retornada pela validação do Gemini. Se nulo, a foto
  /// foi validada com sucesso ou ainda não foi selecionada.
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

  /// Dados do ponto de registro atual, preenchidos via argumentos de rota.
  RegistroPendente? dados;

  /// Controla a exibição de indicadores de carregamento globais na tela,
  /// como durante a busca de dados existentes e o salvamento final.
  bool carregando = false;

  /// Nível de zoom de acessibilidade da fonte (0 = padrão, 1 = médio, 2 = máximo).
  /// Persistido via SharedPreferences e aplicado globalmente via [myAppKey].
  int _nivelZoom = 0;

  /// ID do local já existente no banco de dados (tabela `locais`). Se preenchido,
  /// o salvamento executará um UPSERT de atualização; se nulo, criará um novo registro.
  String? idLocalExistente;

  /// Lista de IDs de vagas (tabela `vagas`) marcadas para exclusão.
  /// Populada quando o usuário desmarca um chip de tipo de vaga que já existe no banco.
  List<String> idsParaDeletar = [];

  /// Tipos de vagas disponíveis para seleção, espelhando o Enum definido no banco de dados.
  final List<String> tiposDisponiveis = ["Idoso", "PcD", "Gestante", "Autista"];

  /// Lista reativa de vagas que o usuário está configurando no formulário.
  /// Cada item representa um tipo de vaga com sua quantidade e foto associada.
  List<_VagaSelecionada> vagasParaRegistro = [];

  @override
  void initState() {
    super.initState();
    // Carrega o nível de zoom salvo antes de renderizar a tela.
    _carregarConfiguracoesIniciais();
    referenciaController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A verificação `dados == null` evita que o bloco seja executado
    // em reconstruções subsequentes do widget, processando os argumentos apenas uma vez.
    if (dados == null) {
      final args = ModalRoute.of(context)!.settings.arguments;

      if (args is RegistroPendente) {
        // Fluxo normal: vindo da captura de endereço
        dados = args;
        // Verifica se já existe um ponto cadastrado próximo às coordenadas recebidas,
        // para pré-preencher o formulário em caso de edição.
        _verificarPontoExistente();
      } else if (args is Map<String, dynamic>) {
        // Fluxo Histórico: vindo da lista de registros já salvos
        _preencherComDadosDoHistorico(args);
      }
    }
  }

  /// Atualiza o nível de zoom de acessibilidade e persiste a preferência do usuário.
  ///
  /// [aumentar]: Se `true`, incrementa o zoom (limite máximo: 2).
  ///             Se `false`, decrementa o zoom (limite mínimo: 0).
  ///
  /// Após a atualização local, notifica o estado global do [MyApp] através
  /// da [myAppKey] para que a escala de texto seja aplicada em toda a aplicação.
  Future<void> _atualizarZoom(bool aumentar) async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      if (aumentar && _nivelZoom < 2) {
        _nivelZoom++;
      } else if (!aumentar && _nivelZoom > 0) {
        _nivelZoom--;
      }
    });

    // Salva a preferência no disco para persistir entre sessões do aplicativo.
    await prefs.setInt('nivel_zoom', _nivelZoom);

    // Acessa o estado do MyApp através da chave global e chama o método de atualização,
    // propagando a mudança de escala para todos os widgets da árvore.
    myAppKey.currentState?.atualizarEscala(_nivelZoom);
  }

  /// Lê o nível de zoom persistido nas SharedPreferences e aplica ao estado local.
  /// Chamado no [initState] para restaurar a preferência do usuário ao abrir a tela.
  Future<void> _carregarConfiguracoesIniciais() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Retorna 0 (padrão) caso nenhuma preferência tenha sido salva anteriormente.
      _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    });
  }

  /// Reconstrói o objeto [dados] e pré-preenche o formulário a partir de um
  /// registro já existente vindo do histórico do usuário.
  ///
  /// [item]: Map com os dados do local e suas vagas, conforme retornado pelo banco.
  ///
  /// A propriedade [quantidadeExistente] é preenchida com o valor do banco para
  /// que a lógica de auditoria em [_salvarTudo] possa detectar alterações corretamente.
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
          // Garante que a quantidade seja sempre um inteiro válido,
          // independente do tipo retornado pelo banco (int ou String).
          final qte = v['quantidade'] is int
              ? v['quantidade']
              : int.tryParse(v['quantidade'].toString()) ?? 1;

          return _VagaSelecionada(
            tipo: v['tipo_vaga']?.toString() ?? '',
            quantidade: qte,
            // Salva o valor original do banco para que a comparação
            // de mudança de quantidade em [_salvarTudo] funcione corretamente.
            quantidadeExistente: qte,
            idVaga: v['id_vaga'] ?? v['id'],
            urlFotoExistente: v['foto_url']?.toString(),
          );
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    // Libera o controller do TextField para evitar memory leaks.
    referenciaController.dispose();
    super.dispose();
  }

  /// Constrói o widget de preview da foto para um card de vaga.
  ///
  /// A prioridade de exibição é: foto local (nova) > URL remota (existente) > ícone placeholder.
  ///
  /// [vaga]: A vaga cujo preview será exibido.
  Widget _construirPreviewFoto(_VagaSelecionada vaga) {
    if (vaga.foto != null) {
      // Prioridade 1: Exibe a foto recém-selecionada do dispositivo local.
      return Image.file(vaga.foto!, width: 50, height: 50, fit: BoxFit.cover);
    } else if (vaga.urlFotoExistente != null) {
      // Prioridade 2: Exibe a foto remota já salva no Supabase Storage.
      return Image.network(
        vaga.urlFotoExistente!,
        width: 50,
        height: 50,
        fit: BoxFit.cover,
      );
    }
    // Prioridade 3 (fallback): Exibe um ícone de placeholder transparente,
    // sinalizando que nenhuma foto foi selecionada ainda.
    return const Icon(Icons.photo_library, color: Color.fromARGB(0, 0, 0, 0));
  }

  /// Consulta o banco de dados para verificar se já existe um ponto de vagas
  /// cadastrado próximo às coordenadas do registro pendente.
  ///
  /// Utiliza uma margem de erro de ~33 metros (0.0003 graus) para cobrir
  /// imprecisões de GPS e evitar duplicatas por pequenas variações de coordenada.
  /// Se um ponto existente for encontrado, pré-preenche o formulário com seus dados.
  Future<void> _verificarPontoExistente() async {
    if (dados == null) return;
    setState(() => carregando = true);

    try {
      // Define a margem de tolerância em graus decimais (~33 metros).
      final double margemErro = 0.0003;

      // Busca na view `locais_com_vagas` (que já inclui os dados das vagas via JOIN)
      // qualquer ponto dentro da caixa delimitadora definida pela margem de erro.
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
                // Salva o valor original do banco para comparação futura,
                // permitindo detectar alterações de quantidade na auditoria.
                quantidadeExistente: qte,
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

  /// Remove um registro da fila de pendentes armazenada localmente nas SharedPreferences.
  ///
  /// Chamado após o salvamento bem-sucedido no banco, para sincronizar
  /// o estado local e evitar que o registro apareça novamente na lista de pendentes.
  ///
  /// [id]: O ID do registro pendente a ser removido da lista local.
  Future<void> _limparRegistroPendente(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final String? dadosString = prefs.getString('meus_registros');

    if (dadosString != null) {
      // Desserializa a lista de registros pendentes armazenada como JSON.
      List<dynamic> dadosDecodificados = jsonDecode(dadosString);

      // Remove apenas o item com o ID correspondente ao registro recém-salvo.
      dadosDecodificados.removeWhere((item) => item['id'] == id);

      // Reserializa e persiste a lista atualizada (sem o item removido).
      await prefs.setString('meus_registros', jsonEncode(dadosDecodificados));
      print("Registro removido dos pendentes com sucesso.");
    }
  }

  /// Comprime um arquivo de imagem para o formato WebP com qualidade reduzida.
  ///
  /// A compressão agressiva (qualidade 10) é intencional para minimizar o
  /// consumo de banda e o espaço de armazenamento no Supabase Storage,
  /// já que as imagens servem apenas como evidência fotográfica, não como arte.
  ///
  /// [arquivoOriginal]: O arquivo de imagem capturado pela câmera/galeria.
  ///
  /// Retorna o [File] comprimido em WebP, ou `null` em caso de falha.
  Future<File?> _comprimirParaWebp(File arquivoOriginal) async {
    // Usa o diretório temporário do sistema operacional (iOS/Android) como destino,
    // pois o arquivo final será enviado ao Supabase e não precisa ser persistido localmente.
    final dir = await path_provider.getTemporaryDirectory();

    // Cria um nome de arquivo único baseado no timestamp para evitar colisões.
    final outPath =
        "${dir.absolute.path}/temp_${DateTime.now().millisecondsSinceEpoch}.webp";

    var resultado = await FlutterImageCompress.compressAndGetFile(
      arquivoOriginal.absolute.path,
      outPath,
      format: CompressFormat.webp,
      quality: 10,
    );

    // A partir do FlutterImageCompress >= 2.0.0, o retorno é do tipo XFile.
    // A conversão para File é necessária para compatibilidade com o restante do código.
    return resultado != null ? File(resultado.path) : null;
  }

  /// Abre o seletor de imagens da galeria, comprime o arquivo selecionado e
  /// dispara a validação em tempo real via IA (Gemini) para a vaga informada.
  ///
  /// O fluxo completo é:
  /// 1. Abre a galeria.
  /// 2. Comprime a imagem para WebP.
  /// 3. Exibe a imagem no card imediatamente (feedback visual ao usuário).
  /// 4. Envia para o Gemini validar se a foto corresponde ao tipo de vaga.
  /// 5. Atualiza o estado do card com sucesso ou mensagem de erro.
  ///
  /// [vaga]: A instância de [_VagaSelecionada] cujo campo de foto será atualizado.
  Future<void> _selecionarFoto(_VagaSelecionada vaga) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        // Ativa o estado de carregamento exclusivo deste card,
        // sem bloquear o restante da interface.
        vaga.validando = true;
        // Limpa qualquer erro de validação anterior para que o usuário
        // possa tentar novamente com uma nova imagem.
        vaga.erroValidacao = null;
      });

      try {
        File arquivoOriginal = File(pickedFile.path);
        File? arquivoWebp = await _comprimirParaWebp(arquivoOriginal);

        if (arquivoWebp != null) {
          // Atualiza a foto na tela imediatamente para feedback visual rápido,
          // antes mesmo do resultado da validação chegar.
          setState(() => vaga.foto = arquivoWebp);

          // Envia a imagem comprimida ao Gemini para verificar se
          // ela realmente representa uma vaga do tipo correto.
          final resultado = await GeminiService.validarVaga(
            arquivoWebp,
            vaga.tipo,
          );

          setState(() {
            if (resultado['status'] == true) {
              // Validação aprovada: limpa qualquer erro residual.
              vaga.erroValidacao = null;
            } else {
              // Validação reprovada: traduz o código de erro para mensagem amigável
              // e remove a foto para forçar o usuário a selecionar uma imagem válida.
              vaga.erroValidacao = _traduzirErroGemini(resultado['message']);
              vaga.foto = null;
            }
          });
        }
      } catch (e) {
        setState(() => vaga.erroValidacao = "Erro ao processar imagem");
      } finally {
        // Garante que o indicador de carregamento do card seja sempre encerrado,
        // mesmo que ocorra uma exceção durante o processo.
        setState(() => vaga.validando = false);
      }
    }
  }

  /// Converte os códigos de erro padronizados retornados pelo Gemini em
  /// mensagens legíveis em português para exibição ao usuário final.
  ///
  /// Os códigos são definidos no prompt enviado ao Gemini via [GeminiService],
  /// garantindo respostas estruturadas e facilmente mapeáveis.
  ///
  /// [message]: O código de erro retornado pelo Gemini (ex: "NOT_A_PARKING_SPOT").
  ///
  /// Retorna uma string com a mensagem de erro traduzida.
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

  /// Orquestra o processo completo de persistência dos dados no Supabase.
  ///
  /// O fluxo de salvamento segue as seguintes etapas em ordem:
  /// 1. **Validações de guarda**: Verifica se há vagas selecionadas, se todas têm foto
  ///    e se não há validações de IA pendentes ou com erro.
  /// 2. **Upsert do Local**: Cria ou atualiza o registro na tabela `locais`.
  /// 3. **Deleção de vagas removidas**: Exclui da tabela `vagas` os registros
  ///    cujos chips foram desmarcados pelo usuário.
  /// 4. **Upsert de cada vaga**: Para cada vaga na lista, decide se deve fazer
  ///    upload de nova foto (removendo a antiga do Storage) e persiste os dados.
  ///    A lógica de auditoria (`id_usuario_ultima_alteracao`) só é acionada
  ///    se houve mudança real (nova foto, quantidade alterada ou vaga nova).
  /// 5. **Registro de contribuição**: Salva ou atualiza a contribuição do usuário.
  /// 6. **Limpeza local**: Remove o registro da fila de pendentes nas SharedPreferences.
  /// 7. **Navegação**: Retorna à tela inicial com mensagem de sucesso.
  Future<void> _salvarTudo() async {
    if (vagasParaRegistro.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Selecione ao menos um tipo de vaga")),
      );
      return;
    }

    // Valida se todas as vagas possuem evidência fotográfica,
    // seja uma foto nova selecionada ou uma URL existente no banco.
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

      // 1. Upsert do local: se [idLocalExistente] for nulo, o Supabase criará
      // um novo registro; caso contrário, atualizará o existente pelo ID.
      // O campo `id_usuario_criador` só é enviado em criações novas para
      // não sobrescrever o criador original em atualizações.
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

      // 2. Executa a deleção em lote de todas as vagas removidas pelo usuário.
      // A lista [idsParaDeletar] é populada quando o chip de uma vaga existente é desmarcado.
      if (idsParaDeletar.isNotEmpty) {
        await supabase.from('vagas').delete().inFilter('id', idsParaDeletar);
      }

      // 3. Itera sobre cada vaga para validar e persistir individualmente.
      for (var vaga in vagasParaRegistro) {
        // Interrompe o salvamento se alguma vaga ainda estiver sendo validada pela IA,
        // garantindo que não serão enviados dados sem aprovação.
        if (vaga.validando) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Aguarde a validação das imagens...")),
          );
          return;
        }
        // Interrompe o salvamento se alguma vaga tiver um erro de validação não resolvido.
        if (vaga.erroValidacao != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Corrija a foto de ${vaga.tipo} antes de salvar."),
            ),
          );
          return;
        }

        // URL que será salva no banco: começa com a URL existente e pode
        // ser sobrescrita caso o usuário tenha selecionado uma nova foto.
        String? urlParaSalvar = vaga.urlFotoExistente;

        // --- Lógica de Detecção de Mudanças (para auditoria) ---
        // Uma foto nova foi selecionada nesta sessão.
        bool fotoMudou = vaga.foto != null;
        // A quantidade foi alterada em relação ao valor original do banco.
        // A verificação `vaga.idVaga != null` garante que só comparamos
        // para vagas já existentes, não para vagas recém-adicionadas.
        bool quantidadeMudou =
            vaga.idVaga != null &&
            (vaga.quantidade != vaga.quantidadeExistente);
        // É uma vaga nova que ainda não existe no banco de dados.
        bool ehNovaVaga = vaga.idVaga == null;

        // Se o usuário selecionou uma nova foto, realiza o processo de
        // substituição: remove o arquivo antigo do Storage e faz upload do novo.
        if (fotoMudou) {
          // Tenta remover a foto antiga do Supabase Storage para evitar acúmulo
          // de arquivos órfãos. O erro é ignorado para não bloquear o fluxo
          // caso o arquivo já tenha sido deletado externamente.
          if (vaga.urlFotoExistente != null) {
            try {
              // Extrai o nome do arquivo da URL pública para usá-lo na deleção.
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

          // Gera um nome único com timestamp para o novo arquivo no Storage.
          final fileName = 'vaga_${DateTime.now().millisecondsSinceEpoch}.webp';
          await supabase.storage
              .from('vagas_images')
              .upload(fileName, vaga.foto!);
          // Obtém a URL pública do arquivo recém-enviado para persistir no banco.
          urlParaSalvar = supabase.storage
              .from('vagas_images')
              .getPublicUrl(fileName);
        }

        // Monta o mapa de dados para o upsert da vaga.
        // O campo `id` só é incluído se a vaga já existe, permitindo ao
        // Supabase decidir entre INSERT e UPDATE corretamente.
        final dadosVaga = {
          if (vaga.idVaga != null) 'id': vaga.idVaga,
          'id_local': localId,
          'tipo_vaga': vaga.tipo,
          'quantidade': vaga.quantidade,
          'foto_url': urlParaSalvar,
        };

        // Os campos de auditoria só são atualizados se houve uma mudança real,
        // preservando a data e o responsável pela última alteração significativa.
        if (fotoMudou || quantidadeMudou || ehNovaVaga) {
          dadosVaga['id_usuario_ultima_alteracao'] = userId;
          dadosVaga['data_ultima_alteracao'] = DateTime.now()
              .toUtc()
              .toIso8601String();
        }

        await supabase.from('vagas').upsert(dadosVaga);
      }

      // 4. Registra ou atualiza a contribuição do usuário para o local.
      // O `onConflict` garante que cada usuário tenha apenas uma contribuição
      // por local, atualizando a data em caso de nova edição.
      await supabase.from('contribuicoes').upsert({
        'id_usuario': userId,
        'id_local': localId,
        'data_contribuicao': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'id_usuario,id_local');

      // 5. Remove o registro da fila de pendentes locais, pois já foi persistido no banco.
      if (dados != null) await _limparRegistroPendente(dados!.id);

      if (mounted) {
        // Navega para a raiz e limpa toda a pilha de navegação,
        // evitando que o usuário volte para uma tela de edição de dados já salvos.
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
      // Garante que o indicador de carregamento seja sempre encerrado.
      setState(() => carregando = false);
    }
  }

  /// Constrói uma linha horizontal de [FilterChip]s para os tipos de vaga fornecidos.
  ///
  /// Cada chip ocupa espaço igual na linha via [Expanded]. Ao selecionar um chip,
  /// adiciona uma nova [_VagaSelecionada] à lista; ao desmarcar, remove a vaga e,
  /// se ela já existia no banco ([idVaga] != null), adiciona seu ID a [idsParaDeletar].
  ///
  /// [tipos]: Lista de strings com os tipos de vaga a exibir nesta linha.
  Widget _criarLinhaDeChips(List<String> tipos) {
    return Row(
      children: tipos.map((tipo) {
        bool selecionado = vagasParaRegistro.any((v) => v.tipo == tipo);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              label: Center(child: Text(tipo)),
              selected: selecionado,
              onSelected: (bool value) {
                setState(() {
                  if (value) {
                    // Adiciona a vaga à lista com valores padrão.
                    vagasParaRegistro.add(_VagaSelecionada(tipo: tipo));
                  } else {
                    // Localiza a vaga a ser removida para verificar se tem ID de banco.
                    final vagaRemovida = vagasParaRegistro.firstWhere(
                      (v) => v.tipo == tipo,
                    );
                    // Se a vaga existe no banco, registra seu ID para deleção
                    // durante o próximo [_salvarTudo].
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
    // Formata o endereço completo para exibição, com fallback caso [dados] seja nulo.
    final enderecoCompleto = dados != null
        ? "${dados!.logradouro}, ${dados!.numero}\n${dados!.bairro}\n${dados!.cidade} - ${dados!.estado}"
        : "Dados não encontrados";

    return Scaffold(
      // Impede que o layout seja redimensionado pelo teclado virtual,
      // evitando overflow em telas menores.
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

                  // Divide os 4 tipos em 2 linhas de 2 chips cada,
                  // garantindo melhor legibilidade em telas pequenas.
                  Column(
                    children: [
                      _criarLinhaDeChips(["Idoso", "PcD"]),
                      const SizedBox(height: 8),
                      _criarLinhaDeChips(["Gestante", "Autista"]),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Renderiza os cards de detalhe em ordem reversa para que
                  // as vagas mais recentemente adicionadas apareçam no topo da lista.
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
                                // Controles de incremento/decremento de quantidade.
                                // O botão de decremento é desabilitado quando a quantidade
                                // já é 1, impedindo valores inválidos (zero ou negativos).
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
                            // O ListTile exibe o estado atual da foto/validação.
                            // O `onTap` é desabilitado durante a validação para
                            // evitar que o usuário inicie uma nova seleção enquanto
                            // a IA ainda está processando.
                            ListTile(
                              leading: vaga.validando
                                  // Durante a validação, exibe um spinner no lugar do ícone.
                                  ? const CircularProgressIndicator(
                                      strokeWidth: 2,
                                    )
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
                      // Desabilita o botão enquanto o salvamento está em andamento,
                      // evitando submissões duplicadas.
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
          // Rodapé fixo com a logo do aplicativo, sempre visível abaixo do conteúdo rolável.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(25),
            alignment: Alignment.centerLeft,
            child: Image.asset(
              'assets/images/titulo.webp',
              width: 150,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
      // Botões de acessibilidade para controle de zoom de fonte,
      // exibidos como FABs sobrepostos no canto inferior direito.
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Botão para diminuir o zoom. Desabilitado e cinza quando já está no nível mínimo (0).
          FloatingActionButton(
            heroTag: "btn_diminuir",
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

          // Botão para aumentar o zoom. Desabilitado e cinza quando já está no nível máximo (2).
          FloatingActionButton(
            heroTag: "btn_aumentar",
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