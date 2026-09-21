import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_theme.dart';
import '../models/history_item.dart';
import '../models/translation_languages.dart';
import '../providers/app_state.dart';
import '../services/history_service.dart';
import '../services/openai_service.dart';
import '../widgets/waveform_widget.dart';

enum _ConvState { idle, recording, processing, playing }

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

class _Turn {
  final bool isA;
  final String original;
  final String translated;
  final String audioPath;
  const _Turn({
    required this.isA,
    required this.original,
    required this.translated,
    required this.audioPath,
  });
}

class ConversationScreen extends StatefulWidget {
  final HistoryItem? initialItem;
  const ConversationScreen({super.key, this.initialItem});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _scroll = ScrollController();

  _ConvState _state = _ConvState.idle;
  bool _isA = true;

  var _langA = kTranslationLanguages[0];
  var _langB = kTranslationLanguages[1];
  var _voiceA = _kVoices[0]; // alloy
  var _voiceB = _kVoices[6]; // nova

  final List<_Turn> _turns = [];
  final List<double> _waveData = [];
  StreamSubscription<Amplitude>? _ampSub;
  StreamSubscription<PlayerState>? _playerSub;
  String? _status;
  int? _playingTurnIdx;
  HistoryService? _historySvc;
  String? _existingItemId;
  int _initialTurnCount = 0;

  late AppButtonTheme _theme;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _playerSub = _player.playerStateStream.listen((s) {
      if (!mounted) return;
      if (s.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
        if (mounted) setState(() {
          _state = _ConvState.idle;
          _playingTurnIdx = null;
        });
      }
    });
    if (widget.initialItem != null) {
      _restoreFromItem(widget.initialItem!);
    }

