import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/history_item.dart';
import '../providers/app_state.dart';
import '../services/history_service.dart';
import '../services/openai_service.dart';

enum _State { idle, processing, result, error }

const _kLanguages = <(String, String, String)>[
  ('en', 'English', 'English'),
  ('ru', 'Русский', 'Russian'),
  ('uk', 'Українська', 'Ukrainian'),
  ('de', 'Deutsch', 'German'),
  ('fr', 'Français', 'French'),
  ('es', 'Español', 'Spanish'),
  ('it', 'Italiano', 'Italian'),
  ('pt', 'Português', 'Portuguese'),
  ('pl', 'Polski', 'Polish'),
  ('nl', 'Nederlands', 'Dutch'),
  ('sv', 'Svenska', 'Swedish'),
  ('no', 'Norsk', 'Norwegian'),
  ('da', 'Dansk', 'Danish'),
  ('fi', 'Suomi', 'Finnish'),
  ('cs', 'Čeština', 'Czech'),
  ('ro', 'Română', 'Romanian'),
  ('hu', 'Magyar', 'Hungarian'),
  ('tr', 'Türkçe', 'Turkish'),
  ('ar', 'العربية', 'Arabic'),
  ('zh', '中文', 'Chinese'),
  ('ja', '日本語', 'Japanese'),
  ('ko', '한국어', 'Korean'),
];

class TranslationScreen extends StatefulWidget {
  const TranslationScreen({super.key});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  final _controller = TextEditingController();
  _State _state = _State.idle;
  String? _resultText;
  String? _errorMessage;
  var _lang = _kLanguages[1]; // default: Russian

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
      final result =
          await OpenAIService(appState.apiKey).translateText(text, _lang.$3);

      if (mounted) {
        context.read<HistoryService>().add(HistoryItem(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              type: HistoryType.translation,
              createdAt: DateTime.now(),
              result: result,
              original: text,
              languageName: _lang.$2,
            ));
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

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LanguagePicker(
        selected: _lang,
        onPick: (lang) {
          setState(() => _lang = lang);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<AppState>().l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translateText),
        backgroundColor: const Color(0xFF0F3460),
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
                fillColor: const Color(0xFF16213E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _showLanguagePicker,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF16213E),
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
                  backgroundColor: const Color(0xFF533483),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      const Color(0xFF533483).withOpacity(0.35),
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
          const SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: Color(0xFF533483)),
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
                color: const Color(0xFF16213E),
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
                color: const Color(0xFF16213E),
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
              _errorMessage ?? l10n.unknownError,
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
                backgroundColor: const Color(0xFF533483),
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
        backgroundColor: const Color(0xFF533483),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
              itemCount: _kLanguages.length,
              itemBuilder: (_, i) {
                final lang = _kLanguages[i];
                final isSelected = lang.$1 == selected.$1;
                return ListTile(
                  title: Text(
                    lang.$2,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: Color(0xFF533483))
                      : null,
                  tileColor: isSelected
                      ? const Color(0xFF533483).withOpacity(0.15)
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
