import 'dart:io';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class GeminiService {
  // A API Key sumiu daqui! A segurança agradece.

  static Future<Map<String, dynamic>> validarVaga(
    File imagem,
    String tipoEsperado,
  ) async {
    try {
      // 1. Lê a imagem e converte para String Base64
      final imageBytes = await imagem.readAsBytes();
      final imagemBase64 = base64Encode(imageBytes);

      // 2. Invoca a Edge Function do Supabase
      final response = await Supabase.instance.client.functions.invoke(
        'validar-vaga',
        body: {
          'imagemBase64': imagemBase64,
          'tipoEsperado': tipoEsperado,
        },
      );

      // 3. A resposta já vem como um Map pronto se for um JSON válido
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      } else {
        // Caso venha como String, decodifica
        return jsonDecode(response.data.toString());
      }
    } on FunctionException catch (fe) {
      // Erros vindos especificamente da Edge Function
      return {"status": false, "message": "ERRO_FUNCAO", "detalhe": fe};
    } catch (e) {
      // Erros genéricos de rede/conexão
      return {"status": false, "message": "ERRO_CONEXAO"};
    }
  }
}