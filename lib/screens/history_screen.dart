import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/history_item.dart';
import '../services/history_service.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История'),
        backgroundColor: const Color(0xFF0F3460),
        foregroundColor: Colors.white,
        actions: [
          Consumer<HistoryService>(
            builder: (context, svc, _) {
              if (svc.items.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Очистить всё',
                onPressed: () => _confirmClear(context, svc),
              );
            },
          ),
        ],
      ),
      body: Consumer<HistoryService>(
        builder: (context, svc, _) {
          if (svc.items.isEmpty) return _buildEmpty();
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: svc.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, i) =>
                _HistoryCard(item: svc.items[i], service: svc),
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 72, color: Colors.white.withOpacity(0.15)),
          const SizedBox(height: 16),
          Text(
            'История пуста',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Результаты операций будут сохраняться здесь',
            style: TextStyle(
              color: Colors.white.withOpacity(0.25),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, HistoryService svc) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Очистить историю?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Все записи будут удалены. Это действие нельзя отменить.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              svc.clear();
              Navigator.pop(context);
            },
            child: const Text('Удалить',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryItem item;
  final HistoryService service;

  const _HistoryCard({required this.item, required this.service});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => service.delete(item.id),
      child: InkWell(
        onTap: () => _showDetail(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF16213E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: item.type.color.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.type.icon, color: item.type.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          item.type.label,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (item.languageName != null) ...[
                          const SizedBox(width: 6),
                          _Badge(item.languageName!),
                        ],
                        if (item.voiceName != null) ...[
                          const SizedBox(width: 6),
                          _Badge(item.voiceName!),
                        ],
                        const Spacer(),
                        Text(
                          _formatDate(item.createdAt),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.result,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              // Кнопка удаления на карточке
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Colors.white.withOpacity(0.3),
                ),
                splashRadius: 20,
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DetailSheet(item: item, service: service),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Удалить запись?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Эта запись будет удалена из истории.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              service.delete(item.id);
              Navigator.pop(context);
            },
            child: const Text('Удалить',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    return '${dt.day} ${months[dt.month - 1]}, '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _DetailSheet extends StatelessWidget {
  final HistoryItem item;
  final HistoryService service;

  const _DetailSheet({required this.item, required this.service});

  @override
  Widget build(BuildContext context) {
    final hasOriginal = item.original != null && item.original!.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
          20, 12, 20,
          24 + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Заголовок
            Row(
              children: [
                Icon(item.type.icon, color: item.type.color, size: 22),
                const SizedBox(width: 10),
                Text(
                  item.type.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.languageName != null) ...[
                  const SizedBox(width: 8),
                  _Badge(item.languageName!),
                ],
                if (item.voiceName != null) ...[
                  const SizedBox(width: 8),
                  _Badge(item.voiceName!),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatDateFull(item.createdAt),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const Divider(color: Colors.white12, height: 24),
            // Текст
            if (hasOriginal) ...[
              const Text(
                'ОРИГИНАЛ',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                item.original!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'ПЕРЕВОД',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
            ],
            SelectableText(
              item.result,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            // Кнопки копирования — сразу под текстом
            Row(
              children: [
                if (hasOriginal) ...[
                  Expanded(
                    child: _CopyButton(
                      label: 'Оригинал',
                      text: item.original!,
                      parentContext: context,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: _CopyButton(
                    label: hasOriginal ? 'Перевод' : 'Копировать',
                    text: item.result,
                    parentContext: context,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Кнопка удаления
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  service.delete(item.id);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.redAccent),
                label: const Text(
                  'Удалить запись',
                  style: TextStyle(color: Colors.redAccent),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateFull(DateTime dt) {
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _CopyButton extends StatelessWidget {
  final String label;
  final String text;
  final BuildContext parentContext;

  const _CopyButton({
    required this.label,
    required this.text,
    required this.parentContext,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(parentContext).showSnackBar(
          const SnackBar(
            content: Text('Скопировано'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      icon: const Icon(Icons.copy, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF533483),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white60, fontSize: 11),
      ),
    );
  }
}
