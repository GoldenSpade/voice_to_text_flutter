import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../models/history_folder.dart';
import '../models/history_item.dart';
import 'folder_service.dart';
import 'history_service.dart';
import 'transform_presets_service.dart';

class BackupService {
  static Future<String> export(
      HistoryService history, TransformPresetsService presets) async {
    final appDir = await getApplicationDocumentsDirectory();
    final historyFile = File('${appDir.path}/history.json');
    final foldersFile = File('${appDir.path}/folders.json');
    final audioDir = Directory('${appDir.path}/audio');

    final archive = Archive();

    if (historyFile.existsSync()) {
      final bytes = historyFile.readAsBytesSync();
      archive.addFile(ArchiveFile('history.json', bytes.length, bytes));
    } else {
      final bytes = utf8.encode('[]');
      archive.addFile(ArchiveFile('history.json', bytes.length, bytes));
    }

    if (foldersFile.existsSync()) {
      final bytes = foldersFile.readAsBytesSync();
      archive.addFile(ArchiveFile('folders.json', bytes.length, bytes));
    }

    if (presets.presets.isNotEmpty) {
      final bytes = utf8.encode(jsonEncode(presets.presets));
      archive.addFile(ArchiveFile('presets.json', bytes.length, bytes));
    }

    if (audioDir.existsSync()) {
      for (final entity in audioDir.listSync()) {
        if (entity is File) {
          final bytes = entity.readAsBytesSync();
          final name = entity.uri.pathSegments.last;
          archive.addFile(ArchiveFile('audio/$name', bytes.length, bytes));
        }
      }
    }

    final zipData = ZipEncoder().encode(archive)!;

    final ts = DateTime.now();
    final stamp = '${ts.year}${_p(ts.month)}${_p(ts.day)}'
        '_${_p(ts.hour)}${_p(ts.minute)}${_p(ts.second)}';
    final fileName = 'va_backup_$stamp.zip';

    final destDir = await _downloadsDir();
    final zipPath = '${destDir.path}/$fileName';
    await File(zipPath).writeAsBytes(zipData);

    return fileName;
  }

  static Future<int> import(
    String zipPath,
    HistoryService history,
    FolderService folders,
    TransformPresetsService presets,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${appDir.path}/audio');
    if (!audioDir.existsSync()) audioDir.createSync(recursive: true);

    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    List<HistoryItem>? items;
    List<HistoryFolder>? folderList;
    List<String>? presetList;

    for (final file in archive) {
      if (!file.isFile) continue;
      final data = file.content as List<int>;

      if (file.name == 'history.json') {
        final list = jsonDecode(utf8.decode(data)) as List;
        items = list
            .map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (file.name == 'folders.json') {
        final list = jsonDecode(utf8.decode(data)) as List;
        folderList = list
            .map((e) => HistoryFolder.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (file.name == 'presets.json') {
        final list = jsonDecode(utf8.decode(data)) as List;
        presetList = list.cast<String>();
      } else if (file.name.startsWith('audio/')) {
        final audioName = file.name.replaceFirst('audio/', '');
        if (audioName.isNotEmpty) {
          await File('${audioDir.path}/$audioName').writeAsBytes(data);
        }
      }
    }

    if (items == null) throw Exception('Invalid backup: history.json not found');

    if (folderList != null) {
      await folders.restoreFolders(folderList);
    }
    if (presetList != null) {
      await presets.restorePresets(presetList);
    }

    final restored = items.map((item) {
      if (item.audioFilePath == null) {
        return HistoryItem(
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
      final fileName = item.audioFilePath!.split('/').last;
      final localPath = '${audioDir.path}/$fileName';
      return HistoryItem(
        id: item.id,
        type: item.type,
        createdAt: item.createdAt,
        result: item.result,
        original: item.original,
        languageName: item.languageName,
        voiceName: item.voiceName,
        audioFilePath: File(localPath).existsSync() ? localPath : null,
        folderId: item.folderId,
      );
    }).toList();

    return history.restoreItems(restored);
  }

  static Future<Directory> _downloadsDir() async {
    const androidDownloads = '/storage/emulated/0/Download';
    if (Directory(androidDownloads).existsSync()) {
      return Directory(androidDownloads);
    }
    final d = await getDownloadsDirectory();
    if (d != null) return d;
    return getApplicationDocumentsDirectory();
  }

  static String _p(int n) => n.toString().padLeft(2, '0');
}
