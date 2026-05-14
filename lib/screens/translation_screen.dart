import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_theme.dart';
import '../models/history_item.dart';
import '../models/translation_languages.dart';
import '../providers/app_state.dart';
import '../services/history_service.dart';
import '../services/openai_service.dart';
import '../services/telegram_service.dart';
import 'transform_sheet.dart';

enum _State { idle, processing, result, error }

class TranslationScreen extends StatefulWidget {
  final String? initialText;
  const TranslationScreen({super.key, this.initialText});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  final _controller = TextEditingController();
  _State _state = _State.idle;
  String? _resultText;
  String? _errorMessage;
  var _lang = kTranslationLanguages[1];
  (String, String, String)? _sourceLang;
  late AppButtonTheme _theme;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _controller.text = widget.initialText!;
    }
    SharedPreferences.getInstance().then((prefs) {
      final idx = (prefs.getInt('pref_trans_lang') ?? 1)
          .clamp(0, kTranslationLanguages.length - 1);
      final srcIdx = prefs.getInt('pref_trans_src_lang') ?? -1;
      if (mounted) {
        setState(() {
          _lang = kTranslationLanguages[idx];
          _sourceLang = srcIdx >= 0 && srcIdx < kTranslationLanguages.length
              ? kTranslationLanguages[srcIdx]
              : null;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _state = _State.processing;
      _resultText = null;
      _errorMessage = null;
    });

    final appState = context.read<AppState>();
    try {
      final result = await OpenAIService(appState.apiKey).translateText(
        text,
        _lang.$3,
        sourceLanguage: _sourceLang?.$3,
      );

      if (mounted) {
        context.read<HistoryService>().add(HistoryItem(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              type: HistoryType.translation,
              createdAt: DateTime.now(),
              result: result,
              original: text,
              languageName: _lang.$2,
            ));
        context.read<TelegramService>().sendResult(
          type: HistoryType.translation,
          result: result,
          original: text,
          languageName: _lang.$2,
        );
        setState(() {
          _state = _State.result;
          _resultText = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _State.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _showSourceLanguagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SourceLanguagePicker(
        selected: _sourceLang,
        onPick: (lang) {
          final idx =
              lang != null ? kTranslationLanguages.indexOf(lang) : -1;
          SharedPreferences.getInstance()
              .then((p) => p.setInt('pref_trans_src_lang', idx));
          setState(() => _sourceLang = lang);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LanguagePicker(
        selected: _lang,
        onPick: (lang) {
          final idx = kTranslationLanguages.indexOf(lang);
          SharedPreferences.getInstance()
              .then((p) => p.setInt('pref_trans_lang', idx));
          setState(() => _lang = lang);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _theme = state.buttonTheme;
    final l10n = state.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translateText),
        backgroundColor: _theme.appBarColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(child: _buildBody(l10n)),
    );
  }

  Widget _buildBody(l10n) {
    return switch (_state) {
      _State.idle => _buildIdle(l10n),
      _State.processing => _buildProcessing(l10n),
      _State.result => _buildResult(l10n),
      _State.error => _buildError(l10n),
    };
  }

  Widget _buildIdle(l10n) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, height: 1.6),
              decoration: InputDecoration(
                hintText: l10n.translateInputHint,
                hintStyle:
                    TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: _theme.surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, value, __) {
              final chars = value.text.length;
              final tokens = chars ~/ 4;
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$chars симв · ~$tokens токенов',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: _showSourceLanguagePicker,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _theme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.text_fields,
                      color: Colors.white54, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    '${l10n.sourceLanguage}:',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5), fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _sourceLang?.$2 ?? l10n.langAuto,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      color: Colors.white38, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _showLanguagePicker,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _theme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.language,
                      color: Colors.white54, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    '${l10n.selectLanguage}:',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5), fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lang.$2,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      color: Colors.white38, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, value, __) => SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: value.text.trim().isEmpty ? null : _translate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _theme.colors[0],
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      _theme.colors[0].withOpacity(0.35),
                  disabledForegroundColor: Colors.white38,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(l10n.translateBtn,
                    style: const TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessing(l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: _theme.colors[0]),
          ),
          const SizedBox(height: 32),
          Text(l10n.translating,
              style: const TextStyle(color: Colors.white, fontSize: 17)),
          const SizedBox(height: 8),
          Text(l10n.sendingText,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildResult(l10n) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(l10n.original),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _theme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _controller.text.trim(),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14, height: 1.6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionLabel('${l10n.translation} → ${_lang.$2}'),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _theme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _resultText ?? '',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, height: 1.6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _CopyButton(
                  label: l10n.copyOriginal,
                  text: _controller.text.trim(),
                  parentContext: context,
                  snackLabel: l10n.copied,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CopyButton(
                  label: l10n.copyTranslation,
                  text: _resultText ?? '',
                  parentContext: context,
                  snackLabel: l10n.copied,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Share.share(_controller.text.trim()),
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: Text(l10n.shareOriginal,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Share.share(_resultText ?? ''),
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: Text(l10n.shareTranslation,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  showTransformSheet(context, _resultText ?? ''),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(l10n.transformText),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withOpacity(0.2)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() {
                _state = _State.idle;
                _resultText = null;
              }),
              icon: const Icon(Icons.translate, size: 18),
              label: Text(l10n.again),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                color: Colors.redAccent, size: 64),
            const SizedBox(height: 20),
            Text(
              l10n.errorOccurred,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.resolveApiError(_errorMessage),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 13,
                  height: 1.5),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => setState(() {
                _state = _State.idle;
                _errorMessage = null;
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: _theme.colors[0],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(l10n.tryAgain),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  final String label;
  final String text;
  final String snackLabel;
  final BuildContext parentContext;

  const _CopyButton({
    required this.label,
    required this.text,
    required this.snackLabel,
    required this.parentContext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.read<AppState>().buttonTheme;
    return ElevatedButton.icon(
      onPressed: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(parentContext).showSnackBar(
          SnackBar(
            content: Text(snackLabel),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      icon: const Icon(Icons.copy, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colors[0],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _SourceLanguagePicker extends StatelessWidget {
  final (String, String, String)? selected;
  final void Function((String, String, String)?) onPick;

  const _SourceLanguagePicker({required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final theme = appState.buttonTheme;
    final l10n = appState.l10n;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: kTranslationLanguages.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  final isAuto = selected == null;
                  return ListTile(
                    title: Text(l10n.langAuto,
                        style: const TextStyle(color: Colors.white)),
                    trailing: isAuto
                        ? Icon(Icons.check, color: theme.colors[0])
                        : null,
                    tileColor: isAuto
                        ? theme.colors[0].withOpacity(0.15)
                        : null,
                    onTap: () => onPick(null),
                  );
                }
                final lang = kTranslationLanguages[i - 1];
                final isSelected = selected?.$1 == lang.$1;
                return ListTile(
                  title: Text(lang.$2,
                      style: const TextStyle(color: Colors.white)),
                  trailing: isSelected
                      ? Icon(Icons.check, color: theme.colors[0])
                      : null,
                  tileColor: isSelected
                      ? theme.colors[0].withOpacity(0.15)
                      : null,
                  onTap: () => onPick(lang),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  final (String, String, String) selected;
  final void Function((String, String, String)) onPick;

  const _LanguagePicker({required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = context.read<AppState>().buttonTheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: kTranslationLanguages.length,
              itemBuilder: (_, i) {
                final lang = kTranslationLanguages[i];
                final isSelected = lang.$1 == selected.$1;
                return ListTile(
                  title: Text(
                    lang.$2,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check, color: theme.colors[0])
                      : null,
                  tileColor: isSelected
                      ? theme.colors[0].withOpacity(0.15)
                      : null,
                  onTap: () => onPick(lang),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
