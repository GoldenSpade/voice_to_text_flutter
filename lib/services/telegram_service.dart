import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_item.dart';

class TelegramService extends ChangeNotifier {
  static const _tokenKey = 'telegram_token';
  static const _chatIdKey = 'telegram_chat_id';

  String _token = '';
  String _chatId = '';

  String get token => _token;
  String get chatId => _chatId;
  bool get isConfigured => _token.isNotEmpty && _chatId.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey) ?? '';
    _chatId = prefs.getString(_chatIdKey) ?? '';
  }

  Future<void> setToken(String value) async {
    _token = value.trim();
    final prefs = await SharedPreferences.getInstance();
    if (_token.isEmpty) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, _token);
    }
    notifyListeners();
  }

  Future<void> setChatId(String value) async {
    _chatId = value.trim();
    final prefs = await SharedPreferences.getInstance();
    if (_chatId.isEmpty) {
      await prefs.remove(_chatIdKey);
    } else {
      await prefs.setString(_chatIdKey, _chatId);
    }
    notifyListeners();
  }

  Future<void> clear() async {
    _token = '';
    _chatId = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_chatIdKey);
    notifyListeners();
  }

  void sendResult({
    required HistoryType type,
    required String result,
    String? original,
    String? languageName,
    String? voiceName,
  }) {
    if (!isConfigured) return;
    _post(_format(type, result, original, languageName, voiceName));
  }

  Future<bool> sendTest() async {
    if (!isConfigured) return false;
    return _post('✅ Voice Translator AI\nBot is connected!');
  }

  Future<String?> fetchChatId() async {
    if (_token.isEmpty) return null;
    try {
      final uri = Uri.parse(
          'https://api.telegram.org/bot$_token/getUpdates?limit=10&offset=-10');
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) return null;
      final results = data['result'] as List;
      for (final update in results.reversed) {
        final chat = update['message']?['chat'] ??
            update['channel_post']?['chat'] ??
            update['my_chat_member']?['chat'];
        if (chat != null) return chat['id'].toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _post(String text) async {
    try {
      final uri =
          Uri.parse('https://api.telegram.org/bot$_token/sendMessage');
      final resp = await http.post(uri, body: {
        'chat_id': _chatId,
        'text': text,
      }).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String _format(HistoryType type, String result, String? original,
      String? languageName, String? voiceName) {
    final buf = StringBuffer();
    switch (type) {
      case HistoryType.transcription:
        buf.write('🎤 Transcription\n\n$result');
      case HistoryType.translation:
        buf.write('🌐 Translation');
        if (languageName != null) buf.write(' → $languageName');
        if (original != null) buf.write('\n\nOriginal:\n$original');
        buf.write('\n\nTranslation:\n$result');
      case HistoryType.transcriptionTranslation:
        buf.write('🎙 Transcription + Translation');
        if (languageName != null) buf.write(' → $languageName');
        if (original != null) buf.write('\n\nTranscription:\n$original');
        buf.write('\n\nTranslation:\n$result');
      case HistoryType.fullCycle:
        buf.write('🔄 Full Cycle');
        if (languageName != null) buf.write(' → $languageName');
        if (original != null) buf.write('\n\nOriginal:\n$original');
        buf.write('\n\nTranslation:\n$result');
        if (voiceName != null) buf.write('\n\n🔊 Voice: $voiceName');
      case HistoryType.tts:
        buf.write('📢 Text to Voice');
        if (voiceName != null) buf.write(' ($voiceName)');
        buf.write('\n\n$result');
      case HistoryType.transform:
        buf.write('✨ Text Transform');
        if (original != null) buf.write('\n\nOriginal:\n$original');
        buf.write('\n\nResult:\n$result');
    }
    return buf.toString();
  }
}
