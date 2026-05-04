import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/history_item.dart';
import '../providers/app_state.dart';
import '../services/history_service.dart';
import '../services/openai_service.dart';
import '../services/telegram_service.dart';
import '../services/transform_presets_service.dart';

enum _TSState { idle, loading, result, error }

void showTransformSheet(BuildContext context, String sourceText) {
  final theme = context.read<AppState>().buttonTheme;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TransformSheet(sourceText: sourceText),
  );
}

class _TransformSheet extends StatefulWidget {
  final String sourceText;
  const _TransformSheet({required this.sourceText});

  @override
  State<_TransformSheet> createState() => _TransformSheetState();
}

class _TransformSheetState extends State<_TransformSheet> {
  final _ctrl = TextEditingController();
  _TSState _state = _TSState.idle;
  String? _result;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _transform() async {
    final instruction = _ctrl.text.trim();
    if (instruction.isEmpty) return;
    setState(() {
      _state = _TSState.loading;
      _result = null;
      _error = null;
    });
    final appState = context.read<AppState>();
    try {
      final result = await OpenAIService(appState.apiKey)
          .transformText(widget.sourceText, instruction);
      if (mounted) {
        context.read<HistoryService>().add(HistoryItem(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              type: HistoryType.transform,
              createdAt: DateTime.now(),
              result: result,
              original: widget.sourceText,
            ));
        context.read<TelegramService>().sendResult(
          type: HistoryType.transform,
          result: result,
          original: widget.sourceText,
        );
        setState(() { _state = _TSState.result; _result = result; });
      }
    } catch (e) {
      if (mounted) setState(() {
        _state = _TSState.error;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = appState.buttonTheme;
    final l10n = appState.l10n;
    return switch (_state) {
      _TSState.idle => _buildIdle(theme, l10n),
      _TSState.loading => _buildLoading(theme, l10n),
      _TSState.result => _buildResult(theme, l10n),
      _TSState.error => _buildError(theme, l10n),
    };
  }

  Widget _buildIdle(theme, l10n) {
    final mq = MediaQuery.of(context);
    final presets = context.watch<TransformPresetsService>();
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, mq.viewInsets.bottom + mq.viewPadding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Handle(),
          const SizedBox(height: 14),
          Text(l10n.transformText,
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
          if (presets.presets.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: presets.presets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final text = presets.presets[i];
                  final label = text.length > 30
                      ? '${text.substring(0, 30)}…'
                      : text;
                  return InputChip(
                    label: Text(label,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    onPressed: () {
                      _ctrl.text = text;
                      _ctrl.selection = TextSelection.collapsed(
                          offset: text.length);
                    },
                    deleteIcon: const Icon(Icons.close,
                        size: 14, color: Colors.white38),
                    onDeleted: () => presets.delete(text),
                    backgroundColor: Colors.white.withOpacity(0.08),
                    side: BorderSide(
                        color: Colors.white.withOpacity(0.2)),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            minLines: 2,
            autofocus: true,
            textInputAction: TextInputAction.done,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: l10n.transformHint,
              hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.3), fontSize: 13),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _ctrl,
            builder: (_, value, __) {
              final text = value.text.trim();
              final alreadySaved = presets.contains(text);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: text.isEmpty ? null : _transform,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: Text(l10n.transformBtn),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colors[0],
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            theme.colors[0].withOpacity(0.35),
                        disabledForegroundColor: Colors.white38,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  if (text.isNotEmpty && !alreadySaved) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () => presets.add(text),
                        icon: const Icon(Icons.bookmark_add_outlined,
                            size: 16),
                        label: Text(l10n.saveAsPreset),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white38,
                          padding:
                              const EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
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
          Text(l10n.transforming,
              style:
                  const TextStyle(color: Colors.white, fontSize: 15)),
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
          Text(l10n.result,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
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
                    Clipboard.setData(
                        ClipboardData(text: _result ?? ''));
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
                    side: BorderSide(
                        color: Colors.white.withOpacity(0.3)),
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
                  setState(() { _state = _TSState.idle; _result = null; }),
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
          const Icon(Icons.error_outline,
              color: Colors.redAccent, size: 48),
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
                setState(() { _state = _TSState.idle; _error = null; }),
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
