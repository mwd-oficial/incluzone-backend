import 'package:flutter/material.dart';
import 'dart:ui';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // Definimos a imagem como variável para facilitar o evict
  final AssetImage splashImage = const AssetImage(
    'assets/images/splash_animation.webp',
  );

  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    _runSplashScreenTimeline();
  }

  Future<void> _runSplashScreenTimeline() async {
    // 1. Força o Flutter a recarregar a imagem do zero
    await splashImage.evict();

    // 2. Aguarda 1 segundo (tela em branco)
    await Future.delayed(const Duration(seconds: 1));

    // 3. Fade In
    if (mounted) {
      setState(() {
        _opacity = 1.0;
      });
    }

    // 4. Tempo visível
    await Future.delayed(const Duration(seconds: 3));

    // 5. Fade Out
    if (mounted) {
      setState(() {
        _opacity = 0.0;
      });
    }

    // 6. Aguarda término do Fade Out
    await Future.delayed(const Duration(seconds: 1));

    // 7. Navega
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: AnimatedOpacity(
          opacity: _opacity,
          duration: const Duration(seconds: 1),
          curve: Curves.easeInOut,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- EFEITO DROP SHADOW AQUI ---
              Stack(
                alignment: Alignment.center,
                children: [
                  // Camada da Sombra: Deslocada e com Blur Preto
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
                    child: Image(
                      image: splashImage,
                      width: 200,
                      color: Colors.black.withOpacity(0.5), // Cor da sombra
                      colorBlendMode:
                          BlendMode.srcIn, // Pinta a imagem de preto
                      fit: BoxFit.contain,
                    ),
                  ),
                  // Camada da Imagem Real
                  Image(
                    image: splashImage,
                    key: UniqueKey(),
                    width: 200,
                    fit: BoxFit.contain,
                  ),
                ],
              ),

              // -------------------------------
              const SizedBox(height: 24),

              // Imagem com o nome do App
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
