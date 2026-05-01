import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/history_folder.dart';

class FolderService extends ChangeNotifier {
  final List<HistoryFolder> _folders = [];
  List<HistoryFolder> get folders => List.unmodifiable(_folders);

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/folders.json');
  }

  Future<void> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return;
      final raw = jsonDecode(file.readAsStringSync()) as List;
      _folders
        ..clear()
        ..addAll(
          raw.map((e) => HistoryFolder.fromJson(e as Map<String, dynamic>)),
        );
    } catch (_) {}
    notifyListeners();
  }

  Future<void> add(String name) async {
    _folders.add(HistoryFolder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      createdAt: DateTime.now(),
    ));
    notifyListeners();
    await _persist();
  }

  Future<void> rename(String id, String newName) async {
    final idx = _folders.indexWhere((f) => f.id == id);
    if (idx == -1) return;
    final old = _folders[idx];
    _folders[idx] = HistoryFolder(
      id: old.id,
      name: newName,
      createdAt: old.createdAt,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> delete(String id) async {
    _folders.removeWhere((f) => f.id == id);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode(_folders.map((f) => f.toJson()).toList()),
      );
    } catch (_) {}
  }
}
