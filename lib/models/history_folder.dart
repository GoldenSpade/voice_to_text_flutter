class HistoryFolder {
  final String id;
  final String name;
  final DateTime createdAt;

  const HistoryFolder({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory HistoryFolder.fromJson(Map<String, dynamic> json) => HistoryFolder(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
