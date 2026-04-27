import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hasKey = context.watch<AppState>().hasApiKey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Assistant'),
        backgroundColor: const Color(0xFF0F3460),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!hasKey) _ApiKeyBanner(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MenuButton(
                    icon: Icons.mic,
                    label: 'Транскрибация аудио',
                    subtitle: 'Голос → Текст',
                    color: const Color(0xFF533483),
                    onTap: hasKey ? () => _notImplemented(context) : null,
                  ),
                  const SizedBox(height: 12),
                  _MenuButton(
                    icon: Icons.translate,
                    label: 'Перевод текста',
                    subtitle: 'Текст → Переведённый текст',
                    color: const Color(0xFF0F3460),
                    onTap: hasKey ? () => _notImplemented(context) : null,
                  ),
                  const SizedBox(height: 12),
                  _MenuButton(
                    icon: Icons.language,
                    label: 'Транскрибация + Перевод',
                    subtitle: 'Голос → Текст → Перевод',
                    color: const Color(0xFF16213E),
                    onTap: hasKey ? () => _notImplemented(context) : null,
                  ),
                  const SizedBox(height: 12),
                  _MenuButton(
                    icon: Icons.record_voice_over,
                    label: 'Полный цикл',
                    subtitle: 'Голос → Текст → Перевод → Голос',
                    color: const Color(0xFF1A1A2E),
                    onTap: hasKey ? () => _notImplemented(context) : null,
                  ),
                  const SizedBox(height: 12),
                  _MenuButton(
                    icon: Icons.volume_up,
                    label: 'Текст в голос',
                    subtitle: 'Текст → Аудио',
                    color: const Color(0xFF533483),
                    onTap: hasKey ? () => _notImplemented(context) : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ApiKeyBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
      child: Container(
        width: double.infinity,
        color: const Color(0xFFB00020),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'OpenAI API ключ не задан. Нажмите для настройки.',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }

  void _notImplemented(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Будет добавлено в следующем этапе')),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.45 : 1.0,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white.withOpacity(0.4),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
