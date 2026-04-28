import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import '../models/app_theme.dart';
import '../models/history_item.dart';
import '../models/translation_languages.dart';
import '../providers/app_state.dart';
import '../services/history_service.dart';
import '../services/openai_service.dart';

enum _State { idle, recording, transcribing, translating, result, error }

class TranscriptionTranslationScreen extends StatefulWidget {
  const TranscriptionTranslationScreen({super.key});

  @override
  State<TranscriptionTranslationScreen> createState() =>
      _TranscriptionTranslationScreenState();
}

class _TranscriptionTranslationScreenState
    extends State<TranscriptionTranslationScreen>
    with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  _State _state = _State.idle;
  String? _transcribedText;
  String? _translatedText;
  String? _errorMessage;
  Timer? _timer;
  int _seconds = 0;
  var _lang = kTranslationLanguages[1];
  late AppButtonTheme _theme;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final l10n = context.read<AppState>().l10n;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.noMicPermission)),
        );
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    _seconds = 0;
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() => _seconds++);
      },
    );

    _pulseController.repeat(reverse: true);
    setState(() => _state = _State.recording);
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _pulseController.stop();
    _pulseController.reset();

    final path = await _recorder.stop();
    if (path == null) {
      final l10n = context.read<AppState>().l10n;
      setState(() {
        _state = _State.error;
        _errorMessage = l10n.unknownError;
      });
      return;
    }

    setState(() => _state = _State.transcribing);

    final service = OpenAIService(context.read<AppState>().apiKey);

    String transcribed;
    try {
      transcribed = await service.transcribeAudio(path);
      try {
        File(path).deleteSync();
      } catch (_) {}
    } catch (e) {
      try {
        File(path).deleteSync();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _state = _State.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _transcribedText = transcribed;
      _state = _State.translating;
    });

    try {
      final translated = await service.translateText(transcribed, _lang.$3);
      if (mounted) {
        context.read<HistoryService>().add(HistoryItem(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              type: HistoryType.transcriptionTranslation,
              createdAt: DateTime.now(),
              result: translated,
              original: transcribed,
              languageName: _lang.$2,
            ));
        setState(() {
          _state = _State.result;
          _translatedText = translated;
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

  String _formatTime(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:'
      '${(s % 60).toString().padLeft(2, '0')}';

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
        title: Text(l10n.transcribeAndTranslate),
        backgroundColor: _theme.appBarColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(child: _buildBody(l10n)),
    );
  }

  Widget _buildBody(l10n) {
    return switch (_state) {
      _State.idle => _buildIdle(l10n),
      _State.recording => _buildRecording(l10n),
      _State.transcribing =>
        _buildProcessing(l10n.transcribing, l10n.sendingAudio),
      _State.translating =>
        _buildProcessing(l10n.translating, l10n.sendingText),
      _State.result => _buildResult(l10n),
      _State.error => _buildError(l10n),
    };
  }

  Widget _buildIdle(l10n) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: InkWell(
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
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _startRecording,
                  child: Container(
                    width: 128,
                    height: 128,
                    decoration: BoxDecoration(
                      color: _theme.colors[0],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _theme.colors[0].withOpacity(0.45),
                          blurRadius: 28,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                    child:
                        const Icon(Icons.mic, color: Colors.white, size: 56),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  l10n.tapToRecord,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.anyLanguage,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecording(l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: GestureDetector(
              onTap: _stopRecording,
              child: Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withOpacity(0.5),
                      blurRadius: 36,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(Icons.stop_rounded,
                    color: Colors.white, size: 56),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            _formatTime(_seconds),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w200,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.tapToStop,
            style: TextStyle(
                color: Colors.white.withOpacity(0.55), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessing(String title, String subtitle) {
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
          Text(title,
              style: const TextStyle(color: Colors.white, fontSize: 17)),
          const SizedBox(height: 8),
          Text(subtitle,
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
                  _transcribedText ?? '',
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
                  _translatedText ?? '',
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
                  text: _transcribedText ?? '',
                  parentContext: context,
                  snackLabel: l10n.copied,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CopyButton(
                  label: l10n.copyTranslation,
                  text: _translatedText ?? '',
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
                _transcribedText = null;
                _translatedText = null;
                _seconds = 0;
              }),
              icon: const Icon(Icons.mic, size: 18),
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
                _seconds = 0;
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
