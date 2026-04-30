import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import '../models/history_item.dart';
import '../providers/app_state.dart';
import '../services/backup_service.dart';
import '../services/history_service.dart';
import 'transform_sheet.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  HistoryType? _activeFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _export(AppLocalizations l10n, HistoryService svc) async {
    try {
      final name = await BackupService.export(svc);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.exportDone}: $name'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _import(AppLocalizations l10n) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.single.path == null) return;
    try {
      final count = await BackupService.import(
        result.files.single.path!,
        context.read<HistoryService>(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.importDone}: $count'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  List<HistoryItem> _filtered(List<HistoryItem> items) {
    var result = items.toList();
    if (_activeFilter != null) {
      result = result.where((e) => e.type == _activeFilter).toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result.where((e) {
        return e.result.toLowerCase().contains(q) ||
            (e.original?.toLowerCase().contains(q) ?? false);
      }).toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final theme = state.buttonTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        backgroundColor: theme.appBarColor,
        foregroundColor: Colors.white,
        actions: [
          Consumer<HistoryService>(
            builder: (context, svc, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  color: theme.surfaceColor,
                  onSelected: (v) {
                    if (v == 'export') _export(l10n, svc);
                    if (v == 'import') _import(l10n);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'export',
                      enabled: svc.items.isNotEmpty,
                      child: Row(
                        children: [
                          Icon(Icons.upload_rounded,
                              size: 20,
                              color: svc.items.isNotEmpty
                                  ? Colors.white70
                                  : Colors.white24),
                          const SizedBox(width: 12),
                          Text(l10n.exportHistory,
                              style: TextStyle(
                                  color: svc.items.isNotEmpty
                                      ? Colors.white
                                      : Colors.white38)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'import',
                      child: Row(
                        children: [
                          const Icon(Icons.download_rounded,
                              size: 20, color: Colors.white70),
                          const SizedBox(width: 12),
                          Text(l10n.importHistory,
                              style:
                                  const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (svc.items.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    tooltip: l10n.clearAll,
                    onPressed: () => _confirmClear(
                        context, svc, l10n, theme.surfaceColor),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: Consumer<HistoryService>(
        builder: (context, svc, _) {
          if (svc.items.isEmpty) return _buildEmpty(l10n);

          final filtered = _filtered(svc.items);

          return Column(
            children: [
              // ── Search bar ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: l10n.searchHint,
                    hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.3), fontSize: 14),
                    prefixIcon: const Icon(Icons.search,
                        color: Colors.white38, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: Colors.white38, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: theme.surfaceColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    isDense: true,
                  ),
                ),
              ),

              // ── Filter chips ────────────────────────────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    _FilterPill(
                      label: l10n.filterAll,
                      selected: _activeFilter == null,
                      color: theme.colors[0],
                      onTap: () => setState(() => _activeFilter = null),
                    ),
                    const SizedBox(width: 6),
                    ...HistoryType.values.map((type) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _FilterPill(
                            label: l10n.historyTypeLabel(type),
                            selected: _activeFilter == type,
                            color: type.color,
                            onTap: () => setState(() => _activeFilter =
                                _activeFilter == type ? null : type),
                          ),
                        )),
                  ],
                ),
              ),

              // ── List ────────────────────────────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? _buildNoResults(l10n)
                    : ListView.separated(
                        padding:
                            const EdgeInsets.only(top: 4, bottom: 100),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 4),
                        itemBuilder: (context, i) =>
                            _HistoryCard(item: filtered[i], service: svc),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history,
              size: 72, color: Colors.white.withOpacity(0.15)),
          const SizedBox(height: 16),
          Text(
            l10n.historyEmpty,
            style: TextStyle(
                color: Colors.white.withOpacity(0.4), fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.historyEmptySub,
            style: TextStyle(
                color: Colors.white.withOpacity(0.25), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off,
              size: 64, color: Colors.white.withOpacity(0.15)),
          const SizedBox(height: 16),
          Text(
            l10n.noResults,
            style: TextStyle(
                color: Colors.white.withOpacity(0.4), fontSize: 17),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, HistoryService svc,
      AppLocalizations l10n, Color surfaceColor) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text(l10n.clearHistoryTitle,
            style: const TextStyle(color: Colors.white)),
        content: Text(l10n.clearHistoryMsg,
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              svc.clear();
              Navigator.pop(context);
            },
            child: Text(l10n.delete,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

// ── Filter pill ───────────────────────────────────────────────────────────────

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(0.2)
              : Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.white.withOpacity(0.15),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : Colors.white54,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ── History card ──────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final HistoryItem item;
  final HistoryService service;

  const _HistoryCard({required this.item, required this.service});

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<AppState>().l10n;
    final theme = context.read<AppState>().buttonTheme;
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => service.delete(item.id),
      child: InkWell(
        onTap: () => _showDetail(context, l10n),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            color: theme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: item.type.color.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.type.icon,
                    color: item.type.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n.historyTypeLabel(item.type),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (item.languageName != null) ...[
                          const SizedBox(width: 6),
                          _Badge(item.languageName!),
                        ],
                        if (item.voiceName != null) ...[
                          const SizedBox(width: 6),
                          _Badge(item.voiceName!),
                        ],
                        if (item.audioFilePath != null) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.headphones,
                              size: 13, color: Colors.white38),
                        ],
                        const Spacer(),
                        Text(
                          _formatDate(item.createdAt),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.result,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: Colors.white.withOpacity(0.3)),
                splashRadius: 20,
                onPressed: () =>
                    _confirmDelete(context, l10n, theme.surfaceColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, AppLocalizations l10n) {
    final theme = context.read<AppState>().buttonTheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DetailSheet(
        item: item,
        service: service,
        l10n: l10n,
        outerContext: context,
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, AppLocalizations l10n, Color surfaceColor) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text(l10n.deleteRecordTitle,
            style: const TextStyle(color: Colors.white)),
        content: Text(l10n.deleteRecordMsg,
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              service.delete(item.id);
              Navigator.pop(context);
            },
            child: Text(l10n.delete,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    return '${dt.day} ${months[dt.month - 1]}, '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── Detail bottom sheet ───────────────────────────────────────────────────────

class _DetailSheet extends StatefulWidget {
  final HistoryItem item;
  final HistoryService service;
  final AppLocalizations l10n;
  final BuildContext outerContext;

  const _DetailSheet({
    required this.item,
    required this.service,
    required this.l10n,
    required this.outerContext,
  });

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  AudioPlayer? _player;
  bool _isPlaying = false;
  bool _audioReady = false;
  StreamSubscription<PlayerState>? _playerSub;

  late String _currentOriginal;
  late String _currentResult;
  final _editOrigCtrl = TextEditingController();
  final _editResultCtrl = TextEditingController();
  bool _editingOriginal = false;
  bool _editingResult = false;

  @override
  void initState() {
    super.initState();
    _currentOriginal = widget.item.original ?? '';
    _currentResult = widget.item.result;
    if (widget.item.audioFilePath != null) _initPlayer();
  }

  Future<void> _initPlayer() async {
    final path = widget.item.audioFilePath!;
    if (!File(path).existsSync()) return;

    _player = AudioPlayer();
    try {
      await _player!.setFilePath(path);
      _playerSub = _player!.playerStateStream.listen((s) {
        if (!mounted) return;
        if (s.processingState == ProcessingState.completed) {
          _player!.pause();
          _player!.seek(Duration.zero);
          setState(() => _isPlaying = false);
        } else {
          setState(() => _isPlaying = s.playing);
        }
      });
      if (mounted) setState(() => _audioReady = true);
    } catch (_) {
      _player?.dispose();
      _player = null;
    }
  }

  Future<void> _togglePlay() async {
    if (_player == null) return;
    if (_isPlaying) {
      await _player!.pause();
    } else {
      if (_player!.processingState == ProcessingState.completed) {
        await _player!.seek(Duration.zero);
      }
      await _player!.play();
    }
  }

  Future<void> _download() async {
    final path = widget.item.audioFilePath;
    if (path == null) return;
    try {
      final sourceFile = File(path);
      if (!sourceFile.existsSync()) return;
      final dir = await _resolveDownloadsDir();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final name = '${widget.item.voiceName ?? 'audio'}_$ts.mp3';
      await sourceFile.copy('${dir.path}/$name');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(widget.outerContext).showSnackBar(
          SnackBar(
            content: Text('${widget.l10n.saved}: $name'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(e.toString().replaceFirst('Exception: ', '')),
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

  Future<void> _share() async {
    final path = widget.item.audioFilePath;
    if (path == null) return;
    await Share.shareXFiles([XFile(path)]);
  }

  void _startEditOriginal() {
    _editOrigCtrl.text = _currentOriginal;
    setState(() => _editingOriginal = true);
  }

  void _finishEditOriginal() {
    final newText = _editOrigCtrl.text;
    setState(() { _currentOriginal = newText; _editingOriginal = false; });
    widget.service.updateOriginal(widget.item.id, newText);
  }

  void _startEditResult() {
    _editResultCtrl.text = _currentResult;
    setState(() => _editingResult = true);
  }

  void _finishEditResult() {
    final newText = _editResultCtrl.text;
    setState(() { _currentResult = newText; _editingResult = false; });
    widget.service.updateResult(widget.item.id, newText);
  }

  @override
  void dispose() {
    _editOrigCtrl.dispose();
    _editResultCtrl.dispose();
    _playerSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<AppState>().buttonTheme;
    final hasOriginal =
        widget.item.original != null && widget.item.original!.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: _audioReady ? 0.62 : 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
          20, 12, 20,
          24 + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(widget.item.type.icon,
                    color: widget.item.type.color, size: 22),
                const SizedBox(width: 10),
                Text(
                  widget.l10n.historyTypeLabel(widget.item.type),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.item.languageName != null) ...[
                  const SizedBox(width: 8),
                  _Badge(widget.item.languageName!),
                ],
                if (widget.item.voiceName != null) ...[
                  const SizedBox(width: 8),
                  _Badge(widget.item.voiceName!),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatDateFull(widget.item.createdAt),
              style:
                  const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const Divider(color: Colors.white12, height: 24),
            if (hasOriginal) ...[
              Row(children: [
                Expanded(child: Text(widget.l10n.original,
                    style: const TextStyle(color: Colors.white38, fontSize: 11,
                        fontWeight: FontWeight.w600, letterSpacing: 1))),
                GestureDetector(
                  onTap: _editingOriginal ? _finishEditOriginal : _startEditOriginal,
                  child: Icon(
                    _editingOriginal ? Icons.check_rounded : Icons.edit_rounded,
                    size: 16,
                    color: _editingOriginal ? Colors.greenAccent : Colors.white38,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              _editingOriginal
                  ? TextField(
                      controller: _editOrigCtrl,
                      maxLines: null,
                      autofocus: true,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 15, height: 1.6),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    )
                  : SelectableText(_currentOriginal,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 15, height: 1.6)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: Text(
                  widget.item.type == HistoryType.transform
                      ? widget.l10n.result
                      : widget.l10n.translation,
                  style: const TextStyle(color: Colors.white38, fontSize: 11,
                      fontWeight: FontWeight.w600, letterSpacing: 1),
                )),
                GestureDetector(
                  onTap: _editingResult ? _finishEditResult : _startEditResult,
                  child: Icon(
                    _editingResult ? Icons.check_rounded : Icons.edit_rounded,
                    size: 16,
                    color: _editingResult ? Colors.greenAccent : Colors.white38,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ],
            if (!hasOriginal) ...[
              Row(children: [
                Expanded(child: Text(widget.l10n.result,
                    style: const TextStyle(color: Colors.white38, fontSize: 11,
                        fontWeight: FontWeight.w600, letterSpacing: 1))),
                GestureDetector(
                  onTap: _editingResult ? _finishEditResult : _startEditResult,
                  child: Icon(
                    _editingResult ? Icons.check_rounded : Icons.edit_rounded,
                    size: 16,
                    color: _editingResult ? Colors.greenAccent : Colors.white38,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ],
            _editingResult
                ? TextField(
                    controller: _editResultCtrl,
                    maxLines: null,
                    autofocus: true,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15, height: 1.6),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  )
                : SelectableText(_currentResult,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15, height: 1.6)),
            const SizedBox(height: 20),
            if (_audioReady) ...[
              const Divider(color: Colors.white12, height: 1),
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
                    _isPlaying
                        ? widget.l10n.pause
                        : widget.l10n.play,
                    style: const TextStyle(fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colors[0],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _download,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(widget.l10n.download),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                            color: Colors.white.withOpacity(0.3)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _share,
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: Text(widget.l10n.share),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                            color: Colors.white.withOpacity(0.3)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                if (hasOriginal) ...[
                  Expanded(
                    child: _CopyButton(
                      label: widget.l10n.copyOriginal,
                      text: _currentOriginal,
                      parentContext: context,
                      snackLabel: widget.l10n.copied,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: _CopyButton(
                    label: hasOriginal
                        ? (widget.item.type == HistoryType.transform
                            ? widget.l10n.copy
                            : widget.l10n.copyTranslation)
                        : widget.l10n.copy,
                    text: _currentResult,
                    parentContext: context,
                    snackLabel: widget.l10n.copied,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (hasOriginal)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Share.share(_currentOriginal),
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: Text(widget.l10n.shareOriginal,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(
                            color: Colors.white.withOpacity(0.2)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Share.share(_currentResult),
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: Text(
                          widget.item.type == HistoryType.transform
                              ? widget.l10n.shareText
                              : widget.l10n.shareTranslation,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(
                            color: Colors.white.withOpacity(0.2)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Share.share(_currentResult),
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: Text(widget.l10n.shareText),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(
                        color: Colors.white.withOpacity(0.2)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    showTransformSheet(context, _currentResult),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(widget.l10n.transformText),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  widget.service.delete(widget.item.id);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.redAccent),
                label: Text(widget.l10n.deleteEntry,
                    style: const TextStyle(color: Colors.redAccent)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                        color: Colors.redAccent.withOpacity(0.3)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateFull(DateTime dt) {
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

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

class _Badge extends StatelessWidget {
  final String label;
  const _Badge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(color: Colors.white60, fontSize: 11)),
    );
  }
}