    SharedPreferences.getInstance().then((prefs) {
      final aIdx = (prefs.getInt('pref_conv_a') ?? 0)
          .clamp(0, kTranslationLanguages.length - 1);
      final bIdx = (prefs.getInt('pref_conv_b') ?? 1)
          .clamp(0, kTranslationLanguages.length - 1);
      final vaIdx = (prefs.getInt('pref_conv_voice_a') ?? 0)
          .clamp(0, _kVoices.length - 1);
      final vbIdx = (prefs.getInt('pref_conv_voice_b') ?? 6)
          .clamp(0, _kVoices.length - 1);
      if (mounted) {
        setState(() {
          if (widget.initialItem == null) {
            _langA = kTranslationLanguages[aIdx];
            _langB = kTranslationLanguages[bIdx];
          }
          _voiceA = _kVoices[vaIdx];
          _voiceB = _kVoices[vbIdx];
        });
      }
    });
  }

  void _restoreFromItem(HistoryItem item) {
    _existingItemId = item.id;
    try {
      final data = jsonDecode(item.result) as Map<String, dynamic>;
      final langAName = data['langAName'] as String? ?? '';
      final langBName = data['langBName'] as String? ?? '';
      _langA = kTranslationLanguages.firstWhere(
        (l) => l.$2 == langAName,
        orElse: () => kTranslationLanguages[0],
      );
      _langB = kTranslationLanguages.firstWhere(
        (l) => l.$2 == langBName,
        orElse: () => kTranslationLanguages[1],
      );
      for (final t in (data['turns'] as List)) {
        final map = t as Map<String, dynamic>;
        _turns.add(_Turn(
          isA: map['isA'] as bool,
          original: map['original'] as String? ?? '',
          translated: map['translated'] as String? ?? '',
          audioPath: map['audioPath'] as String? ?? '',
        ));
      }
      _initialTurnCount = _turns.length;
    } catch (_) {}
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _historySvc ??= context.read<HistoryService>();
  }

  @override
  void dispose() {
    _saveConversation();
    _ampSub?.cancel();
    _pulseCtrl.dispose();
    _playerSub?.cancel();
    _player.dispose();
    _recorder.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _saveConversation() {
    if (_historySvc == null) return;
    if (_existingItemId != null && _turns.length <= _initialTurnCount) return;
    if (_turns.isEmpty) return;
    final json = jsonEncode({
      'langAName': _langA.$2,
      'langBName': _langB.$2,
      'turns': _turns
          .map((t) => {
                'isA': t.isA,
                'original': t.original,
                'translated': t.translated,
                'audioPath': t.audioPath,
              })
          .toList(),
    });
    if (_existingItemId != null) {
      _historySvc!.updateResult(_existingItemId!, json);
    } else {
      _historySvc!.add(HistoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: HistoryType.conversation,
        createdAt: DateTime.now(),
        result: json,
        languageName: '${_langA.$2} ↔ ${_langB.$2}',
      ));
    }
  }

  Future<void> _startRecording(bool isA) async {
    final l10n = context.read<AppState>().l10n;
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.noMicPermission)),
        );
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/conv_${DateTime.now().millisecondsSinceEpoch}.m4a';

    HapticFeedback.mediumImpact();
    await _recorder.start(
      const RecordConfig(
          encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
      path: path,
    );

    _waveData.clear();
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((amp) {
      if (!mounted) return;
      final norm = ((amp.current.clamp(-60.0, 0.0) + 60.0) / 60.0);
      setState(() => _waveData.add(norm));
    });

    _pulseCtrl.repeat(reverse: true);
    setState(() {
      _state = _ConvState.recording;
      _isA = isA;
    });
  }

  Future<void> _stopRecording() async {
    _ampSub?.cancel();
    _ampSub = null;
    _pulseCtrl.stop();
    _pulseCtrl.reset();

    HapticFeedback.lightImpact();
    final path = await _recorder.stop();
    if (path == null || !mounted) return;
    await _process(path, _isA);
  }

  Future<void> _process(String path, bool isA) async {
    final fromLang = isA ? _langA : _langB;
    final toLang = isA ? _langB : _langA;
    final apiKey = context.read<AppState>().apiKey;
    final svc = OpenAIService(apiKey);
    final l10n = context.read<AppState>().l10n;

    setState(() {
      _state = _ConvState.processing;
      _status = l10n.transcribing;
    });

    String original;
    try {
      original = await svc.transcribeAudio(path);
      try {
        File(path).deleteSync();
      } catch (_) {}
    } catch (e) {
      try {
        File(path).deleteSync();
      } catch (_) {}
      if (mounted) {
        setState(() => _state = _ConvState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return;
    }
    if (!mounted) return;

    setState(() => _status = l10n.translating);

    String translated;
    try {
      translated = await svc.translateText(
        original,
        toLang.$3,
        sourceLanguage: fromLang.$3,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _state = _ConvState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return;
    }
    if (!mounted) return;

    setState(() => _status = l10n.generating);

    String audioPath;
    try {
      final dir = await getApplicationDocumentsDirectory();
      audioPath =
          '${dir.path}/conv_tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final voice = (isA ? _voiceA : _voiceB).$1;
      await svc.textToSpeech(translated, voice, audioPath);
      await _player.setFilePath(audioPath);
    } catch (e) {
      if (mounted) {
        setState(() => _state = _ConvState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return;
    }
    if (!mounted) return;

    final turnIdx = _turns.length;
    setState(() {
      _turns.add(_Turn(
        isA: isA,
        original: original,
        translated: translated,
        audioPath: audioPath,
      ));
      _state = _ConvState.playing;
      _playingTurnIdx = turnIdx;
      _status = null;
    });

    _scrollToBottom();
    await _player.play();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _replayTurn(int idx) async {
    final path = _turns[idx].audioPath;
    if (!File(path).existsSync()) return;
    if (_state == _ConvState.playing) {
      await _player.stop();
      if (_playingTurnIdx == idx) {
        setState(() {
          _state = _ConvState.idle;
          _playingTurnIdx = null;
        });
        return;
      }
    }
    await _player.setFilePath(path);
    setState(() {
      _state = _ConvState.playing;
      _playingTurnIdx = idx;
    });
    await _player.play();
  }

  void _pickLang(bool isA) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LangPicker(
        selected: isA ? _langA : _langB,
        onPick: (lang) {
          final idx = kTranslationLanguages.indexOf(lang);
          SharedPreferences.getInstance().then(
              (p) => p.setInt(isA ? 'pref_conv_a' : 'pref_conv_b', idx));
          setState(() {
            if (isA) {
              _langA = lang;
            } else {
              _langB = lang;
            }
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  void _pickVoice(bool isA) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _VoicePicker(
        selected: isA ? _voiceA : _voiceB,
        onPick: (v) {
          final idx = _kVoices.indexOf(v);
          SharedPreferences.getInstance().then((p) =>
              p.setInt(isA ? 'pref_conv_voice_a' : 'pref_conv_voice_b', idx));
          setState(() {
            if (isA) {
              _voiceA = v;
            } else {
              _voiceB = v;
            }
          });
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
    final colors = _theme.colors;
    final colorA = colors[0];
    final colorB = colors.length > 1 ? colors[1] : colors[0];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.conversationTranslator),
        backgroundColor: _theme.appBarColor,
        foregroundColor: Colors.white,
        actions: [
          if (_turns.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: l10n.clearAll,
              onPressed: _state == _ConvState.idle
                  ? () => setState(() => _turns.clear())
                  : null,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LangChip(
                          lang: _langA,
                          color: colorA,
                          onTap: _state == _ConvState.idle
                              ? () => _pickLang(true)
                              : null,
                        ),
                        const SizedBox(height: 4),
                        _VoiceChip(
                          voice: _voiceA,
                          color: colorA,
                          onTap: _state == _ConvState.idle
                              ? () => _pickVoice(true)
                              : null,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 11, 8, 0),
                    child: const Icon(Icons.swap_horiz_rounded,
                        color: Colors.white38, size: 22),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LangChip(
                          lang: _langB,
                          color: colorB,
                          onTap: _state == _ConvState.idle
                              ? () => _pickLang(false)
                              : null,
                        ),
                        const SizedBox(height: 4),
                        _VoiceChip(
                          voice: _voiceB,
                          color: colorB,
                          onTap: _state == _ConvState.idle
                              ? () => _pickVoice(false)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _turns.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.forum_outlined,
                              color: Color(0x1FFFFFFF), size: 64),
                          const SizedBox(height: 16),
                          Text(
                            l10n.conversationEmpty,
                            style: const TextStyle(
                                color: Color(0x3FFFFFFF), fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      itemCount: _turns.length,
                      itemBuilder: (_, i) => _TurnBubble(
                        turn: _turns[i],
                        index: i,
                        langA: _langA,
                        langB: _langB,
                        colorA: colorA,
                        colorB: colorB,
                        isPlaying: _playingTurnIdx == i,
                        canReplay: _state == _ConvState.idle ||
                            _state == _ConvState.playing,
                        onReplay: () => _replayTurn(i),
                      ),
                    ),
            ),
            if (_state == _ConvState.recording)
              WaveformWidget(
                data: _waveData,
                color: _isA ? colorA : colorB,
                height: 44,
              ),
            if (_state == _ConvState.processing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _theme.colors[0]),
                    ),
                    const SizedBox(width: 10),
                    Text(_status ?? '',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
            if (_state == _ConvState.playing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Icon(Icons.graphic_eq_rounded,
                    color: Color(0x4DFFFFFF), size: 26),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: _SpeakButton(
                      label: _langA.$2,
                      color: colorA,
                      isActive: _state == _ConvState.recording && _isA,
                      enabled: _state == _ConvState.idle ||
                          (_state == _ConvState.recording && _isA),
                      pulseAnim: _pulseAnim,
                      onTap: () {
                        if (_state == _ConvState.idle) {
                          _startRecording(true);
                        } else if (_state == _ConvState.recording && _isA) {
                          _stopRecording();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SpeakButton(
                      label: _langB.$2,
                      color: colorB,
                      isActive: _state == _ConvState.recording && !_isA,
                      enabled: _state == _ConvState.idle ||
                          (_state == _ConvState.recording && !_isA),
                      pulseAnim: _pulseAnim,
                      onTap: () {
                        if (_state == _ConvState.idle) {
                          _startRecording(false);
                        } else if (_state == _ConvState.recording && !_isA) {
                          _stopRecording();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _copy(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  final l10n = context.read<AppState>().l10n;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(l10n.copied),
      duration: const Duration(seconds: 1),
    ),
  );
}

class _TurnBubble extends StatelessWidget {
  final _Turn turn;
  final int index;
  final (String, String, String) langA;
  final (String, String, String) langB;
  final Color colorA;
  final Color colorB;
  final bool isPlaying;
  final bool canReplay;
  final VoidCallback onReplay;

  const _TurnBubble({
    required this.turn,
    required this.index,
    required this.langA,
    required this.langB,
    required this.colorA,
    required this.colorB,
    required this.isPlaying,
    required this.canReplay,
    required this.onReplay,
  });

  @override
  Widget build(BuildContext context) {
    final isA = turn.isA;
    final fromLang = isA ? langA : langB;
    final toLang = isA ? langB : langA;
    final color = isA ? colorA : colorB;

    return Align(
      alignment: isA ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: EdgeInsets.only(
          bottom: 10,
          left: isA ? 0 : 36,
          right: isA ? 36 : 0,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.13),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft:
                isA ? Radius.zero : const Radius.circular(14),
            bottomRight:
                isA ? const Radius.circular(14) : Radius.zero,
          ),
          border: Border.all(color: color.withOpacity(0.25), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  fromLang.$2,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _copy(context, turn.original),
                  child: Icon(Icons.copy_rounded,
                      size: 13, color: color.withOpacity(0.45)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              turn.original,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 8),
            Container(height: 0.5, color: Colors.white12),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.arrow_forward_rounded,
                    size: 10, color: Colors.white38),
                const SizedBox(width: 4),
                Text(
                  toLang.$2,
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      letterSpacing: 0.5),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _copy(context, turn.translated),
                  child: const Icon(Icons.copy_rounded,
                      size: 13, color: Colors.white24),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              turn.translated,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: canReplay ? onReplay : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isPlaying
                        ? color.withOpacity(0.25)
                        : color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    isPlaying
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                    size: 16,
                    color: isPlaying ? color : color.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeakButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isActive;
  final bool enabled;
  final Animation<double> pulseAnim;
  final VoidCallback onTap;

  const _SpeakButton({
    required this.label,
    required this.color,
    required this.isActive,
    required this.enabled,
    required this.pulseAnim,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: isActive
          ? pulseAnim
          : const AlwaysStoppedAnimation<double>(1.0),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.redAccent
                : (enabled ? color : color.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(14),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.redAccent.withOpacity(0.4),
                      blurRadius: 16,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                isActive ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 26,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final (String, String, String) lang;
  final Color color;
  final VoidCallback? onTap;

  const _LangChip({required this.lang, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                lang.$2,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down_rounded, color: color, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _LangPicker extends StatelessWidget {
  final (String, String, String) selected;
  final void Function((String, String, String)) onPick;

  const _LangPicker({required this.selected, required this.onPick});

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

class _VoiceChip extends StatelessWidget {
  final (String, String) voice;
  final Color color;
  final VoidCallback? onTap;

  const _VoiceChip({required this.voice, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.record_voice_over_rounded,
                color: color.withOpacity(0.65), size: 12),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                voice.$1,
                style: TextStyle(
                  color: color.withOpacity(0.8),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down_rounded,
                  color: color.withOpacity(0.5), size: 14),
            ],
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
      minChildSize: 0.35,
      maxChildSize: 0.85,
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
