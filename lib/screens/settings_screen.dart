import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/app_theme.dart';
import '../providers/app_state.dart';
import '../services/telegram_service.dart';

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
        12 => l10n.themePastelMono,
        13 => l10n.themeDuskMono,
        14 => l10n.themeEarthMono,
        15 => l10n.themeNeutralMono,
        16 => l10n.themeMistMono,
        17 => l10n.themeOceanMono,
        18 => l10n.themeSakuraMono,
        19 => l10n.themeSunsetMono,
        20 => l10n.themeVividMono,
        21 => l10n.themeMintMono,
        22 => l10n.themeLavenderMono,
        _ => l10n.themeGraphiteMono,
      };

  static const _monoIndices = {12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23};

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

          _TelegramSection(theme: theme, l10n: l10n),

          const SizedBox(height: 32),
          const Divider(color: Colors.white12),
          const SizedBox(height: 16),

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


        ],
      ),
    );
  }
}

class _TelegramSection extends StatefulWidget {
  final AppButtonTheme theme;
  final AppLocalizations l10n;
  const _TelegramSection({required this.theme, required this.l10n});

  @override
  State<_TelegramSection> createState() => _TelegramSectionState();
}

class _TelegramSectionState extends State<_TelegramSection> {
  late TextEditingController _tokenCtrl;
  late TextEditingController _chatIdCtrl;
  bool _detecting = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final tg = context.read<TelegramService>();
    _tokenCtrl = TextEditingController(text: tg.token);
    _chatIdCtrl = TextEditingController(text: tg.chatId);
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _chatIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _autoDetect() async {
    final tg = context.read<TelegramService>();
    await tg.setToken(_tokenCtrl.text);
    setState(() => _detecting = true);
    final id = await tg.fetchChatId();
    if (!mounted) return;
    setState(() => _detecting = false);
    if (id != null) {
      _chatIdCtrl.text = id;
      await tg.setChatId(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.l10n.telegramDetected),
        backgroundColor: Colors.green,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.l10n.telegramNotFound),
      ));
    }
  }

  Future<void> _test() async {
    final tg = context.read<TelegramService>();
    await tg.setToken(_tokenCtrl.text);
    await tg.setChatId(_chatIdCtrl.text);
    setState(() => _testing = true);
    final ok = await tg.sendTest();
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? widget.l10n.telegramTestOk : widget.l10n.telegramTestFail),
      backgroundColor: ok ? Colors.green : null,
    ));
  }

  Future<void> _disconnect() async {
    await context.read<TelegramService>().clear();
    _tokenCtrl.clear();
    _chatIdCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final l10n = widget.l10n;
    final tg = context.watch<TelegramService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Telegram Bot',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.telegramHint,
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _tokenCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Bot Token',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
            filled: true,
            fillColor: theme.surfaceColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatIdCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Chat ID',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                  filled: true,
                  fillColor: theme.surfaceColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _detecting ? null : _autoDetect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.surfaceColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _detecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(l10n.telegramAutoDetect,
                        style: const TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            onPressed: _testing ? null : _test,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colors[0],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _testing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(l10n.telegramTestBtn,
                    style: const TextStyle(fontSize: 15)),
          ),
        ),
        if (tg.isConfigured) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _disconnect,
            child: Text(
              l10n.telegramDisconnect,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ],
    );
  }
}

