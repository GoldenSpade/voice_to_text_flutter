import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final theme = state.buttonTheme;

    final sections = [
      _Section(Icons.info_outline, l10n.helpAboutTitle, l10n.helpAboutBody),
      _Section(Icons.mic, l10n.transcribeAudio, l10n.helpTranscribeBody),
      _Section(Icons.translate, l10n.translateText, l10n.helpTranslateBody),
      _Section(Icons.language, l10n.transcribeAndTranslate, l10n.helpBothBody),
      _Section(Icons.record_voice_over, l10n.fullCycle, l10n.helpFullCycleBody),
      _Section(Icons.volume_up, l10n.textToVoice, l10n.helpTtsBody),
      _Section(Icons.history, l10n.historyTitle, l10n.helpHistoryBody),
      _Section(Icons.settings, l10n.settingsTitle, l10n.helpSettingsBody),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.helpTitle),
        backgroundColor: theme.appBarColor,
        foregroundColor: Colors.white,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sections.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _SectionCard(sections[i], theme.surfaceColor),
      ),
    );
  }
}

class _Section {
  final IconData icon;
  final String title;
  final String body;
  const _Section(this.icon, this.title, this.body);
}

class _SectionCard extends StatelessWidget {
  final _Section section;
  final Color surfaceColor;
  const _SectionCard(this.section, this.surfaceColor);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(section.icon, color: Colors.white70, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  section.body,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
