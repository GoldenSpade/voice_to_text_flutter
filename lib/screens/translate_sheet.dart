import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_item.dart';
import '../models/translation_languages.dart';
import '../providers/app_state.dart';
import '../services/history_service.dart';
import '../services/openai_service.dart';
import '../services/telegram_service.dart';

enum _TrState { idle, loading, result, error }

void showTranslateSheet(BuildContext context, String sourceText) {
  final theme = context.read<AppState>().buttonTheme;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TranslateSheet(sourceText: sourceText),
  );
}

class _TranslateSheet extends StatefulWidget {
  final String sourceText;
  const _TranslateSheet({required this.sourceText});

  @override
  State<_TranslateSheet> createState() => _TranslateSheetState();
}

class _TranslateSheetState extends State<_TranslateSheet> {
  var _lang = kTranslationLanguages[1];
  _TrState _state = _TrState.idle;
  String? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final idx = (prefs.getInt('pref_ts_translate_lang') ?? 1)
          .clamp(0, kTranslationLanguages.length - 1);
      if (mounted) setState(() => _lang = kTranslationLanguages[idx]);
    });
  }

  Future<void> _translate() async {
    setState(() {
      _state = _TrState.loading;
      _result = null;
      _error = null;
    });
    final appState = context.read<AppState>();
    try {
      final result = await OpenAIService(appState.apiKey)
          .translateText(widget.sourceText, _lang.$3);
      if (mounted) {
        context.read<HistoryService>().add(HistoryItem(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              type: HistoryType.transcriptionTranslation,
              createdAt: DateTime.now(),
              result: result,
              original: widget.sourceText,
              languageName: _lang.$2,
            ));
        context.read<TelegramService>().sendResult(
          type: HistoryType.transcriptionTranslation,
          result: result,
          original: widget.sourceText,
          languageName: _lang.$2,
        );
        setState(() {
          _state = _TrState.result;
          _result = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _TrState.error;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _showLanguagePicker() {
    final theme = context.read<AppState>().buttonTheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LanguagePicker(
        selected: _lang,
        onPick: (lang) {
          final idx = kTranslationLanguages.indexOf(lang);
          SharedPreferences.getInstance()
              .then((p) => p.setInt('pref_ts_translate_lang', idx));
          setState(() => _lang = lang);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = appState.buttonTheme;
    final l10n = appState.l10n;
    return switch (_state) {
      _TrState.idle => _buildIdle(theme, l10n),
      _TrState.loading => _buildLoading(theme, l10n),
      _TrState.result => _buildResult(theme, l10n),
      _TrState.error => _buildError(theme, l10n),
    };
  }

  Widget _buildIdle(theme, l10n) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, mq.viewInsets.bottom + mq.viewPadding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Handle(),
          const SizedBox(height: 14),
          Text(l10n.translateText,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              widget.sourceText.length > 220
                  ? '${widget.sourceText.substring(0, 220)}…'
                  : widget.sourceText,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _showLanguagePicker,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black26,
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
                    child: Text(_lang.$2,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15)),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      color: Colors.white38, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _translate,
              icon: const Icon(Icons.translate, size: 18),
              label: Text(l10n.translateBtn),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colors[0],
                foregroundColor: Colors.white,
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

  Widget _buildLoading(theme, l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Handle(),
          const SizedBox(height: 32),
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: theme.colors[0]),
          ),
          const SizedBox(height: 20),
          Text(l10n.translating,
              style: const TextStyle(color: Colors.white, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildResult(theme, l10n) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, mq.viewInsets.bottom + mq.viewPadding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Handle(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(l10n.result,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
              _LangBadge(_lang.$2),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 300),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _result ?? '',
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, height: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _result ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(l10n.copied),
                          duration: const Duration(seconds: 1)),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(l10n.copy),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colors[0],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Share.share(_result ?? ''),
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: Text(l10n.shareText),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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
                  setState(() {
                    _state = _TrState.idle;
                    _result = null;
                  }),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(l10n.again),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withOpacity(0.2)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(theme, l10n) {
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(32, 32, 32, 32 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Handle(),
          const SizedBox(height: 20),
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text(
            l10n.resolveApiError(_error),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
                height: 1.5),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () =>
                setState(() {
                  _state = _TrState.idle;
                  _error = null;
                }),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colors[0],
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(l10n.tryAgain),
          ),
        ],
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _LangBadge extends StatelessWidget {
  final String label;
  const _LangBadge(this.label);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style:
                const TextStyle(color: Colors.white60, fontSize: 11)),
      );
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
                  title: Text(lang.$2,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(lang.$3,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
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
