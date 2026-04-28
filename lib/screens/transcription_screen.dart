import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import '../models/app_theme.dart';
import '../models/history_item.dart';
import '../providers/app_state.dart';
import '../services/history_service.dart';
import '../services/openai_service.dart';

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
  Timer? _timer;
  int _seconds = 0;
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
    if (widget.initialFilePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _transcribeFromPath(widget.initialFilePath!);
      });
    }
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

    setState(() => _state = _State.processing);

    final appState = context.read<AppState>();
    try {
      final text =
          await OpenAIService(appState.apiKey).transcribeAudio(path);
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

  Future<void> _transcribeFromPath(String path) async {
    setState(() {
      _state = _State.processing;
      _resultText = null;
      _errorMessage = null;
      _corrected = false;
    });
    final appState = context.read<AppState>();
    try {
      final text =
          await OpenAIService(appState.apiKey).transcribeAudio(path);
      if (mounted) {
        final id = DateTime.now().millisecondsSinceEpoch.toString();
        context.read<HistoryService>().add(HistoryItem(
              id: id,
              type: HistoryType.transcription,
              createdAt: DateTime.now(),
              result: text,
            ));
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
            content:
                Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
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
                child: const Icon(
                  Icons.stop_rounded,
                  color: Colors.white,
                  size: 56,
                ),
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
              color: Colors.white.withOpacity(0.55),
              fontSize: 14,
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
              Text(
                l10n.result,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
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
              child: SingleChildScrollView(
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
              onPressed: (_correcting || _corrected) ? null : _correctText,
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
                    _corrected ? Colors.greenAccent : _theme.colors[0],
                side: BorderSide(
                  color: _corrected
                      ? Colors.greenAccent.withOpacity(0.4)
                      : _theme.colors[0].withOpacity(0.5),
                ),
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
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _state = _State.idle;
                    _resultText = null;
                    _seconds = 0;
                    _historyItemId = null;
                    _corrected = false;
                  }),
                  icon: const Icon(Icons.mic, size: 18),
                  label: Text(l10n.again),
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
              _errorMessage ?? l10n.unknownError,
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
