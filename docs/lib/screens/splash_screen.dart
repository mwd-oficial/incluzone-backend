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
import 'dart:ui';

/// Tela de splash animada exibida na inicialização do aplicativo.
///
/// Exibe uma animação de fade in/out sobre uma imagem de splash,
/// com efeito de sombra projetada (drop shadow) construído manualmente
/// via [ImageFiltered] e [Stack]. Ao término da animação, navega
/// automaticamente para a rota inicial do app.
///
/// É um [StatefulWidget] pois precisa gerenciar o estado da opacidade
/// ao longo do tempo, coordenando as etapas da linha do tempo via [Future.delayed].
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// Referência tipada para o asset de imagem do splash.
  ///
  /// Armazenar como campo da classe (em vez de instanciar diretamente no
  /// [build]) é essencial para que o método [evict] possa ser chamado
  /// sobre a mesma instância de [ImageProvider] que será usada na UI,
  /// garantindo que o cache seja limpo para *exatamente* este asset.
  final AssetImage splashImage = const AssetImage(
    'assets/images/splash_animation.webp',
  );

  /// Controla a visibilidade da coluna de conteúdo via [AnimatedOpacity].
  ///
  /// Começa em `0.0` (totalmente transparente) para que a tela inicie
  /// em branco. A linha do tempo da splash alterna este valor entre
  /// `0.0` e `1.0` para produzir os efeitos de fade in e fade out.
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    // Dispara a linha do tempo assim que o widget é inserido na árvore.
    // Não aguardamos o Future aqui intencionalmente: o initState não pode
    // ser assíncrono, e os efeitos colaterais são tratados internamente
    // pela própria _runSplashScreenTimeline com verificações de `mounted`.
    _runSplashScreenTimeline();
  }

  /// Orquestra todas as etapas visuais e de navegação da tela de splash.
  ///
  /// A sequência é inteiramente linear e baseada em tempo, sem dependência
  /// de gestos do usuário. Cada etapa é comentada abaixo com seu propósito.
  ///
  /// A verificação `if (mounted)` antes de cada [setState] e antes da
  /// navegação é uma salvaguarda obrigatória: se o widget for removido da
  /// árvore enquanto um [Future.delayed] ainda está em andamento (ex.: o
  /// usuário navega manualmente), chamadas a [setState] ou ao [Navigator]
  /// em um widget desmontado causariam exceções em tempo de execução.
  Future<void> _runSplashScreenTimeline() async {
    // 1. Limpa o cache de imagem antes de exibir.
    //    O Flutter mantém um cache interno de imagens decodificadas. Sem o
    //    evict(), em hot reloads ou reinicializações rápidas do app, o
    //    Flutter poderia exibir um frame da imagem já decodificada antes
    //    que a animação WebP tivesse a chance de começar do quadro inicial,
    //    causando um "flash" ou animação cortada.
    await splashImage.evict();

    // 2. Pausa inicial com a tela em branco.
    //    Proporciona um momento de "respiro" antes do conteúdo aparecer,
    //    evitando que a imagem surja abruptamente logo após o launch screen
    //    nativo do SO.
    await Future.delayed(const Duration(seconds: 1));

    // 3. Inicia o Fade In alterando a opacidade para totalmente visível.
    //    O [AnimatedOpacity] no build() interpola suavemente de 0.0 para
    //    1.0 na duração configurada (1 segundo), produzindo o efeito de
    //    fade in sem necessidade de um AnimationController explícito.
    if (mounted) {
      setState(() {
        _opacity = 1.0;
      });
    }

    // 4. Mantém o conteúdo visível pelo tempo configurado.
    //    Este delay deve ser maior que a duração da animação WebP para
    //    que o usuário possa ver o ciclo completo da animação.
    await Future.delayed(const Duration(seconds: 3));

    // 5. Inicia o Fade Out revertendo a opacidade para zero.
    //    Assim como no Fade In, o [AnimatedOpacity] faz a transição
    //    suavemente. A navegação só acontece após este efeito concluir.
    if (mounted) {
      setState(() {
        _opacity = 0.0;
      });
    }

    // 6. Aguarda o término da animação de Fade Out antes de navegar.
    //    Este delay deve ser igual à duração do [AnimatedOpacity] (1 segundo)
    //    para garantir que a tela já esteja completamente transparente no
    //    momento da troca de rota, evitando um corte visual abrupto.
    await Future.delayed(const Duration(seconds: 1));

    // 7. Substitui a rota atual pela rota raiz do app.
    //    [pushReplacementNamed] remove a SplashScreen da pilha de navegação,
    //    impedindo que o usuário retorne a ela ao pressionar o botão "voltar".
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Fundo branco explícito para que a tela em branco durante o delay
      // inicial e durante os fades seja consistente com o launch screen nativo,
      // criando uma transição imperceptível entre os dois.
      backgroundColor: Colors.white,
      body: Center(
        child: AnimatedOpacity(
          // Valor atual da opacidade, controlado pela linha do tempo assíncrona.
          opacity: _opacity,
          // Duração da interpolação de opacidade. Deve ser igual ao delay da
          // etapa 6 para que fade e navegação estejam sincronizados.
          duration: const Duration(seconds: 1),
          // Curva que suaviza a aceleração/desaceleração do fade,
          // evitando transições lineares que parecem mecânicas.
          curve: Curves.easeInOut,
          child: Column(
            // MinSize evita que a Column ocupe toda a altura disponível,
            // mantendo o conjunto de widgets centralizado verticalmente
            // apenas pelo espaço que seus filhos de fato ocupam.
            mainAxisSize: MainAxisSize.min,
            children: [
              /// Grupo responsável pelo efeito de sombra projetada (drop shadow)
              /// sobre a imagem de splash.
              ///
              /// O Flutter não oferece drop shadow nativo para widgets [Image]
              /// (apenas box shadow para contêineres), portanto o efeito é
              /// construído manualmente com duas camadas sobrepostas em um [Stack]:
              /// a camada inferior é uma cópia desfocada e colorida da mesma imagem,
              /// simulando a sombra; a camada superior é a imagem original.
              Stack(
                alignment: Alignment.center,
                children: [
                  /// Camada de sombra: uma cópia da imagem pintada de preto
                  /// semitransparente e desfocada via [ImageFiltered].
                  ///
                  /// A combinação de [BlendMode.srcIn] com [Colors.black.withOpacity]
                  /// substitui todos os pixels não-transparentes da imagem pela cor
                  /// preta com a opacidade definida, criando uma silhueta escura que,
                  /// após o blur, simula a sombra projetada abaixo da imagem real.
                  ImageFiltered(
                    // sigmaX e sigmaY controlam o raio do desfoque gaussiano
                    // em cada eixo. Valores maiores = sombra mais difusa/suave.
                    imageFilter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
                    child: Image(
                      image: splashImage,
                      width: 200,
                      // Define a cor que será aplicada sobre a imagem.
                      // A opacidade de 0.5 torna a sombra semitransparente,
                      // integrando-a visualmente ao fundo branco.
                      color: Colors.black.withOpacity(0.5),
                      // srcIn usa a silhueta (canal alpha) da imagem original
                      // como máscara e preenche os pixels visíveis com a `color`
                      // definida acima, resultando em uma silhueta preta da imagem.
                      colorBlendMode: BlendMode.srcIn,
                      fit: BoxFit.contain,
                    ),
                  ),

                  /// Camada da imagem real, renderizada sobre a sombra.
                  ///
                  /// [UniqueKey] força o Flutter a tratar este widget como uma
                  /// instância sempre nova a cada rebuild, o que reinicia a
                  /// animação WebP do quadro zero — comportamento desejado após
                  /// o [evict()] da etapa 1 da linha do tempo.
                  Image(
                    image: splashImage,
                    key: UniqueKey(),
                    width: 200,
                    fit: BoxFit.contain,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              /// Imagem estática com o logotipo/nome do aplicativo,
              /// exibida abaixo da animação de splash.
              /// Utiliza [Image.asset] pois não requer o controle de cache
              /// que [AssetImage] com [evict] proporciona acima.
              Image.asset(
                'assets/images/titulo.webp',
                width: 200,
                fit: BoxFit.contain,
              ),
            ],
          ),
        ),
      ),
    );
  }
}