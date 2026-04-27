import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';

class AppState extends ChangeNotifier {
  static const _keyApiKey = 'openai_api_key';
  static const _keyLang = 'language_code';

  String _apiKey = '';
  String _languageCode = 'en';

  String get apiKey => _apiKey;
  bool get hasApiKey => _apiKey.isNotEmpty;
  String get languageCode => _languageCode;
  AppLocalizations get l10n => AppLocalizations(_languageCode);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_keyApiKey) ?? '';
    _languageCode = prefs.getString(_keyLang) ?? 'en';
    notifyListeners();
  }

  Future<void> saveApiKey(String key) async {
    _apiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, _apiKey);
    notifyListeners();
  }

  Future<void> saveLanguage(String code) async {
    _languageCode = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLang, code);
    notifyListeners();
  }
}
