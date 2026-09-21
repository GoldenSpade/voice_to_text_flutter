import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_theme.dart';
import '../models/history_item.dart';
import '../models/transcription_languages.dart';
import '../models/translation_languages.dart';
import '../providers/app_state.dart';
import '../services/history_service.dart';
import '../services/openai_service.dart';
import '../services/telegram_service.dart';
import 'transform_sheet.dart';
import '../widgets/waveform_widget.dart';

enum _Stage { idle, recording, transcribing, translating, generating, result, error }

const _kVoices = <(String, String)>[
  ('alloy', 'Neutral, versatile'),
  ('ash', 'Soft, warm'),
  ('coral', 'Friendly, positive'),
  ('echo', 'Confident, authoritative'),
  ('fable', 'British accent, expressive'),
  ('onyx', 'Deep, authoritative'),
  ('nova', 'Energetic, female'),
  ('sage', 'Calm, wise'),
  ('shimmer', 'Light, expressive'),
];

class FullCycleScreen extends StatefulWidget {
  const FullCycleScreen({super.key});

  @override
  State<FullCycleScreen> createState() => _FullCycleScreenState();
}

class _FullCycleScreenState extends State<FullCycleScreen>
    with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();

  _Stage _stage = _Stage.idle;
  var _language = kTranslationLanguages[0];
  var _voice = _kVoices[0];
  var _speechLang = kTranscriptionLanguages[0];

  String? _originalText;
  String? _translatedText;
  String? _audioPath;
  String? _errorMessage;
  String? _historyItemId;
  final _editOrigCtrl = TextEditingController();
  bool _editingOriginal = false;
  bool _isPlaying = false;
  late AppButtonTheme _theme;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  StreamSubscription<PlayerState>? _playerSub;
  final List<double> _waveData = [];
  StreamSubscription<Amplitude>? _amplitudeSub;
  String? _recordingPath;
  double _fileSizeMb = 0;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _playerSub = _player.playerStateStream.listen((s) {
      if (!mounted) return;
      if (s.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
        setState(() => _isPlaying = false);
      } else {
        setState(() => _isPlaying = s.playing);
      }
    });
    SharedPreferences.getInstance().then((prefs) {
      final langIdx = (prefs.getInt('pref_fc_lang') ?? 0)
          .clamp(0, kTranslationLanguages.length - 1);
      final voiceIdx = (prefs.getInt('pref_fc_voice') ?? 0)
          .clamp(0, _kVoices.length - 1);
      final speechIdx = (prefs.getInt('pref_fc_speech_lang') ?? 0)
          .clamp(0, kTranscriptionLanguages.length - 1);
      if (mounted) setState(() {
        _language = kTranslationLanguages[langIdx];
        _voice = _kVoices[voiceIdx];
        _speechLang = kTranscriptionLanguages[speechIdx];
      });
    });
  }

  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _pulseCtrl.dispose();
    _editOrigCtrl.dispose();
    _playerSub?.cancel();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(context.read<AppState>().l10n.noMicPermission)),
        );
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/fc_${DateTime.now().millisecondsSinceEpoch}.m4a';
    HapticFeedback.mediumImpact();
    await _recorder.start(
      RecordConfig(
          encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
      path: path,
    );

    _recordingPath = path;
    _fileSizeMb = 0;
    _isPaused = false;
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

    _pulseCtrl.repeat(reverse: true);
    setState(() => _stage = _Stage.recording);
  }

  Future<void> _stopAndProcess() async {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    _isPaused = false;
    HapticFeedback.lightImpact();
    final recPath = await _recorder.stop();
    if (recPath == null || !mounted) return;

    final apiKey = context.read<AppState>().apiKey;
    final svc = OpenAIService(apiKey);

    final speechLangCode = _speechLang.$1.isEmpty ? null : _speechLang.$1;

    setState(() => _stage = _Stage.transcribing);
    String original;
    try {
      original = await svc.transcribeAudio(recPath, language: speechLangCode);
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
      return;
    }
    if (!mounted) return;

    setState(() => _stage = _Stage.translating);
    String translated;
    try {
      translated = await svc.translateText(original, _language.$3);
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
      return;
    }
    if (!mounted) return;

    setState(() => _stage = _Stage.generating);
    String audioPath;
    try {
      final dir = await getTemporaryDirectory();
      audioPath =
          '${dir.path}/fc_tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
      await svc.textToSpeech(translated, _voice.$1, audioPath);
      await _player.setFilePath(audioPath);
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
      return;
    }
    if (!mounted) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    context.read<HistoryService>().add(HistoryItem(
          id: id,
          type: HistoryType.fullCycle,
          createdAt: DateTime.now(),
          original: original,
          result: translated,
          languageName: _language.$2,
          voiceName: _voice.$1,
          audioFilePath: audioPath,
        ));
    context.read<TelegramService>().sendAudioResult(
      audioPath,
      caption: '🔄 ${_language.$2}\n\n$translated',
    );

    setState(() {
      _stage = _Stage.result;
      _originalText = original;
      _translatedText = translated;
      _audioPath = audioPath;
      _historyItemId = id;
    });
  }

  Future<void> _pauseRecording() async {
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    HapticFeedback.lightImpact();
    await _recorder.pause();
    setState(() => _isPaused = true);
  }

  Future<void> _resumeRecording() async {
    HapticFeedback.mediumImpact();
    await _recorder.resume();
    _pulseCtrl.repeat(reverse: true);
    setState(() => _isPaused = false);
  }

  Future<void> _pickAndProcess() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null || !mounted) return;

    final recPath = result.files.single.path!;
    final apiKey = context.read<AppState>().apiKey;
    final svc = OpenAIService(apiKey);
    final speechLangCode = _speechLang.$1.isEmpty ? null : _speechLang.$1;

    setState(() => _stage = _Stage.transcribing);
    String original;
    try {
      original = await svc.transcribeAudio(recPath, language: speechLangCode);
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
      return;
    }
    if (!mounted) return;

    setState(() => _stage = _Stage.translating);
    String translated;
    try {
      translated = await svc.translateText(original, _language.$3);
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
      return;
    }
    if (!mounted) return;

    setState(() => _stage = _Stage.generating);
    String audioPath;
    try {
      final dir = await getTemporaryDirectory();
      audioPath =
          '${dir.path}/fc_tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
      await svc.textToSpeech(translated, _voice.$1, audioPath);
      await _player.setFilePath(audioPath);
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
      return;
    }
    if (!mounted) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    context.read<HistoryService>().add(HistoryItem(
          id: id,
          type: HistoryType.fullCycle,
          createdAt: DateTime.now(),
          original: original,
          result: translated,
          languageName: _language.$2,
          voiceName: _voice.$1,
          audioFilePath: audioPath,
        ));
    context.read<TelegramService>().sendAudioResult(
      audioPath,
      caption: '🔄 ${_language.$2}\n\n$translated',
    );

    setState(() {
      _stage = _Stage.result;
      _originalText = original;
      _translatedText = translated;
      _audioPath = audioPath;
      _historyItemId = id;
    });
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  Future<void> _download(String savedLabel) async {
    if (_audioPath == null) return;
    try {
      final dir = await _resolveDownloadsDir();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final name = 'full_${_voice.$1}_$ts.mp3';
      await File(_audioPath!).copy('${dir.path}/$name');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('$savedLabel: $name'),
              duration: const Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(e.toString().replaceFirst('Exception: ', '')),
              duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  Future<Directory> _resolveDownloadsDir() async {
    const androidDownloads = '/storage/emulated/0/Download';
    if (Directory(androidDownloads).existsSync()) {
      return Directory(androidDownloads);
    }
    final d = await getDownloadsDirectory();
    if (d != null) return d;
    return getApplicationDocumentsDirectory();
  }

  Future<void> _share() async {
    if (_audioPath == null) return;
    await Share.shareXFiles([XFile(_audioPath!)]);
  }

  void _reset() {
    _player.stop();
    setState(() {
      _stage = _Stage.idle;
      _originalText = null;
      _translatedText = null;
      _audioPath = null;
      _errorMessage = null;
      _isPlaying = false;
      _historyItemId = null;
      _editingOriginal = false;
    });
  }

  void _startEditOriginal() {
    _editOrigCtrl.text = _originalText ?? '';
    setState(() => _editingOriginal = true);
  }

  void _finishEditOriginal() {
    final newText = _editOrigCtrl.text;
    setState(() {
      _originalText = newText;
      _editingOriginal = false;
    });
    if (_historyItemId != null) {
      context.read<HistoryService>().updateOriginal(_historyItemId!, newText);
    }
  }

  void _showSpeechLanguagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _theme.surfaceColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SpeechLangPicker(
        selected: _speechLang,
        onPick: (lang) {
          final idx = kTranscriptionLanguages.indexOf(lang);
          SharedPreferences.getInstance()
              .then((p) => p.setInt('pref_fc_speech_lang', idx));
          setState(() => _speechLang = lang);
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _LanguagePicker(
        selected: _language,
        onPick: (lang) {
          final idx = kTranslationLanguages.indexOf(lang);
          SharedPreferences.getInstance()
              .then((p) => p.setInt('pref_fc_lang', idx));
          setState(() => _language = lang);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showVoicePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _theme.surfaceColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _VoicePicker(
        selected: _voice,
        onPick: (v) {
          final idx = _kVoices.indexOf(v);
          SharedPreferences.getInstance()
              .then((p) => p.setInt('pref_fc_voice', idx));
          setState(() => _voice = v);
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
        title: Text(l10n.fullCycle),
        backgroundColor: _theme.appBarColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(child: _buildBody(l10n)),
    );
  }

  Widget _buildBody(l10n) => switch (_stage) {
        _Stage.idle => _buildIdle(l10n),
        _Stage.recording => _buildRecording(l10n),
        _Stage.transcribing =>
          _buildProcessing(l10n, l10n.transcribing, l10n.sendingAudio, 1),
        _Stage.translating =>
          _buildProcessing(l10n, l10n.translating, l10n.sendingText, 2),
        _Stage.generating =>
          _buildProcessing(l10n, l10n.generating, l10n.sendingForSpeech, 3),
        _Stage.result => _buildResult(l10n),
        _Stage.error => _buildError(l10n),
      };

  Widget _buildIdle(l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        children: [
          _SelectorCard(
            icon: Icons.mic_none,
            label: '${l10n.speechLanguage}:',
            value: _speechLang.$1.isEmpty ? l10n.langAuto : _speechLang.$2,
            surfaceColor: _theme.surfaceColor,
            onTap: _showSpeechLanguagePicker,
          ),
          const SizedBox(height: 10),
          _SelectorCard(
            icon: Icons.translate,
            label: '${l10n.selectLanguage}:',
            value: _language.$2,
            surfaceColor: _theme.surfaceColor,
            onTap: _showLanguagePicker,
          ),
          const SizedBox(height: 10),
          _SelectorCard(
            icon: Icons.record_voice_over,
            label: '${l10n.selectVoice}:',
            value: '${_voice.$1}  ·  ${_voice.$2}',
            surfaceColor: _theme.surfaceColor,
            onTap: _showVoicePicker,
          ),
          const Spacer(),
          GestureDetector(
            onTap: _startRecording,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: _theme.colors[0],
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _theme.colors[0].withOpacity(0.45),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.mic, color: Colors.white, size: 44),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.tapToRecord,
            style:
                TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.fullCycleSub,
            style:
                TextStyle(color: Colors.white.withOpacity(0.28), fontSize: 12),
          ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickAndProcess,
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
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildRecording(l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          WaveformWidget(data: _waveData, color: Colors.redAccent, height: 56),
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
                  width: 64,
                  height: 64,
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
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              ScaleTransition(
                scale: _isPaused
                    ? AlwaysStoppedAnimation<double>(1.0)
                    : _pulseAnim,
                child: GestureDetector(
                  onTap: _stopAndProcess,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent
                              .withOpacity(_isPaused ? 0.2 : 0.5),
                          blurRadius: 28,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.stop_rounded,
                        color: Colors.white, size: 40),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            l10n.tapToStop,
            style: TextStyle(
              color: _isPaused
                  ? Colors.amber.withOpacity(0.7)
                  : Colors.white.withOpacity(0.45),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessing(l10n, String title, String subtitle, int step) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
                style:
                    const TextStyle(color: Colors.white, fontSize: 17)),
            const SizedBox(height: 8),
            Text(subtitle,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: i + 1 == step ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i < step
                        ? _theme.colors[0]
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.original,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _editingOriginal ? _finishEditOriginal : _startEditOriginal,
                child: Icon(
                  _editingOriginal ? Icons.check_rounded : Icons.edit_rounded,
                  size: 16,
                  color: _editingOriginal ? Colors.greenAccent : Colors.white38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _theme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _editingOriginal
                ? TextField(
                    controller: _editOrigCtrl,
                    maxLines: null,
                    autofocus: true,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14, height: 1.5),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  )
                : SelectableText(
                    _originalText ?? '',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14, height: 1.5),
                  ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                l10n.translation,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              _Badge(_language.$2),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _theme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              _translatedText ?? '',
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, height: 1.5),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.record_voice_over,
                  color: Colors.white38, size: 15),
              const SizedBox(width: 6),
              Text(_voice.$1,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 13)),
              const SizedBox(width: 4),
              Text('· ${_voice.$2}',
                  style: const TextStyle(
                      color: Colors.white30, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _togglePlay,
              icon: Icon(
                _isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 22,
              ),
              label: Text(
                _isPlaying ? l10n.pause : l10n.play,
                style: const TextStyle(fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _theme.colors[0],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _download(l10n.saved),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(l10n.download),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                        color: Colors.white.withOpacity(0.3)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: Text(l10n.share),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                        color: Colors.white.withOpacity(0.3)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _CopyButton(
                    label: l10n.copyOriginal,
                    text: _originalText ?? ''),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CopyButton(
                    label: l10n.copyTranslation,
                    text: _translatedText ?? ''),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Share.share(_originalText ?? ''),
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
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Share.share(_translatedText ?? ''),
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
                  showTransformSheet(context, _translatedText ?? ''),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(l10n.transformText),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withOpacity(0.2)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.again),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 12),
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
                _stage = _Stage.idle;
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

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SelectorCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color surfaceColor;
  final VoidCallback onTap;

  const _SelectorCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.surfaceColor,
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
            Icon(icon, color: Colors.white54, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style:
                    const TextStyle(color: Colors.white, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                color: Colors.white.withOpacity(0.3), size: 14),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
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
}

class _CopyButton extends StatelessWidget {
  final String label;
  final String text;

  const _CopyButton({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = context.read<AppState>().buttonTheme;
    return ElevatedButton.icon(
      onPressed: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.read<AppState>().l10n.copied),
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

// ── Bottom sheet pickers ──────────────────────────────────────────────────────

class _LanguagePicker extends StatelessWidget {
  final (String, String, String) selected;
  final void Function((String, String, String)) onPick;

  const _LanguagePicker({required this.selected, required this.onPick});

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
              itemCount: kTranslationLanguages.length,
              itemBuilder: (_, i) {
                final lang = kTranslationLanguages[i];
                final isSelected = lang.$1 == selected.$1;
                return ListTile(
                  title: Text(lang.$2,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(l10n.languageName(lang.$1),
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

class _VoicePicker extends StatelessWidget {
  final (String, String) selected;
  final void Function((String, String)) onPick;

  const _VoicePicker({required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = context.read<AppState>().buttonTheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
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
              itemCount: _kVoices.length,
              itemBuilder: (_, i) {
                final v = _kVoices[i];
                final isSelected = v.$1 == selected.$1;
                return ListTile(
                  title: Text(v.$1,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(v.$2,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                  trailing: isSelected
                      ? Icon(Icons.check, color: theme.colors[0])
                      : null,
                  tileColor: isSelected
                      ? theme.colors[0].withOpacity(0.15)
                      : null,
                  onTap: () => onPick(v),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeechLangPicker extends StatelessWidget {
  final (String, String, String) selected;
  final void Function((String, String, String)) onPick;

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
                      : Text(l10n.languageName(lang.$1),
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
