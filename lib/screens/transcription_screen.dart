import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_theme.dart';
import '../models/history_item.dart';
import '../models/transcription_languages.dart';
import '../providers/app_state.dart';
import '../services/history_service.dart';
import '../services/openai_service.dart';
import '../services/telegram_service.dart';
import 'transform_sheet.dart';
import 'translate_sheet.dart';
import '../widgets/waveform_widget.dart';

enum _State { idle, recording, processing, result, error }

class TranscriptionScreen extends StatefulWidget {
  final String? initialFilePath;
  const TranscriptionScreen({super.key, this.initialFilePath});

  @override
  State<TranscriptionScreen> createState() => _TranscriptionScreenState();
}

class _TranscriptionScreenState extends State<TranscriptionScreen>
    with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  _State _state = _State.idle;
  String? _resultText;
  String? _errorMessage;
  String? _historyItemId;
  bool _correcting = false;
  bool _corrected = false;
  final _editCtrl = TextEditingController();
  bool _editing = false;
  Timer? _timer;
  int _seconds = 0;
  var _speechLang = kTranscriptionLanguages[0];
  late AppButtonTheme _theme;
  final List<double> _waveData = [];
  StreamSubscription<Amplitude>? _amplitudeSub;
  String? _recordingPath;
  double _fileSizeMb = 0;
  bool _isPaused = false;

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
    SharedPreferences.getInstance().then((prefs) {
      final idx = (prefs.getInt('pref_ts_speech_lang') ?? 0)
          .clamp(0, kTranscriptionLanguages.length - 1);
      if (mounted) setState(() => _speechLang = kTranscriptionLanguages[idx]);
    });
    if (widget.initialFilePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _transcribeFromPath(widget.initialFilePath!);
      });
    }
  }

  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _pulseController.dispose();
    _editCtrl.dispose();
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

    _recordingPath = path;
    _fileSizeMb = 0;
    _isPaused = false;
    _seconds = 0;
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() => _seconds++);
      },
    );

    _waveData.clear();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((amp) {
      if (!mounted || _isPaused) return;
      final norm = ((amp.current.clamp(-60.0, 0.0) + 60.0) / 60.0);
      double newSize = _fileSizeMb;
      try {
        newSize = File(_recordingPath!).lengthSync() / (1024 * 1024);
      } catch (_) {}
      setState(() {
        _waveData.add(norm);
        _fileSizeMb = newSize;
      });
    });

    _pulseController.repeat(reverse: true);
    setState(() => _state = _State.recording);
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
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

    setState(() => _state = _State.processing);

    final appState = context.read<AppState>();
    final langCode = _speechLang.$1.isEmpty ? null : _speechLang.$1;
    try {
      final text = await OpenAIService(appState.apiKey)
          .transcribeAudio(path, language: langCode);
      try {
        File(path).deleteSync();
      } catch (_) {}
      if (mounted) {
        final id = DateTime.now().millisecondsSinceEpoch.toString();
        context.read<HistoryService>().add(HistoryItem(
              id: id,
              type: HistoryType.transcription,
              createdAt: DateTime.now(),
              result: text,
            ));
        context.read<TelegramService>().sendResult(
          type: HistoryType.transcription,
          result: text,
        );
        setState(() {
          _state = _State.result;
          _resultText = text;
          _historyItemId = id;
          _corrected = false;
        });
      }
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
    }
  }

  Future<void> _pauseRecording() async {
    _timer?.cancel();
    _pulseController.stop();
    _pulseController.reset();
    await _recorder.pause();
    setState(() => _isPaused = true);
  }

  Future<void> _resumeRecording() async {
    await _recorder.resume();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    _pulseController.repeat(reverse: true);
    setState(() => _isPaused = false);
  }

  Future<void> _transcribeFromPath(String path) async {
    setState(() {
      _state = _State.processing;
      _resultText = null;
      _errorMessage = null;
      _corrected = false;
    });
    final appState = context.read<AppState>();
    final langCode = _speechLang.$1.isEmpty ? null : _speechLang.$1;
    try {
      final text = await OpenAIService(appState.apiKey)
          .transcribeAudio(path, language: langCode);
      if (mounted) {
        final id = DateTime.now().millisecondsSinceEpoch.toString();
        context.read<HistoryService>().add(HistoryItem(
              id: id,
              type: HistoryType.transcription,
              createdAt: DateTime.now(),
              result: text,
            ));
        context.read<TelegramService>().sendResult(
          type: HistoryType.transcription,
          result: text,
        );
        setState(() {
          _state = _State.result;
          _resultText = text;
          _historyItemId = id;
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

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;
    await _transcribeFromPath(result.files.single.path!);
  }

  void _showSpeechLanguagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SpeechLangPicker(
        selected: _speechLang,
        onPick: (lang) {
          final idx = kTranscriptionLanguages.indexOf(lang);
          SharedPreferences.getInstance()
              .then((p) => p.setInt('pref_ts_speech_lang', idx));
          setState(() => _speechLang = lang);
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _correctText() async {
    if (_resultText == null || _correcting) return;
    setState(() => _correcting = true);
    final appState = context.read<AppState>();
    try {
      final corrected =
          await OpenAIService(appState.apiKey).correctText(_resultText!);
      if (mounted) {
        if (_historyItemId != null) {
          context
              .read<HistoryService>()
              .updateResult(_historyItemId!, corrected);
        }
        setState(() {
          _resultText = corrected;
          _correcting = false;
          _corrected = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _correcting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appState.l10n.resolveApiError(
                e.toString().replaceFirst('Exception: ', ''))),
          ),
        );
      }
    }
  }

  void _startEdit() {
    _editCtrl.text = _resultText ?? '';
    setState(() => _editing = true);
  }

  void _finishEdit() {
    final newText = _editCtrl.text;
    setState(() {
      _resultText = newText;
      _editing = false;
    });
    if (_historyItemId != null) {
      context.read<HistoryService>().updateResult(_historyItemId!, newText);
    }
  }

  String _formatTime(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:'
      '${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _theme = state.buttonTheme;
    final l10n = state.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.transcribeAudio),
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
      _State.processing => _buildProcessing(l10n),
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
            onTap: _showSpeechLanguagePicker,
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
                  const Icon(Icons.mic_none,
                      color: Colors.white54, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    '${l10n.speechLanguage}:',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5), fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _speechLang.$1.isEmpty
                          ? l10n.langAuto
                          : _speechLang.$2,
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
                    child: const Icon(Icons.mic, color: Colors.white, size: 56),
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
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 48, height: 1, color: Colors.white12),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white24,
                      ),
                    ),
                    Container(width: 48, height: 1, color: Colors.white12),
                  ],
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text(l10n.uploadFile),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
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
          WaveformWidget(data: _waveData, color: Colors.redAccent),
          const SizedBox(height: 6),
          Text(
            '${_fileSizeMb.toStringAsFixed(1)} МБ / 25 МБ',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _isPaused ? _resumeRecording : _pauseRecording,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 1.5),
                  ),
                  child: Icon(
                    _isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    color: Colors.white60,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(width: 28),
              ScaleTransition(
                scale: _isPaused
                    ? AlwaysStoppedAnimation<double>(1.0)
                    : _pulseAnimation,
                child: GestureDetector(
                  onTap: _stopRecording,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent
                              .withOpacity(_isPaused ? 0.2 : 0.5),
                          blurRadius: 36,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.stop_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isPaused) ...[
                const Icon(Icons.pause_rounded,
                    color: Colors.amber, size: 14),
                const SizedBox(width: 4),
              ],
              Text(
                _formatTime(_seconds),
                style: TextStyle(
                  color: _isPaused
                      ? Colors.amber.withOpacity(0.8)
                      : Colors.white.withOpacity(0.7),
                  fontSize: 22,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tapToStop,
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 13,
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
              strokeWidth: 3,
              color: _theme.colors[0],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            l10n.transcribing,
            style: const TextStyle(color: Colors.white, fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.sendingAudio,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
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
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.greenAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.result,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _editing ? _finishEdit : _startEdit,
                child: Icon(
                  _editing ? Icons.check_rounded : Icons.edit_rounded,
                  size: 20,
                  color: _editing ? Colors.greenAccent : Colors.white38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _theme.surfaceColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: _editing
                  ? TextField(
                      controller: _editCtrl,
                      maxLines: null,
                      expands: true,
                      autofocus: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.65,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    )
                  : SingleChildScrollView(
                      child: SelectableText(
                        _resultText ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.65,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_correcting || _corrected || _editing) ? null : _correctText,
              icon: _correcting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _theme.colors[0],
                      ),
                    )
                  : Icon(
                      _corrected
                          ? Icons.check_circle_outline
                          : Icons.auto_fix_high,
                      size: 18,
                    ),
              label: Text(
                _correcting
                    ? l10n.correcting
                    : (_corrected ? l10n.corrected : l10n.fixErrors),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    _corrected ? Colors.greenAccent : Colors.white70,
                side: BorderSide(
                  color: _corrected
                      ? Colors.greenAccent.withOpacity(0.4)
                      : Colors.white.withOpacity(0.2),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
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
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  showTranslateSheet(context, _resultText ?? ''),
              icon: const Icon(Icons.translate, size: 18),
              label: Text(l10n.translateBtn),
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
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: _resultText ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.copied),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(l10n.copy),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _theme.colors[0],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Share.share(_resultText ?? ''),
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: Text(l10n.shareText),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
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
                _seconds = 0;
                _historyItemId = null;
                _corrected = false;
                _editing = false;
              }),
              icon: const Icon(Icons.mic, size: 18),
              label: Text(l10n.again),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.resolveApiError(_errorMessage),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 13,
                height: 1.5,
              ),
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

class _SpeechLangPicker extends StatelessWidget {
  final (String, String) selected;
  final void Function((String, String)) onPick;

  const _SpeechLangPicker({required this.selected, required this.onPick});

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
              itemCount: kTranscriptionLanguages.length,
              itemBuilder: (_, i) {
                final lang = kTranscriptionLanguages[i];
                final isSelected = lang.$1 == selected.$1;
                final displayName =
                    lang.$1.isEmpty ? l10n.langAuto : lang.$2;
                return ListTile(
                  title: Text(displayName,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: lang.$1.isEmpty
                      ? null
                      : Text(lang.$1,
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
