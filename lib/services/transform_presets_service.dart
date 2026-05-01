import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TransformPresetsService extends ChangeNotifier {
  static const _key = 'transform_presets';

  List<String> _presets = [];
  List<String> get presets => List.unmodifiable(_presets);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _presets = prefs.getStringList(_key) ?? [];
  }

  Future<void> add(String text) async {
    final t = text.trim();
    if (t.isEmpty || _presets.contains(t)) return;
    _presets = [t, ..._presets];
    await _persist();
    notifyListeners();
  }

  Future<void> delete(String text) async {
    _presets = _presets.where((p) => p != text).toList();
    await _persist();
    notifyListeners();
  }

  bool contains(String text) => _presets.contains(text.trim());

  Future<void> restorePresets(List<String> incoming) async {
    bool changed = false;
    for (final p in incoming) {
      final t = p.trim();
      if (t.isNotEmpty && !_presets.contains(t)) {
        _presets.add(t);
        changed = true;
      }
    }
    if (changed) {
      await _persist();
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _presets);
  }
}
