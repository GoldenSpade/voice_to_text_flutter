import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/app_theme.dart';
import '../models/history_item.dart';
import '../providers/app_state.dart';
import '../services/history_service.dart';
import '../services/openai_service.dart';
import '../services/telegram_service.dart';

enum _State { idle, generating, ready, error }

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

class TtsScreen extends StatefulWidget {
  const TtsScreen({super.key});

  @override
  State<TtsScreen> createState() => _TtsScreenState();
}

class _TtsScreenState extends State<TtsScreen> {
  final _controller = TextEditingController();
  final _player = AudioPlayer();
  _State _state = _State.idle;
  String? _filePath;
  String? _errorMessage;
  var _voice = _kVoices[0];
  bool _isPlaying = false;
  StreamSubscription<PlayerState>? _playerSub;
  late AppButtonTheme _theme;

  @override
  void initState() {
    super.initState();
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
      final idx = (prefs.getInt('pref_tts_voice') ?? 0)
          .clamp(0, _kVoices.length - 1);
      if (mounted) setState(() => _voice = _kVoices[idx]);
    });
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _player.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (_isPlaying) await _player.stop();

    setState(() {
      _state = _State.generating;
      _filePath = null;
      _errorMessage = null;
    });

    final appState = context.read<AppState>();
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3';

      await OpenAIService(appState.apiKey).textToSpeech(text, _voice.$1, path);
      await _player.setFilePath(path);

      if (mounted) {
        context.read<HistoryService>().add(HistoryItem(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              type: HistoryType.tts,
              createdAt: DateTime.now(),
              result: text,
              voiceName: _voice.$1,
              audioFilePath: path,
            ));
        context.read<TelegramService>().sendAudioResult(
          path,
          caption: '📢 ${_voice.$1}\n\n$text',
        );
        setState(() {
          _state = _State.ready;
          _filePath = path;
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
    if (_filePath == null) return;
    try {
      final dir = await _resolveDownloadsDir();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final name = 'tts_${_voice.$1}_$ts.mp3';
      await File(_filePath!).copy('${dir.path}/$name');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$savedLabel: $name'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            duration: const Duration(seconds: 3),
          ),
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

  void _showVoicePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _VoicePicker(
        selected: _voice,
        onPick: (v) {
          final idx = _kVoices.indexOf(v);
          SharedPreferences.getInstance()
              .then((p) => p.setInt('pref_tts_voice', idx));
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
        title: Text(l10n.textToVoice),
        backgroundColor: _theme.appBarColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(child: _buildBody(l10n)),
    );
  }

  Widget _buildBody(l10n) {
    return switch (_state) {
      _State.idle => _buildIdle(l10n),
      _State.generating => _buildGenerating(l10n),
      _State.ready => _buildReady(l10n),
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
                hintText: l10n.enterTextToSpeak,
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
          const SizedBox(height: 16),
          InkWell(
            onTap: _showVoicePicker,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _theme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.record_voice_over,
                      color: Colors.white54, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    '${l10n.selectVoice}:',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _voice.$1,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '· ${_voice.$2}',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
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
                onPressed:
                    value.text.trim().isEmpty ? null : _generate,
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
                child: Text(l10n.generateSpeech,
                    style: const TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerating(l10n) {
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
          Text(l10n.generating,
              style:
                  const TextStyle(color: Colors.white, fontSize: 17)),
          const SizedBox(height: 8),
          Text(l10n.sendingForSpeech,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildReady(l10n) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.result,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
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
                      color: Colors.white, fontSize: 14, height: 1.6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.record_voice_over,
                  color: Colors.white38, size: 16),
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
          Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _togglePlay,
                  icon: Icon(
                    _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 22,
                  ),
                  label: Text(_isPlaying ? l10n.pause : l10n.play),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _theme.colors[0],
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _download(l10n.saved),
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: Text(l10n.download),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                        color: Colors.white.withOpacity(0.3)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await _player.stop();
                setState(() {
                  _state = _State.idle;
                  _filePath = null;
                  _isPlaying = false;
                });
              },
              icon: const Icon(Icons.volume_up, size: 18),
              label: Text(l10n.again),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(
                    color: Colors.white.withOpacity(0.3)),
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
