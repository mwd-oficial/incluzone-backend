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
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

/// Tela que exibe o histórico de locais com vagas registrados pelo usuário.
///
/// Permite visualizar os locais cadastrados, suas vagas associadas, editar
/// registros existentes e ajustar o nível de zoom/escala da interface.
class HistoricoScreen extends StatefulWidget {
  const HistoricoScreen({super.key});

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

class _HistoricoScreenState extends State<HistoricoScreen> {
  final supabase = Supabase.instance.client;
  bool _carregando = true;
  List<dynamic> _historico = [];
  final String _cacheKey = 'historico_cache';
  int _nivelZoom = 0;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
    _buscarHistorico();
  }

  /// Atualiza o nível de zoom/escala da interface (entre 0 e 2).
  ///
  /// [aumentar] indica se o zoom deve ser incrementado (`true`) ou
  /// decrementado (`false`). O novo valor é persistido localmente via
  /// [SharedPreferences] e propagado para o estado global do app
  /// (definido em `main.dart`) através da [myAppKey], para que a escala
  /// visual seja aplicada em toda a aplicação.
  Future<void> _atualizarZoom(bool aumentar) async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      // Limita o zoom entre os níveis 0 (mínimo) e 2 (máximo)
      if (aumentar && _nivelZoom < 2) {
        _nivelZoom++;
      } else if (!aumentar && _nivelZoom > 0) {
        _nivelZoom--;
      }
    });

    // Persiste o nível de zoom escolhido para que seja restaurado
    // na próxima abertura do app
    await prefs.setInt('nivel_zoom', _nivelZoom);

    // Acessa o estado do MyApp através da chave global e notifica
    // a aplicação inteira para recalcular sua escala visual
    myAppKey.currentState?.atualizarEscala(_nivelZoom);
  }

  /// Carrega o nível de zoom previamente salvo pelo usuário.
  ///
  /// Caso não exista valor salvo, assume o nível padrão (0).
  Future<void> _carregarConfiguracoesIniciais() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    });
  }

  /// Busca o histórico de contribuições (locais com vagas) do usuário logado.
  ///
  /// Estratégia "cache-first": primeiro tenta carregar dados salvos
  /// localmente para exibir algo rapidamente ao usuário, e depois,
  /// se houver conexão com a internet, busca os dados atualizados no
  /// Supabase e atualiza o cache local.
  Future<void> _buscarHistorico() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Tentar carregar do cache primeiro para dar agilidade visual
    final cacheJson = prefs.getString(_cacheKey);
    if (cacheJson != null && _historico.isEmpty) {
      setState(() {
        _historico = jsonDecode(cacheJson);
        _carregando = false;
      });
    }

    // 2. Se tiver internet, busca do banco e atualiza o cache
    if (await _temInternet()) {
      try {
        final user = supabase.auth.currentUser;
        if (user == null) return;

        // Busca as contribuições do usuário, trazendo junto os dados
        // relacionados do local (locais_com_vagas) via join implícito
        final response = await supabase
            .from('contribuicoes')
            .select(
              'id_local, locais_com_vagas (*)',
            ) // Simplificado para o exemplo
            .eq('id_usuario', user.id);

        // Extrai apenas o objeto "locais_com_vagas" de cada item retornado,
        // descartando o wrapper de "contribuicoes"
        final novosDados = response
            .map((item) => item['locais_com_vagas'])
            .toList();

        setState(() {
          _historico = novosDados;
          _carregando = false;
        });

        // Salva no SharedPreferences para a próxima vez
        await prefs.setString(_cacheKey, jsonEncode(novosDados));
      } catch (e) {
        debugPrint("Erro ao buscar histórico: $e");
        setState(() => _carregando = false);
      }
    } else {
      // Caso esteja totalmente offline e não tenha cache,
      // apenas encerra o carregamento (lista permanece vazia)
      setState(() => _carregando = false);
    }
  }

  /// Verifica se o dispositivo possui conexão ativa com a internet.
  ///
  /// Primeiro verifica o status da conectividade (wifi/dados móveis) e,
  /// em seguida, confirma a conectividade real tentando resolver o DNS
  /// de "google.com", evitando falsos positivos (ex: conectado ao wifi
  /// mas sem acesso à internet).
  Future<bool> _temInternet() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) return false;
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
      builder: (context) => AlertDialog(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Histórico"),
        scrolledUnderElevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: _carregando
          // Estado de carregamento: exibe spinner central
          ? const Center(child: CircularProgressIndicator())
          : _historico.isEmpty
          // Estado vazio: exibe ícone e mensagem informando ausência de registros
          ? Center(
              child: Padding(
                padding: const EdgeInsets.only(
                  bottom: 100,
                ), // Ajuste este valor para subir ou descer
                child: Column(
                  mainAxisSize: MainAxisSize
                      .min, // Faz a coluna ocupar apenas o espaço dos filhos
                  children: [
                    Icon(
                      Icons.history_outlined,
                      size: 80,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Nenhum registro encontrado.",
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          // Estado com dados: exibe lista de locais com vagas registradas
          : Column(
              // Adicionado Column para empilhar o texto e a lista
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    "Histórico das suas vagas registradas:",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                Expanded(
                  // Ocupa o restante do espaço da tela
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _historico.length,
                    itemBuilder: (context, index) {
                      final item = _historico[index];

                      // Garante que 'vagas' seja sempre uma lista, mesmo que
                      // o backend retorne null ou outro tipo inesperado
                      final List<dynamic> vagas = item['vagas'] is List
                          ? item['vagas']
                          : [];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ExpansionTile(
                          collapsedShape: const Border(),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          title: Text(
                            "${item['logradouro']}, ${item['numero']}",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            "${item['bairro']} - ${item['cidade']}",
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Referência: ${item['referencia'] != null && item['referencia'].isNotEmpty ? item['referencia'] : 'Não registrada'}",
                                  ),
                                  const Divider(),
                                  // Itera sobre cada vaga associada ao local
                                  ...vagas.map((v) {
                                    // Se a vaga não possuir tipo definido, provavelmente
                                    // veio de um LEFT JOIN sem correspondência,
                                    // então é ignorada (renderiza widget vazio)
                                    if (v['tipo_vaga'] == null)
                                      return const SizedBox();

                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      // Leading: Mostra o ícone do tipo de vaga
                                      leading: SizedBox(
                                        width: 32,
                                        height: 32,
                                        child: _getCustomImage(v['tipo_vaga']),
                                      ),
                                      title: Text(v['tipo_vaga']),
                                      // Trailing: Mostra a foto da vaga vinda do banco e a quantidade
                                      trailing: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 12,
                                        children: [
                                          Text(
                                            "${v['quantidade']} vagas",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          // Widget de imagem da vaga
                                          if (v['foto_url'] != null)
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: Image.network(
                                                v['foto_url'],
                                                width: 45,
                                                height: 45,
                                                fit: BoxFit.cover,
                                                // Tratamento de erro caso o link expire ou falhe
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) => const Icon(
                                                      Icons.broken_image,
                                                      size: 20,
                                                    ),
                                                // Exibe um indicador de progresso enquanto
                                                // a imagem da vaga ainda está carregando
                                                loadingBuilder:
                                                    (
                                                      context,
                                                      child,
                                                      loadingProgress,
                                                    ) {
                                                      if (loadingProgress ==
                                                          null) {
                                                        return child;
                                                      }
                                                      return const SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      );
                                                    },
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  const SizedBox(height: 8),
                                  Center(
                                    child: TextButton.icon(
                                      onPressed: () async {
                                        // Bloqueia a edição caso o dispositivo esteja
                                        // offline, já que a operação depende do Supabase
                                        if (!(await _temInternet())) {
                                          if (mounted) {
                                            _mostrarDialogo(
                                              "Sem Conexão",
                                              "Parece que você está offline. Verifique sua conexão com a internet para editar este registro.",
                                            );
                                          }
                                          return; // Interrompe aqui
                                        }
                                        // Navega para a tela de registro de vagas,
                                        // passando o item atual para edição
                                        await Navigator.pushNamed(
                                          context,
                                          '/registro_vagas',
                                          arguments: item,
                                        );
                                        _buscarHistorico(); // Atualiza a lista ao voltar
                                      },
                                      icon: const Icon(Icons.edit, size: 20),
                                      label: const Text("Editar registro"),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.blue[700],
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  width: double.infinity, // Largura 100%
                  padding: const EdgeInsets.all(10),
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
      // Botões flutuantes de controle de zoom (A- e A+),
      // posicionados lado a lado no canto inferior
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

  /// Retorna o widget de ícone correspondente ao [tipo] de vaga informado.
  ///
  /// Cada tipo de vaga (PcD, Autista, Gestante, Idoso) possui uma imagem
  /// própria localizada em `assets/images/vaga_icons/`. Caso o [tipo]
  /// não seja reconhecido, retorna um ícone genérico de localização.
  /// Caso a imagem falhe ao carregar, exibe um ícone de "imagem quebrada".
  Widget _getCustomImage(String tipo) {
    String path;

    switch (tipo) {
      case 'PcD':
        path = 'assets/images/vaga_icons/pcd.webp';
        break;
      case 'Autista':
        path = 'assets/images/vaga_icons/autista.webp';
        break;
      case 'Gestante':
        path = 'assets/images/vaga_icons/gestante.webp';
        break;
      case 'Idoso':
        path = 'assets/images/vaga_icons/idoso.webp';
        break;
      default:
        // Caso não encontre, retorna um ícone padrão ou imagem genérica
        return const Icon(Icons.location_on, color: Colors.grey);
    }

    return Image.asset(
      path,
      fit: BoxFit.contain,
      // Caso a imagem falhe ao carregar (caminho errado, etc)
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.broken_image),
    );
  }
}