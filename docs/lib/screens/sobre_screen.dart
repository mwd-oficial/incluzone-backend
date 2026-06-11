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
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'package:url_launcher/url_launcher.dart';

/// Tela "Sobre o IncluZone", responsável por exibir informações institucionais
/// do aplicativo, como versão, equipe de desenvolvimento e canal de suporte.
///
/// Além das informações estáticas, esta tela também gerencia o nível de zoom
/// de acessibilidade do aplicativo, permitindo ao usuário aumentar ou diminuir
/// o tamanho global dos elementos de interface.
class SobreScreen extends StatefulWidget {
  const SobreScreen({super.key});

  @override
  State<SobreScreen> createState() => _SobreScreenState();
}

/// Estado associado ao [SobreScreen].
///
/// Mantém e persiste o nível de zoom de acessibilidade selecionado pelo usuário,
/// além de coordenar a abertura do cliente de e-mail nativo do dispositivo.
class _SobreScreenState extends State<SobreScreen> {
  /// Nível atual de zoom de acessibilidade.
  ///
  /// Os valores possíveis são:
  /// - `0`: Tamanho padrão (mínimo permitido).
  /// - `1`: Tamanho médio.
  /// - `2`: Tamanho máximo permitido.
  int _nivelZoom = 0;

  @override
  void initState() {
    super.initState();
    // Carrega o nível de zoom salvo anteriormente assim que o estado é
    // inicializado, garantindo que a interface reflita a preferência persistida.
    _carregarConfiguracoesIniciais();
  }

  /// Abre o aplicativo de e-mail padrão do dispositivo com o endereço de
  /// suporte do IncluZone pré-preenchido no campo de destinatário.
  ///
  /// Utiliza o esquema `mailto:` para acionar o app de e-mail nativo via
  /// [url_launcher]. Caso o dispositivo não possua um cliente de e-mail
  /// configurado ou ocorra qualquer falha ao tentar abrir a URL, exibe um
  /// [SnackBar] informando o usuário sobre o problema.
  Future<void> _enviarEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'incluzoneapp+suporte@gmail.com',
    );

    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    } else {
      // Verifica se o widget ainda está montado antes de interagir com o
      // contexto, evitando erros ao tentar exibir o SnackBar após a
      // desconstrução da tela (e.g., usuário navegou para outra tela).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o app de e-mail'),
          ),
        );
      }
    }
  }

  /// Recupera o nível de zoom previamente salvo pelo usuário via [SharedPreferences]
  /// e atualiza o estado local da tela.
  ///
  /// Utiliza o valor padrão `0` caso nenhuma preferência tenha sido salva ainda
  /// (primeira execução do app ou dados apagados). Isso garante que a tela
  /// sempre inicie em um estado consistente.
  Future<void> _carregarConfiguracoesIniciais() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    });
  }

  /// Incrementa ou decrementa o nível de zoom de acessibilidade e persiste
  /// a nova preferência do usuário.
  ///
  /// O nível de zoom é controlado pelo parâmetro [aumentar]:
  /// - Se `true`, aumenta o zoom em um nível, respeitando o máximo de `2`.
  /// - Se `false`, diminui o zoom em um nível, respeitando o mínimo de `0`.
  ///
  /// Após a atualização local do estado, o novo nível é:
  /// 1. Salvo em [SharedPreferences] para persistir entre sessões do app.
  /// 2. Propagado globalmente para o widget raiz via [myAppKey], que aplica
  ///    a escala em toda a árvore de widgets do aplicativo.
  ///
  /// [aumentar] - `true` para aumentar o zoom, `false` para diminuir.
  Future<void> _atualizarZoom(bool aumentar) async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      // Incrementa apenas se ainda não atingiu o nível máximo (2).
      if (aumentar && _nivelZoom < 2) {
        _nivelZoom++;
      // Decrementa apenas se ainda não atingiu o nível mínimo (0).
      } else if (!aumentar && _nivelZoom > 0) {
        _nivelZoom--;
      }
    });

    // Persiste o novo nível de zoom para que a preferência sobreviva ao
    // encerramento e reabertura do aplicativo.
    await prefs.setInt('nivel_zoom', _nivelZoom);

    // Notifica o estado global do app (via GlobalKey em main.dart) para
    // recalcular e aplicar o fator de escala na interface inteira.
    myAppKey.currentState?.atualizarEscala(_nivelZoom);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sobre o IncluZone")),
      body: SizedBox.expand(
        // SizedBox.expand força o widget filho a ocupar todo o espaço
        // disponível do body, o que é necessário para que o Stack interno
        // possa posicionar elementos de forma absoluta em relação à tela
        // (como o logotipo fixado no canto inferior esquerdo).
        child: Stack(
          children: [
            // Camada principal com o conteúdo rolável da tela.
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    "Este aplicativo foi desenvolvido para oferecer uma experiência acessível e segura.",
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Aqui você pode encontrar informações sobre nossa missão e os termos de uso.",
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const ListTile(
                    leading: Icon(Icons.code),
                    title: Text("Desenvolvido por"),
                    subtitle: Text("Equipe IncluZone"),
                  ),
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text("Versão"),
                    subtitle: Text("1.0.0"),
                  ),
                  const Divider(),
                  // Item de contato clicável: ao ser pressionado, aciona
                  // [_enviarEmail] para abrir o cliente de e-mail nativo com
                  // o endereço de suporte pré-preenchido.
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: const Text("Suporte via E-mail"),
                    subtitle: const Text(
                      "incluzoneapp+suporte@gmail.com",
                      style: TextStyle(
                        // A formatação visual (azul + sublinhado) reforça a
                        // affordance de que este texto é um link clicável,
                        // alinhando a aparência ao comportamento do onTap.
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    onTap: _enviarEmail,
                  ),
                ],
              ),
            ),
            // Camada sobreposta: exibe o logotipo do app fixado no canto
            // inferior esquerdo, independentemente da rolagem do conteúdo acima.
            Positioned(
              bottom: 25,
              left: 25,
              child: Image.asset('assets/images/titulo.webp', width: 150),
            ),
          ],
        ),
      ),
      // Botões de acessibilidade para controle de zoom, posicionados como
      // FABs para garantir acesso fácil e persistente, sem interferir no
      // conteúdo rolável principal.
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "btn_diminuir_sobre",
            // O botão de diminuir é desabilitado (onPressed: null) quando o
            // zoom já está no nível mínimo (0), sinalizando visualmente ao
            // usuário que não é possível reduzir mais.
            onPressed: _nivelZoom > 0 ? () => _atualizarZoom(false) : null,
            // A cor de fundo muda para cinza quando desabilitado, reforçando
            // o feedback visual de estado inativo.
            backgroundColor: _nivelZoom > 0 ? null : Colors.grey.shade300,
            shape: const CircleBorder(),
            child: Text(
              "A-",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                // A cor do ícone também escurece para cinza quando inativo,
                // garantindo contraste adequado sobre o fundo cinza claro.
                color: _nivelZoom > 0 ? null : Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: "btn_aumentar_sobre",
            // O botão de aumentar é desabilitado (onPressed: null) quando o
            // zoom já está no nível máximo (2), impedindo incrementos além
            // do limite definido pela regra de negócio.
            onPressed: _nivelZoom < 2 ? () => _atualizarZoom(true) : null,
            // Mesma lógica de feedback visual aplicada ao botão de diminuir:
            // fundo cinza quando no limite máximo de zoom.
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