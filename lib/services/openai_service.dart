import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class OpenAIService {
  final String apiKey;

  const OpenAIService(this.apiKey);

  Future<String> transcribeAudio(String filePath) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.openai.com/v1/audio/transcriptions'),
    )
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = 'gpt-4o-transcribe'
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode == 200) {
      return (jsonDecode(body) as Map<String, dynamic>)['text'] as String;
    }

    final errorBody = jsonDecode(body) as Map<String, dynamic>;
    final message = (errorBody['error'] as Map<String, dynamic>?)?['message'];
    throw Exception(message ?? 'HTTP ${streamed.statusCode}');
  }

  Future<String> translateText(String text, String targetLanguageCode) async {
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini',
        'temperature': 0.3,
        'messages': [
          {
            'role': 'system',
            'content':
                'Translate the following text to the language with ISO code "$targetLanguageCode". '
                    'Return only the translated text, no explanations.',
          },
          {'role': 'user', 'content': text},
        ],
      }),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return (json['choices'] as List)[0]['message']['content'] as String;
    }

    final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
    final message = (errorBody['error'] as Map<String, dynamic>?)?['message'];
    throw Exception(message ?? 'HTTP ${response.statusCode}');
  }

  Future<File> textToSpeech(
      String text, String voice, String outputPath) async {
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/audio/speech'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'tts-1',
        'input': text,
        'voice': voice,
      }),
    );

    if (response.statusCode == 200) {
      final file = File(outputPath);
      await file.writeAsBytes(response.bodyBytes);
      return file;
    }

    final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
    final message = (errorBody['error'] as Map<String, dynamic>?)?['message'];
    throw Exception(message ?? 'HTTP ${response.statusCode}');
  }
}
