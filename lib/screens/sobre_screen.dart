import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'package:url_launcher/url_launcher.dart';

class SobreScreen extends StatefulWidget {
  const SobreScreen({super.key});

  @override
  State<SobreScreen> createState() => _SobreScreenState();
}

class _SobreScreenState extends State<SobreScreen> {
  int _nivelZoom = 0;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
  }

  Future<void> _enviarEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'incluzoneapp+suporte@gmail.com',
    );

    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    } else {
      // Caso ocorra um erro ou não haja app de email instalado
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o app de e-mail'),
          ),
        );
      }
    }
  }

  Future<void> _carregarConfiguracoesIniciais() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nivelZoom = prefs.getInt('nivel_zoom') ?? 0;
    });
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

    await prefs.setInt('nivel_zoom', _nivelZoom);
    myAppKey.currentState?.atualizarEscala(_nivelZoom);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sobre o IncluZone")),
      body: SizedBox.expand(
        // <-- ISSO FAZ O STACK OCUPAR A TELA TODA
        child: Stack(
          children: [
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
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: const Text("Suporte via E-mail"),
                    subtitle: const Text(
                      "incluzoneapp+suporte@gmail.com",
                      style: TextStyle(
                        color: Colors.blue, // Define a cor azul
                        decoration:
                            TextDecoration.underline, // Adiciona o sublinhado
                      ),
                    ),
                    onTap: _enviarEmail,
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 25,
              left: 25,
              child: Image.asset('assets/images/titulo.webp', width: 150),
            ),
          ],
        ),
      ),
      // Botões de acessibilidade mantidos identicos
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "btn_diminuir_sobre",
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
          FloatingActionButton(
            heroTag: "btn_aumentar_sobre",
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
