import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/history_item.dart';

class HistoryService extends ChangeNotifier {
  static const _maxItems = 200;

  final List<HistoryItem> _items = [];
  List<HistoryItem> get items => List.unmodifiable(_items);

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/history.json');
  }

  Future<void> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return;
      final raw = jsonDecode(file.readAsStringSync()) as List;
      _items
        ..clear()
        ..addAll(
          raw.map((e) => HistoryItem.fromJson(e as Map<String, dynamic>)),
        );
      _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> add(HistoryItem item) async {
    _items.insert(0, item);
    if (_items.length > _maxItems) _items.removeLast();
    notifyListeners();
    await _persist();
  }

  Future<void> delete(String id) async {
    _items.removeWhere((e) => e.id == id);
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    _items.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode(_items.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }
}
