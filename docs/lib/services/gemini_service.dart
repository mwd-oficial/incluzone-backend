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
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Serviço responsável por integrar a aplicação com o modelo de IA Gemini,
/// utilizando uma Edge Function do Supabase como intermediária segura.
///
/// A comunicação com a API do Gemini não ocorre diretamente no cliente Flutter,
/// mas sim por meio de uma função serverless hospedada no Supabase. Isso evita
/// que a API Key fique exposta no código do aplicativo (bundle do cliente),
/// mitigando riscos de segurança como extração da chave via engenharia reversa.
class GeminiService {
  /// Envia uma imagem para validação por IA, verificando se ela corresponde
  /// ao tipo de vaga esperado (ex.: "moto", "carro", "caminhão").
  ///
  /// O fluxo completo é:
  /// 1. A imagem é lida do sistema de arquivos e codificada em Base64.
  /// 2. O payload é enviado para a Edge Function `validar-vaga` no Supabase.
  /// 3. A Edge Function, com acesso seguro à API Key do Gemini, processa
  ///    a imagem e devolve um JSON com o resultado da validação.
  ///
  /// Retorna um [Map<String, dynamic>] com a estrutura de resposta da IA.
  /// Em caso de sucesso, espera-se um campo `status` (bool) indicando se a
  /// vaga é válida, e um campo `message` com detalhes. Em caso de falha,
  /// o map retornado sempre conterá `"status": false` e um código de erro
  /// em `"message"` para que a camada de UI possa tratar adequadamente.
  ///
  /// Parâmetros:
  /// - [imagem]: O arquivo de imagem capturado (ex.: foto tirada pela câmera).
  /// - [tipoEsperado]: String que descreve o tipo de veículo/vaga que a IA
  ///   deve identificar na imagem para aprovar a validação.
  static Future<Map<String, dynamic>> validarVaga(
    File imagem,
    String tipoEsperado,
  ) async {
    try {
      // Lê todos os bytes do arquivo de imagem de forma assíncrona.
      // `readAsBytes()` é preferível a `readAsString()` para arquivos binários,
      // pois preserva os dados brutos sem nenhuma conversão de encoding de texto.
      final imageBytes = await imagem.readAsBytes();

      // Converte os bytes brutos da imagem para uma String Base64.
      // Este formato é necessário porque o corpo da requisição HTTP para a
      // Edge Function é um JSON (texto puro), que não suporta dados binários diretamente.
      final imagemBase64 = base64Encode(imageBytes);

      // Invoca a Edge Function denominada 'validar-vaga' hospedada no Supabase.
      // O cliente do Supabase já está inicializado globalmente na aplicação,
      // portanto `Supabase.instance.client` é acessado como singleton.
      // O `body` é serializado automaticamente como JSON pelo SDK do Supabase.
      final response = await Supabase.instance.client.functions.invoke(
        'validar-vaga',
        body: {
          'imagemBase64': imagemBase64,
          'tipoEsperado': tipoEsperado,
        },
      );

      // O SDK do Supabase pode retornar o `response.data` já desserializado
      // como um Map (quando o Content-Type da resposta é application/json),
      // ou como uma String bruta (em outros casos). A verificação abaixo
      // garante que o retorno deste método seja sempre um Map tipado,
      // independentemente do formato que a Edge Function retornar.
      if (response.data is Map) {
        // Caso mais comum: o Supabase já desserializou o JSON da resposta.
        // `Map<String, dynamic>.from()` cria uma cópia fortemente tipada
        // a partir do Map genérico retornado pelo SDK.
        return Map<String, dynamic>.from(response.data);
      } else {
        // Caminho alternativo: a resposta veio como String (ex.: Content-Type
        // diferente de application/json). Força a desserialização manual do JSON.
        return jsonDecode(response.data.toString());
      }
    } on FunctionException catch (fe) {
      // Captura erros específicos lançados pelo SDK do Supabase quando a
      // Edge Function retorna um status HTTP de erro (4xx ou 5xx), ou quando
      // há uma falha lógica interna na própria função serverless.
      // O `detalhe` inclui o objeto de exceção completo para facilitar o debug,
      // mas em produção considere logar `fe.details` em vez de expô-lo ao cliente.
      return {"status": false, "message": "ERRO_FUNCAO", "detalhe": fe};
    } catch (e) {
      // Captura qualquer outra exceção não prevista, como falhas de conectividade
      // (ex.: ausência de internet), timeout de rede, ou erros de parsing de JSON.
      // Retorna um código de erro genérico para que a UI exiba uma mensagem
      // amigável sem expor detalhes técnicos internos ao usuário final.
      return {"status": false, "message": "ERRO_CONEXAO"};
    }
  }
}