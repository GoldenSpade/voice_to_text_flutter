import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'transcription_screen.dart';
import 'translation_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final hasKey = state.hasApiKey;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        backgroundColor: const Color(0xFF0F3460),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: l10n.historyTooltip,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.settingsTooltip,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!hasKey) _ApiKeyBanner(context, l10n.apiKeyMissing),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MenuButton(
                    icon: Icons.mic,
                    label: l10n.transcribeAudio,
                    subtitle: l10n.transcribeAudioSub,
                    color: const Color(0xFF533483),
                    onTap: hasKey
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TranscriptionScreen(),
                              ),
                            )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _MenuButton(
                    icon: Icons.translate,
                    label: l10n.translateText,
                    subtitle: l10n.translateTextSub,
                    color: const Color(0xFF0F3460),
                    onTap: hasKey
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TranslationScreen(),
                              ),
                            )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _MenuButton(
                    icon: Icons.language,
                    label: l10n.transcribeAndTranslate,
                    subtitle: l10n.transcribeAndTranslateSub,
                    color: const Color(0xFF1E3254),
                    onTap: hasKey ? () => _notImplemented(context, l10n.comingSoon) : null,
                  ),
                  const SizedBox(height: 12),
                  _MenuButton(
                    icon: Icons.record_voice_over,
                    label: l10n.fullCycle,
                    subtitle: l10n.fullCycleSub,
                    color: const Color(0xFF1B3A6B),
                    onTap: hasKey ? () => _notImplemented(context, l10n.comingSoon) : null,
                  ),
                  const SizedBox(height: 12),
                  _MenuButton(
                    icon: Icons.volume_up,
                    label: l10n.textToVoice,
                    subtitle: l10n.textToVoiceSub,
                    color: const Color(0xFF533483),
                    onTap: hasKey ? () => _notImplemented(context, l10n.comingSoon) : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ApiKeyBanner(BuildContext context, String message) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
      child: Container(
        width: double.infinity,
        color: const Color(0xFFB00020),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }

  void _notImplemented(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
