import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class OpenAIService {
  final String apiKey;

  const OpenAIService(this.apiKey);

  Future<T> _call<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on SocketException {
      throw Exception('no_internet');
    } on http.ClientException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('socketfailed') ||
          msg.contains('failed host lookup') ||
          msg.contains('no address associated') ||
          msg.contains('connection refused') ||
          msg.contains('network is unreachable')) {
        throw Exception('no_internet');
      }
      rethrow;
    }
  }

  static String _parseError(String body, int statusCode) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      return (map['error'] as Map<String, dynamic>?)?['message'] as String? ??
          'HTTP $statusCode';
    } catch (_) {
      return 'HTTP $statusCode';
    }
  }

  Future<String> transcribeAudio(String filePath, {String? language}) =>
      _call(() async {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('https://api.openai.com/v1/audio/transcriptions'),
        )
          ..headers['Authorization'] = 'Bearer $apiKey'
          ..fields['model'] = 'gpt-4o-transcribe'
          ..files.add(await http.MultipartFile.fromPath('file', filePath));

        if (language != null && language.isNotEmpty) {
          request.fields['language'] = language;
        }

        final streamed = await request.send();
        final body = await streamed.stream.bytesToString();

        if (streamed.statusCode == 200) {
          return (jsonDecode(body) as Map<String, dynamic>)['text'] as String;
        }
        throw Exception(_parseError(body, streamed.statusCode));
      });

  Future<String> translateText(String text, String targetLanguage) =>
      _call(() async {
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
        throw Exception(_parseError(response.body, response.statusCode));
      });

  Future<String> correctText(String text) => _call(() async {
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
        throw Exception(_parseError(response.body, response.statusCode));
      });

  Future<String> transformText(String text, String instruction) =>
      _call(() async {
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
        throw Exception(_parseError(response.body, response.statusCode));
      });

  Future<File> textToSpeech(
          String text, String voice, String outputPath) =>
      _call(() async {
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
        throw Exception(_parseError(response.body, response.statusCode));
      });
}
