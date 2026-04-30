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

  Future<String> translateText(String text, String targetLanguage) async {
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
                'Translate the following text to $targetLanguage. '
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

  Future<String> correctText(String text) async {
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini',
        'temperature': 0.1,
        'messages': [
          {
            'role': 'system',
            'content':
                'Fix punctuation, capitalization and grammar in the following text. '
                'Preserve the original language and meaning exactly. '
                'Return only the corrected text, no explanations.',
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

  Future<String> transformText(String text, String instruction) async {
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini',
        'temperature': 0.7,
        'messages': [
          {
            'role': 'system',
            'content':
                'You are a helpful text transformation assistant. '
                'Transform the given text according to the user\'s instruction. '
                'Return only the transformed text, no explanations.',
          },
          {
            'role': 'user',
            'content': 'Text:\n$text\n\nInstruction: $instruction',
          },
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
