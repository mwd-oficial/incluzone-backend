import 'dart:io';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static const String _apiKey = "";

  static Future<Map<String, dynamic>> validarVaga(
    File imagem,
    String tipoEsperado,
  ) async {
    try {
      final model = GenerativeModel(model: 'gemini-3-flash-preview', apiKey: _apiKey);

      // Lê a imagem como bytes
      final imageBytes = await imagem.readAsBytes();

      final prompt = [
        Content.multi([
          TextPart('''
Analise a imagem da vaga de estacionamento.
Tipo esperado pelo usuário: $tipoEsperado.

Retorne APENAS um JSON:
{
  "status": boolean,
  "message": "OK" | "NOT_A_PARKING_SPOT" | "WRONG_TYPE" | "NO_SIGNALIZATION" | "POOR_QUALITY" | "OBSTRUCTED"
}

Regras de Decisão:
1. Se a imagem não for de um estacionamento ou rua: "NOT_A_PARKING_SPOT".
2. Se a sinalização (vertical ou horizontal) estiver visível e for diferente de "$tipoEsperado": "WRONG_TYPE".
3. Se houver um veículo ou objeto cobrindo a pintura/placa, impedindo a validação: "OBSTRUCTED".
4. Se a área for claramente uma vaga, mas não houver nenhuma pintura ou placa indicando categoria especial: "NO_SIGNALIZATION".
5. Se a imagem estiver muito escura, borrada ou longe demais: "POOR_QUALITY".
6. "status" será true APENAS se a sinalização confirmar categoricamente o "$tipoEsperado".

Retorne apenas o JSON, sem explicações.
'''),
          DataPart('image/webp', imageBytes),
        ]),
      ];

      final response = await model.generateContent(prompt);

      // Limpa a resposta (remove ```json e espaços)
      String textoLimpo = response.text!
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      return jsonDecode(textoLimpo);
    } catch (e) {
      return {"status": false, "message": "ERRO_CONEXAO"};
    }
  }
}
