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

  Future<Directory> _audioDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${dir.path}/audio');
    if (!audioDir.existsSync()) audioDir.createSync(recursive: true);
    return audioDir;
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
    HistoryItem savedItem = item;

    if (item.audioFilePath != null) {
      try {
        final audioDir = await _audioDir();
        final fileName = item.audioFilePath!.split('/').last;
        final dest = '${audioDir.path}/$fileName';
        await File(item.audioFilePath!).copy(dest);
        savedItem = HistoryItem(
          id: item.id,
          type: item.type,
          createdAt: item.createdAt,
          result: item.result,
          original: item.original,
          languageName: item.languageName,
          voiceName: item.voiceName,
          audioFilePath: dest,
          folderId: item.folderId,
        );
      } catch (_) {
        savedItem = HistoryItem(
          id: item.id,
          type: item.type,
          createdAt: item.createdAt,
          result: item.result,
          original: item.original,
          languageName: item.languageName,
          voiceName: item.voiceName,
          folderId: item.folderId,
        );
      }
    }

    _items.insert(0, savedItem);
    if (_items.length > _maxItems) {
      _deleteAudioFile(_items.removeLast());
    }
    notifyListeners();
    await _persist();
  }

  Future<void> delete(String id) async {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx != -1) {
      _deleteAudioFile(_items[idx]);
      _items.removeAt(idx);
    }
    notifyListeners();
    await _persist();
  }

  Future<HistoryItem?> softDelete(String id) async {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx == -1) return null;
    final item = _items[idx];
    _items.removeAt(idx);
    notifyListeners();
    await _persist();
    return item;
  }

  Future<void> undoDelete(HistoryItem item) async {
    _items.insert(0, item);
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
    await _persist();
  }

  void deleteAudioFile(HistoryItem item) => _deleteAudioFile(item);

  List<HistoryItem> softDeleteBatch(List<String> ids) {
    final deleted = <HistoryItem>[];
    for (final id in ids) {
      final idx = _items.indexWhere((e) => e.id == id);
      if (idx != -1) {
        deleted.add(_items[idx]);
        _items.removeAt(idx);
      }
    }
    if (deleted.isNotEmpty) {
      notifyListeners();
      _persist();
    }
    return deleted;
  }

  Future<void> undoDeleteBatch(List<HistoryItem> items) async {
    for (final item in items) {
      _items.insert(0, item);
    }
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
    await _persist();
  }

  Future<void> moveToFolderBatch(List<String> ids, String? folderId) async {
    for (final id in ids) {
      final idx = _items.indexWhere((e) => e.id == id);
      if (idx == -1) continue;
      final old = _items[idx];
      _items[idx] = HistoryItem(
        id: old.id,
        type: old.type,
        createdAt: old.createdAt,
        result: old.result,
        original: old.original,
        languageName: old.languageName,
        voiceName: old.voiceName,
        audioFilePath: old.audioFilePath,
        folderId: folderId,
      );
    }
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    for (final item in _items) {
      _deleteAudioFile(item);
    }
    _items.clear();
    notifyListeners();
    await _persist();
  }

  void _deleteAudioFile(HistoryItem item) {
    if (item.audioFilePath != null) {
      try {
        File(item.audioFilePath!).deleteSync();
      } catch (_) {}
    }
  }

  Future<void> updateResult(String id, String newResult) async {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    final old = _items[idx];
    _items[idx] = HistoryItem(
      id: old.id,
      type: old.type,
      createdAt: old.createdAt,
      result: newResult,
      original: old.original,
      languageName: old.languageName,
      voiceName: old.voiceName,
      audioFilePath: old.audioFilePath,
      folderId: old.folderId,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> updateOriginal(String id, String newOriginal) async {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    final old = _items[idx];
    _items[idx] = HistoryItem(
      id: old.id,
      type: old.type,
      createdAt: old.createdAt,
      result: old.result,
      original: newOriginal,
      languageName: old.languageName,
      voiceName: old.voiceName,
      audioFilePath: old.audioFilePath,
      folderId: old.folderId,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> moveToFolder(String id, String? folderId) async {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    final old = _items[idx];
    _items[idx] = HistoryItem(
      id: old.id,
      type: old.type,
      createdAt: old.createdAt,
      result: old.result,
      original: old.original,
      languageName: old.languageName,
      voiceName: old.voiceName,
      audioFilePath: old.audioFilePath,
      folderId: folderId,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> deleteAllFromFolder(String folderId) async {
    final toDelete = _items.where((e) => e.folderId == folderId).toList();
    if (toDelete.isEmpty) return;
    for (final item in toDelete) {
      _deleteAudioFile(item);
    }
    _items.removeWhere((e) => e.folderId == folderId);
    notifyListeners();
    await _persist();
  }

  Future<int> restoreItems(List<HistoryItem> items) async {
    final existingIds = _items.map((e) => e.id).toSet();
    int added = 0;
    for (final item in items) {
      if (!existingIds.contains(item.id)) {
        _items.add(item);
        existingIds.add(item.id);
        added++;
      }
    }
    if (added == 0) return 0;
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    while (_items.length > _maxItems) {
      _deleteAudioFile(_items.removeLast());
    }
    notifyListeners();
    await _persist();
    return added;
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
