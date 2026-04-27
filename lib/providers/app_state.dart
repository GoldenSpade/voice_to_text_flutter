import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../models/app_theme.dart';

class AppState extends ChangeNotifier {
  static const _keyApiKey = 'openai_api_key';
  static const _keyLang = 'language_code';
  static const _keyTheme = 'theme_index';

  String _apiKey = '';
  String _languageCode = 'en';
  int _themeIndex = 0;

  String get apiKey => _apiKey;
  bool get hasApiKey => _apiKey.isNotEmpty;
  String get languageCode => _languageCode;
  AppLocalizations get l10n => AppLocalizations(_languageCode);
  int get themeIndex => _themeIndex;
  AppButtonTheme get buttonTheme => kAppThemes[_themeIndex];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_keyApiKey) ?? '';
    _languageCode = prefs.getString(_keyLang) ?? 'en';
    _themeIndex = (prefs.getInt(_keyTheme) ?? 0).clamp(0, kAppThemes.length - 1);
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

  Future<void> saveTheme(int index) async {
    _themeIndex = index.clamp(0, kAppThemes.length - 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTheme, _themeIndex);
    notifyListeners();
  }
}
