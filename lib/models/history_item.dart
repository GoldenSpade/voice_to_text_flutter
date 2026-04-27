import 'package:flutter/material.dart';

enum HistoryType {
  transcription,
  translation,
  transcriptionTranslation,
  fullCycle,
  tts,
}

extension HistoryTypeX on HistoryType {
  String get label => switch (this) {
        HistoryType.transcription => 'Транскрибация',
        HistoryType.translation => 'Перевод текста',
        HistoryType.transcriptionTranslation => 'Транскр. + Перевод',
        HistoryType.fullCycle => 'Полный цикл',
        HistoryType.tts => 'Текст в голос',
      };

  IconData get icon => switch (this) {
        HistoryType.transcription => Icons.mic,
        HistoryType.translation => Icons.translate,
        HistoryType.transcriptionTranslation => Icons.language,
        HistoryType.fullCycle => Icons.record_voice_over,
        HistoryType.tts => Icons.volume_up,
      };

  Color get color => switch (this) {
        HistoryType.transcription => const Color(0xFF533483),
        HistoryType.translation => const Color(0xFF1565C0),
        HistoryType.transcriptionTranslation => const Color(0xFF00695C),
        HistoryType.fullCycle => const Color(0xFF4A148C),
        HistoryType.tts => const Color(0xFF6A1B9A),
      };
}

class HistoryItem {
  final String id;
  final HistoryType type;
  final DateTime createdAt;
  final String result;
  final String? original;
  final String? languageName;
  final String? voiceName;
  final String? audioFilePath;

  const HistoryItem({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.result,
    this.original,
    this.languageName,
    this.voiceName,
    this.audioFilePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'createdAt': createdAt.toIso8601String(),
        'result': result,
        if (original != null) 'original': original,
        if (languageName != null) 'languageName': languageName,
        if (voiceName != null) 'voiceName': voiceName,
        if (audioFilePath != null) 'audioFilePath': audioFilePath,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        id: json['id'] as String,
        type: HistoryType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => HistoryType.transcription,
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        result: json['result'] as String,
        original: json['original'] as String?,
        languageName: json['languageName'] as String?,
        voiceName: json['voiceName'] as String?,
        audioFilePath: json['audioFilePath'] as String?,
      );
}
