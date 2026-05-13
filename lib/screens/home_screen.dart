import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'help_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'transcription_screen.dart';
import 'full_cycle_screen.dart';
import 'transcription_translation_screen.dart';
import 'translation_screen.dart';
import 'tts_screen.dart';
import 'conversation_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final hasKey = state.hasApiKey;
    final theme = state.buttonTheme;
    final colors = theme.colors;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.appTitle),
        backgroundColor: theme.appBarColor,
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
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: l10n.helpTitle,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpScreen()),
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
                    color: colors[0],
                    textColor: theme.textPrimary,
                    subtitleColor: theme.textSecondary,
                    iconColor: theme.accentColor,
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
                    color: colors[1],
                    textColor: theme.textPrimary,
                    subtitleColor: theme.textSecondary,
                    iconColor: theme.accentColor,
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
                    color: colors[2],
                    textColor: theme.textPrimary,
                    subtitleColor: theme.textSecondary,
                    iconColor: theme.accentColor,
                    onTap: hasKey
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const TranscriptionTranslationScreen(),
                              ),
                            )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _MenuButton(
                    icon: Icons.record_voice_over,
                    label: l10n.fullCycle,
                    subtitle: l10n.fullCycleSub,
                    color: colors[3],
                    textColor: theme.textPrimary,
                    subtitleColor: theme.textSecondary,
                    iconColor: theme.accentColor,
                    onTap: hasKey
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const FullCycleScreen(),
                              ),
                            )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _MenuButton(
                    icon: Icons.volume_up,
                    label: l10n.textToVoice,
                    subtitle: l10n.textToVoiceSub,
                    color: colors[4],
                    textColor: theme.textPrimary,
                    subtitleColor: theme.textSecondary,
                    iconColor: theme.accentColor,
                    onTap: hasKey
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TtsScreen(),
                              ),
                            )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _MenuButton(
                    icon: Icons.forum_rounded,
                    label: l10n.conversationTranslator,
                    subtitle: l10n.conversationTranslatorSub,
                    color: colors[5 % colors.length],
                    textColor: theme.textPrimary,
                    subtitleColor: theme.textSecondary,
                    iconColor: theme.accentColor,
                    onTap: hasKey
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ConversationScreen(),
                              ),
                            )
                        : null,
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


}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  final Color textColor;
  final Color subtitleColor;
  final Color iconColor;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.textColor = Colors.white,
    this.subtitleColor = const Color(0xFFA6A6A6),
    this.iconColor = Colors.white,
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
                    color: iconColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: textColor.withOpacity(0.4),
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
