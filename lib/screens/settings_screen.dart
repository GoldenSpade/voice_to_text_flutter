import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/app_theme.dart';
import '../providers/app_state.dart';
import '../services/backup_service.dart';
import '../services/history_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _controller;
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<AppState>().apiKey,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.read<AppState>().l10n;
    final key = _controller.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterApiKey)),
      );
      return;
    }
    setState(() => _saving = true);
    await context.read<AppState>().saveApiKey(key);
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.apiKeySaved),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  String _themeName(AppLocalizations l10n, int i) => switch (i) {
        0 => l10n.themePastel,
        1 => l10n.themeDusk,
        2 => l10n.themeEarth,
        3 => l10n.themeMono,
        4 => l10n.themeMist,
        5 => l10n.themeOcean,
        6 => l10n.themeSakura,
        7 => l10n.themeSunset,
        8 => l10n.themeVivid,
        9 => l10n.themeMint,
        10 => l10n.themeLavender,
        11 => l10n.themeGraphite,
        _ => l10n.themePastelMono,
      };

  static const _monoIndices = {12};

  Widget _buildThemeGroup({
    required String title,
    required List<int> indices,
    required int selectedIndex,
    required AppLocalizations l10n,
    required AppState state,
    bool initiallyExpanded = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 12),
        title: Text(
          title,
          style: TextStyle(
            color: indices.contains(selectedIndex)
                ? Colors.white
                : Colors.white54,
            fontSize: 14,
            fontWeight: indices.contains(selectedIndex)
                ? FontWeight.w600
                : FontWeight.normal,
          ),
        ),
        trailing: Icon(
          Icons.expand_more,
          color: Colors.white38,
        ),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 14,
            children: indices.map((i) {
              final t = kAppThemes[i];
              final selected = selectedIndex == i;
              final themeName = _themeName(l10n, i);
              return GestureDetector(
                onTap: () => state.saveTheme(i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? Colors.white : Colors.white24,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 88,
                          height: 108,
                          child: Column(
                            children: [
                              Container(height: 14, color: t.appBarColor),
                              Expanded(
                                child: Container(
                                  color: t.backgroundColor,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: t.colors
                                        .map((c) => Container(
                                              height: 11,
                                              decoration: BoxDecoration(
                                                color: c,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                            ))
                                        .toList(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected)
                          const Icon(Icons.check_circle,
                              color: Colors.white, size: 12),
                        if (selected) const SizedBox(width: 3),
                        Text(
                          themeName,
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.white54,
                            fontSize: 11,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _export(AppLocalizations l10n) async {
    try {
      final name =
          await BackupService.export(context.read<HistoryService>());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.exportDone}: $name'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _import(AppLocalizations l10n) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.single.path == null) return;
    try {
      final count = await BackupService.import(
        result.files.single.path!,
        context.read<HistoryService>(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.importDone}: $count'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  void _showLanguagePicker(BuildContext context, AppState state) {
    final theme = state.buttonTheme;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: theme.surfaceColor,
        title: Text(
          state.l10n.interfaceLanguage,
          style: const TextStyle(color: Colors.white),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: AppLocalizations.supportedLanguages.map(((String, String) lang) {
              final (code, name) = lang;
              return RadioListTile<String>(
                value: code,
                groupValue: state.languageCode,
                activeColor: theme.colors[0],
                title: Text(name, style: const TextStyle(color: Colors.white)),
                onChanged: (val) {
                  if (val != null) {
                    state.saveLanguage(val);
                    Navigator.pop(context);
                  }
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              state.l10n.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final theme = state.buttonTheme;

    final currentLangName = AppLocalizations.supportedLanguages
        .firstWhere(
          (e) => e.$1 == state.languageCode,
          orElse: () => ('en', 'English'),
        )
        .$2;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        backgroundColor: theme.appBarColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
        children: [
          // ── Language ─────────────────────────────────────────────────────
          Text(
            l10n.interfaceLanguage,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _showLanguagePicker(context, state),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: theme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.language,
                      color: Colors.white54, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      currentLangName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      color: Colors.white38, size: 16),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),
          const Divider(color: Colors.white12),
          const SizedBox(height: 16),

          // ── API Key ──────────────────────────────────────────────────────
          Text(
            l10n.apiKeyLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.apiKeyDescription,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'sk-proj-...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
              filled: true,
              fillColor: theme.surfaceColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white54,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colors[0],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(l10n.save,
                      style: const TextStyle(fontSize: 16)),
            ),
          ),
          if (state.hasApiKey) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await context.read<AppState>().saveApiKey('');
                _controller.clear();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.apiKeyDeleted)),
                  );
                }
              },
              child: Text(
                l10n.deleteKey,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ],

          const SizedBox(height: 32),
          const Divider(color: Colors.white12),
          const SizedBox(height: 16),

          // ── Color Theme ──────────────────────────────────────────────────
          Text(
            l10n.colorThemeLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _buildThemeGroup(
            title: l10n.themeGroupMulti,
            indices: List.generate(
                kAppThemes.length - _monoIndices.length, (i) => i),
            selectedIndex: state.themeIndex,
            l10n: l10n,
            state: state,
            initiallyExpanded: !_monoIndices.contains(state.themeIndex),
          ),
          const Divider(color: Colors.white12, height: 1),
          _buildThemeGroup(
            title: l10n.themeGroupMono,
            indices: _monoIndices.toList(),
            selectedIndex: state.themeIndex,
            l10n: l10n,
            state: state,
            initiallyExpanded: _monoIndices.contains(state.themeIndex),
          ),

          const SizedBox(height: 32),
          const Divider(color: Colors.white12),
          const SizedBox(height: 16),

          // ── Backup ────────────────────────────────────────────────────────
          Text(
            l10n.backupSection,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _BackupTile(
            icon: Icons.upload_rounded,
            title: l10n.exportHistory,
            subtitle: 'ZIP → Downloads',
            surfaceColor: theme.surfaceColor,
            accentColor: theme.colors[0],
            onTap: () => _export(l10n),
          ),
          const SizedBox(height: 8),
          _BackupTile(
            icon: Icons.download_rounded,
            title: l10n.importHistory,
            subtitle: 'ZIP',
            surfaceColor: theme.surfaceColor,
            accentColor: theme.colors[0],
            onTap: () => _import(l10n),
          ),

        ],
      ),
    );
  }
}

class _BackupTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color surfaceColor;
  final Color accentColor;
  final VoidCallback onTap;

  const _BackupTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.surfaceColor,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }
}
