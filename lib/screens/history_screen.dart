import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import '../models/history_folder.dart';
import '../models/history_item.dart';
import '../providers/app_state.dart';
import '../services/backup_service.dart';
import '../services/folder_service.dart';
import '../services/history_service.dart';
import '../services/transform_presets_service.dart';
import 'transform_sheet.dart';

void _showDeleteUndo(
  ScaffoldMessengerState messenger,
  HistoryItem item,
  HistoryService service,
  AppLocalizations l10n,
) {
  messenger.hideCurrentSnackBar();
  messenger
      .showSnackBar(
        SnackBar(
          content: Text(l10n.deleted),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () => service.undoDelete(item),
          ),
          duration: const Duration(seconds: 4),
        ),
      )
      .closed
      .then((reason) {
    if (reason != SnackBarClosedReason.action) {
      service.deleteAudioFile(item);
    }
  });
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  HistoryType? _activeFilter;
  String? _activeFolderId;
  final Set<String> _selectedIds = {};
  bool get _selectMode => _selectedIds.isNotEmpty;
  bool _showFavoritesOnly = false;

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _startSelect(String id) {
    setState(() => _selectedIds.add(id));
  }

  void _selectAll(List<HistoryItem> items) {
    setState(() => _selectedIds.addAll(items.map((e) => e.id)));
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
  }

  void _deleteSelectedBatch(HistoryService svc, AppLocalizations l10n) {
    if (_selectedIds.isEmpty) return;
    final ids = List<String>.from(_selectedIds);
    _clearSelection();
    final messenger = ScaffoldMessenger.of(context);
    final deleted = svc.softDeleteBatch(ids);
    if (deleted.isEmpty) return;
    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(SnackBar(
          content: Text('${l10n.deleted}: ${deleted.length}'),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () => svc.undoDeleteBatch(deleted),
          ),
          duration: const Duration(seconds: 4),
        ))
        .closed
        .then((reason) {
      if (reason != SnackBarClosedReason.action) {
        for (final item in deleted) {
          svc.deleteAudioFile(item);
        }
      }
    });
  }

  void _moveBatchToFolder(String? folderId, HistoryService svc) {
    svc.moveToFolderBatch(List<String>.from(_selectedIds), folderId);
    _clearSelection();
  }

  void _showBatchFolderPicker(
      BuildContext context, AppLocalizations l10n, dynamic theme) {
    final fs = context.read<FolderService>();
    final svc = context.read<HistoryService>();
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FolderPickerSheet(
        folders: fs.folders,
        currentFolderId: null,
        l10n: l10n,
        theme: theme,
        onPick: (folderId) {
          Navigator.pop(context);
          _moveBatchToFolder(folderId, svc);
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _export(AppLocalizations l10n, HistoryService svc) async {
    try {
      final name = await BackupService.export(
          svc, context.read<TransformPresetsService>());
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
        context.read<FolderService>(),
        context.read<TransformPresetsService>(),
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
    var result = _activeFolderId == null
        ? items.where((e) => e.folderId == null).toList()
        : items.where((e) => e.folderId == _activeFolderId).toList();
    if (_showFavoritesOnly) {
      result = result.where((e) => e.isFavorite).toList();
    }
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

  void _createFolder(AppLocalizations l10n, Color surfaceColor) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text(l10n.newFolder,
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.folderNameHint,
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white54)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                context.read<FolderService>().add(name);
              }
              Navigator.pop(context);
            },
            child: Text(l10n.save,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final theme = state.buttonTheme;

    return PopScope(
      canPop: _activeFolderId == null && !_selectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_selectMode) {
            _clearSelection();
          } else {
            setState(() => _activeFolderId = null);
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _selectMode
              ? theme.colors[0].withOpacity(0.25)
              : theme.appBarColor,
          foregroundColor: Colors.white,
          leading: _selectMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _clearSelection,
                )
              : (_activeFolderId != null
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => _activeFolderId = null),
                    )
                  : null),
          title: _selectMode
              ? Text('${_selectedIds.length} ${l10n.selected}')
              : (_activeFolderId != null
                  ? Consumer<FolderService>(
                      builder: (_, fs, __) {
                        final folder = fs.folders
                            .where((f) => f.id == _activeFolderId)
                            .firstOrNull;
                        return Text(folder?.name ?? '');
                      },
                    )
                  : Text(l10n.historyTitle)),
          actions: _selectMode
              ? [
                  Consumer2<HistoryService, FolderService>(
                    builder: (_, svc, fs, __) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.select_all),
                          tooltip: l10n.selectAll,
                          onPressed: () =>
                              _selectAll(_filtered(svc.items)),
                        ),
                        if (fs.folders.isNotEmpty)
                          IconButton(
                            icon: const Icon(
                                Icons.drive_file_move_outlined),
                            onPressed: () => _showBatchFolderPicker(
                                context, l10n, theme),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          color: Colors.redAccent,
                          onPressed: () =>
                              _deleteSelectedBatch(svc, l10n),
                        ),
                      ],
                    ),
                  ),
                ]
              : [
                  if (_activeFolderId != null)
                    Consumer<FolderService>(
                      builder: (_, fs, __) {
                        final folder = fs.folders
                            .where((f) => f.id == _activeFolderId)
                            .firstOrNull;
                        if (folder == null) return const SizedBox.shrink();
                        return PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          color: theme.surfaceColor,
                          onSelected: (v) {
                            if (v == 'rename')
                              _renameFolder(
                                  folder, l10n, theme.surfaceColor);
                            if (v == 'delete')
                              _deleteFolder(
                                  folder, l10n, theme.surfaceColor);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'rename',
                              child: Row(children: [
                                const Icon(
                                    Icons.drive_file_rename_outline,
                                    size: 20,
                                    color: Colors.white70),
                                const SizedBox(width: 12),
                                Text(l10n.rename,
                                    style: const TextStyle(
                                        color: Colors.white)),
                              ]),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(children: [
                                const Icon(Icons.delete_outline,
                                    size: 20, color: Colors.redAccent),
                                const SizedBox(width: 12),
                                Text(l10n.delete,
                                    style: const TextStyle(
                                        color: Colors.redAccent)),
                              ]),
                            ),
                          ],
                        );
                      },
                    )
                  else
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
                              if (v == 'newfolder')
                                _createFolder(l10n, theme.surfaceColor);
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'newfolder',
                                child: Row(children: [
                                  const Icon(
                                      Icons.create_new_folder_outlined,
                                      size: 20,
                                      color: Colors.white70),
                                  const SizedBox(width: 12),
                                  Text(l10n.newFolder,
                                      style: const TextStyle(
                                          color: Colors.white)),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'export',
                                enabled: svc.items.isNotEmpty,
                                child: Row(children: [
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
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'import',
                                child: Row(children: [
                                  const Icon(Icons.download_rounded,
                                      size: 20, color: Colors.white70),
                                  const SizedBox(width: 12),
                                  Text(l10n.importHistory,
                                      style: const TextStyle(
                                          color: Colors.white)),
                                ]),
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
        body: Consumer2<HistoryService, FolderService>(
          builder: (context, svc, fs, _) {
            if (svc.items.isEmpty && fs.folders.isEmpty) {
              return _buildEmpty(l10n);
            }

            final filtered = _filtered(svc.items);

            return Column(
              children: [
                // ── Search bar ──────────────────────────────────────────
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
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),

                // ── Filter chips ────────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      _FilterPill(
                        label: l10n.filterAll,
                        selected: _activeFilter == null && !_showFavoritesOnly,
                        color: theme.colors[0],
                        onTap: () => setState(() {
                          _activeFilter = null;
                          _showFavoritesOnly = false;
                        }),
                      ),
                      const SizedBox(width: 6),
                      _FilterPill(
                        icon: Icons.star_rounded,
                        label: l10n.favorites,
                        selected: _showFavoritesOnly,
                        color: Colors.amber,
                        onTap: () => setState(
                            () => _showFavoritesOnly = !_showFavoritesOnly),
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

                // ── Folder row (root only) ──────────────────────────────
                if (_activeFolderId == null && fs.folders.isNotEmpty)
                  SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      itemCount: fs.folders.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final folder = fs.folders[i];
                        final count = svc.items
                            .where((e) => e.folderId == folder.id)
                            .length;
                        return _FolderCard(
                          folder: folder,
                          count: count,
                          color: theme.colors[0],
                          onTap: () =>
                              setState(() => _activeFolderId = folder.id),
                          onLongPress: () => _showFolderContextMenu(
                              context, folder, l10n, theme.surfaceColor),
                        );
                      },
                    ),
                  ),

                // ── List ────────────────────────────────────────────────
                Expanded(
                  child: filtered.isEmpty
                      ? _buildNoResults(l10n)
                      : ListView.separated(
                          padding:
                              const EdgeInsets.only(top: 4, bottom: 100),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, i) => _HistoryCard(
                            item: filtered[i],
                            service: svc,
                            folderService: fs,
                            selectMode: _selectMode,
                            isSelected: _selectedIds.contains(filtered[i].id),
                            onToggleSelect: () => _toggleSelect(filtered[i].id),
                            onStartSelect: () => _startSelect(filtered[i].id),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
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
              context.read<FolderService>().clearAll();
              Navigator.pop(context);
            },
            child: Text(l10n.delete,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _renameFolder(
      HistoryFolder folder, AppLocalizations l10n, Color surfaceColor) {
    final ctrl = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text(l10n.rename,
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.folderNameHint,
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white54)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                context.read<FolderService>().rename(folder.id, name);
              }
              Navigator.pop(context);
            },
            child: Text(l10n.save,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showFolderContextMenu(BuildContext context, HistoryFolder folder,
      AppLocalizations l10n, Color surfaceColor) {
    final color = context.read<AppState>().buttonTheme.colors[0];
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        minimum: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(children: [
                Icon(Icons.folder_rounded, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(folder.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline,
                  color: Colors.white70),
              title: Text(l10n.rename,
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _renameFolder(folder, l10n, surfaceColor);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text(l10n.delete,
                  style: const TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                _deleteFolder(folder, l10n, surfaceColor);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _deleteFolder(
      HistoryFolder folder, AppLocalizations l10n, Color surfaceColor) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text(l10n.delete,
            style: const TextStyle(color: Colors.white)),
        content: Text(
          '"${folder.name}"',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel,
                style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              context.read<HistoryService>().deleteAllFromFolder(folder.id);
              context.read<FolderService>().delete(folder.id);
              setState(() => _activeFolderId = null);
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

// ── Folder card ───────────────────────────────────────────────────────────────

class _FolderCard extends StatelessWidget {
  final HistoryFolder folder;
  final int count;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _FolderCard({
    required this.folder,
    required this.count,
    required this.color,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 120,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(Icons.folder_rounded, color: color, size: 24),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
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
  final IconData? icon;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 12, color: selected ? color : Colors.white54),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.white54,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── History card ──────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final HistoryItem item;
  final HistoryService service;
  final FolderService folderService;
  final bool selectMode;
  final bool isSelected;
  final VoidCallback onToggleSelect;
  final VoidCallback onStartSelect;

  const _HistoryCard({
    required this.item,
    required this.service,
    required this.folderService,
    this.selectMode = false,
    this.isSelected = false,
    required this.onToggleSelect,
    required this.onStartSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<AppState>().l10n;
    final theme = context.read<AppState>().buttonTheme;

    if (selectMode) {
      return _buildSelectableCard(context, l10n, theme);
    }

    return GestureDetector(
      onLongPress: onStartSelect,
      child: _buildDismissible(context, l10n, theme),
    );
  }

  Widget _buildSelectableCard(
      BuildContext context, AppLocalizations l10n, dynamic theme) {
    return GestureDetector(
      onTap: onToggleSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colors[0].withOpacity(0.18)
              : theme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? theme.colors[0] : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colors[0].withOpacity(0.3)
                    : item.type.color.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: isSelected
                  ? Icon(Icons.check_rounded, color: theme.colors[0], size: 20)
                  : Icon(item.type.icon, color: item.type.color, size: 20),
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
          ],
        ),
      ),
    );
  }

  void _showFolderPicker(
      BuildContext context, AppLocalizations l10n, dynamic theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FolderPickerSheet(
        folders: folderService.folders,
        currentFolderId: item.folderId,
        l10n: l10n,
        theme: theme,
        onPick: (folderId) {
          service.moveToFolder(item.id, folderId);
          Navigator.pop(context);
        },
      ),
    );
  }

  Widget _buildDismissible(
      BuildContext context, AppLocalizations l10n, dynamic theme) {
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
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final deleted = await service.softDelete(item.id);
        if (deleted != null) {
          _showDeleteUndo(messenger, deleted, service, l10n);
        }
      },
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
                      item.type == HistoryType.conversation
                          ? _conversationPreview(item.result)
                          : item.result,
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
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => service.toggleFavorite(item.id),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                      child: Icon(
                        item.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 18,
                        color: item.isFavorite
                            ? Colors.amber
                            : Colors.white24,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        _confirmDelete(context, l10n, theme.surfaceColor),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                      child: Icon(Icons.delete_outline,
                          size: 18,
                          color: Colors.white.withOpacity(0.25)),
                    ),
                  ),
                ],
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
      builder: (_) => item.type == HistoryType.conversation
          ? _ConversationDetailSheet(item: item, service: service, l10n: l10n)
          : _DetailSheet(
              item: item,
              service: service,
              folderService: folderService,
              l10n: l10n,
              outerContext: context,
            ),
    );
  }

  static String _conversationPreview(String result) {
    try {
      final data = jsonDecode(result) as Map<String, dynamic>;
      final turns = data['turns'] as List;
      if (turns.isNotEmpty) {
        return turns.first['original'] as String? ?? '';
      }
    } catch (_) {}
    return '';
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
            onPressed: () async {
              Navigator.pop(context);
              final messenger = ScaffoldMessenger.of(context);
              final deleted = await service.softDelete(item.id);
              if (deleted != null) {
                _showDeleteUndo(messenger, deleted, service, l10n);
              }
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
  final FolderService folderService;
  final AppLocalizations l10n;
  final BuildContext outerContext;

  const _DetailSheet({
    required this.item,
    required this.service,
    required this.folderService,
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

  late bool _isFavorite;
  late String _currentOriginal;
  late String _currentResult;
  final _editOrigCtrl = TextEditingController();
  final _editResultCtrl = TextEditingController();
  bool _editingOriginal = false;
  bool _editingResult = false;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.item.isFavorite;
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
    setState(() {
      _currentOriginal = newText;
      _editingOriginal = false;
    });
    widget.service.updateOriginal(widget.item.id, newText);
  }

  void _startEditResult() {
    _editResultCtrl.text = _currentResult;
    setState(() => _editingResult = true);
  }

  void _finishEditResult() {
    final newText = _editResultCtrl.text;
    setState(() {
      _currentResult = newText;
      _editingResult = false;
    });
    widget.service.updateResult(widget.item.id, newText);
  }

  Widget _buildCounter(String text) {
    final words =
        text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final chars = text.length;
    return Text(
      '$words ${widget.l10n.wordsAbbr} · $chars ${widget.l10n.charsAbbr}',
      style: const TextStyle(color: Colors.white38, fontSize: 11),
    );
  }

  void _showFolderPicker() {
    final theme = context.read<AppState>().buttonTheme;
    final l10n = widget.l10n;
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FolderPickerSheet(
        folders: widget.folderService.folders,
        currentFolderId: widget.item.folderId,
        l10n: l10n,
        theme: theme,
        onPick: (folderId) {
          widget.service.moveToFolder(widget.item.id, folderId);
          Navigator.pop(context);
          Navigator.pop(context);
        },
      ),
    );
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
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    widget.service.toggleFavorite(widget.item.id);
                    setState(() => _isFavorite = !_isFavorite);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _isFavorite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: _isFavorite ? Colors.amber : Colors.white38,
                      size: 24,
                    ),
                  ),
                ),
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
                Expanded(
                    child: Text(widget.l10n.original,
                        style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1))),
                GestureDetector(
                  onTap: _editingOriginal
                      ? _finishEditOriginal
                      : _startEditOriginal,
                  child: Icon(
                    _editingOriginal
                        ? Icons.check_rounded
                        : Icons.edit_rounded,
                    size: 16,
                    color: _editingOriginal
                        ? Colors.greenAccent
                        : Colors.white38,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              _editingOriginal
                  ? TextField(
                      controller: _editOrigCtrl,
                      maxLines: null,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
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
              const SizedBox(height: 4),
              _buildCounter(
                  _editingOriginal ? _editOrigCtrl.text : _currentOriginal),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: Text(
                  widget.item.type == HistoryType.transform
                      ? widget.l10n.result
                      : widget.l10n.translation,
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1),
                )),
                GestureDetector(
                  onTap:
                      _editingResult ? _finishEditResult : _startEditResult,
                  child: Icon(
                    _editingResult
                        ? Icons.check_rounded
                        : Icons.edit_rounded,
                    size: 16,
                    color:
                        _editingResult ? Colors.greenAccent : Colors.white38,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ],
            if (!hasOriginal) ...[
              Row(children: [
                Expanded(
                    child: Text(widget.l10n.result,
                        style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1))),
                GestureDetector(
                  onTap:
                      _editingResult ? _finishEditResult : _startEditResult,
                  child: Icon(
                    _editingResult
                        ? Icons.check_rounded
                        : Icons.edit_rounded,
                    size: 16,
                    color:
                        _editingResult ? Colors.greenAccent : Colors.white38,
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
                    onChanged: (_) => setState(() {}),
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
            const SizedBox(height: 4),
            _buildCounter(
                _editingResult ? _editResultCtrl.text : _currentResult),
            const SizedBox(height: 16),
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
                    _isPlaying ? widget.l10n.pause : widget.l10n.play,
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
                      onPressed: () => Share.share(_currentOriginal),
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
                      onPressed: () => Share.share(_currentResult),
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
              child: OutlinedButton.icon(
                onPressed: _showFolderPicker,
                icon: const Icon(Icons.drive_file_move_outlined, size: 18),
                label: Text(widget.l10n.moveToFolder),
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
                onPressed: () async {
                  final messenger =
                      ScaffoldMessenger.of(widget.outerContext);
                  final deleted =
                      await widget.service.softDelete(widget.item.id);
                  if (mounted) Navigator.pop(context);
                  if (deleted != null) {
                    _showDeleteUndo(
                        messenger, deleted, widget.service, widget.l10n);
                  }
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

// ── Folder picker sheet ───────────────────────────────────────────────────────

class _FolderPickerSheet extends StatelessWidget {
  final List<HistoryFolder> folders;
  final String? currentFolderId;
  final AppLocalizations l10n;
  final dynamic theme;
  final void Function(String? folderId) onPick;

  const _FolderPickerSheet({
    required this.folders,
    required this.currentFolderId,
    required this.l10n,
    required this.theme,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              l10n.moveToFolder,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              children: [
                ListTile(
                  leading: Icon(Icons.folder_off_outlined,
                      color: currentFolderId == null
                          ? theme.colors[0]
                          : Colors.white38),
                  title: Text(l10n.noFolder,
                      style: const TextStyle(color: Colors.white)),
                  trailing: currentFolderId == null
                      ? Icon(Icons.check, color: theme.colors[0])
                      : null,
                  tileColor: currentFolderId == null
                      ? theme.colors[0].withOpacity(0.15)
                      : null,
                  onTap: () => onPick(null),
                ),
                ...folders.map((folder) {
                  final isSelected = folder.id == currentFolderId;
                  return ListTile(
                    leading: Icon(Icons.folder_rounded,
                        color: isSelected
                            ? theme.colors[0]
                            : Colors.white54),
                    title: Text(folder.name,
                        style: const TextStyle(color: Colors.white)),
                    trailing: isSelected
                        ? Icon(Icons.check, color: theme.colors[0])
                        : null,
                    tileColor: isSelected
                        ? theme.colors[0].withOpacity(0.15)
                        : null,
                    onTap: () => onPick(folder.id),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
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

// ── Conversation detail sheet ─────────────────────────────────────────────────

class _ConversationDetailSheet extends StatefulWidget {
  final HistoryItem item;
  final HistoryService service;
  final AppLocalizations l10n;

  const _ConversationDetailSheet({
    required this.item,
    required this.service,
    required this.l10n,
  });

  @override
  State<_ConversationDetailSheet> createState() =>
      _ConversationDetailSheetState();
}

class _ConversationDetailSheetState extends State<_ConversationDetailSheet> {
  late List<Map<String, dynamic>> _turns;
  late String _langAName;
  late String _langBName;
  late bool _isFavorite;

  final _player = AudioPlayer();
  int? _playingIdx;
  StreamSubscription<PlayerState>? _playerSub;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.item.isFavorite;
    try {
      final data =
          jsonDecode(widget.item.result) as Map<String, dynamic>;
      _turns =
          (data['turns'] as List).cast<Map<String, dynamic>>();
      _langAName = data['langAName'] as String? ?? '';
      _langBName = data['langBName'] as String? ?? '';
    } catch (_) {
      _turns = [];
      _langAName = '';
      _langBName = '';
    }
    _playerSub = _player.playerStateStream.listen((s) {
      if (!mounted) return;
      if (s.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
        if (mounted) setState(() => _playingIdx = null);
      }
    });
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _playTurn(int idx) async {
    final path = _turns[idx]['audioPath'] as String?;
    if (path == null || !File(path).existsSync()) return;
    if (_playingIdx != null) {
      await _player.stop();
      if (_playingIdx == idx) {
        setState(() => _playingIdx = null);
        return;
      }
    }
    await _player.setFilePath(path);
    setState(() => _playingIdx = idx);
    await _player.play();
  }

  String _formatDateFull(DateTime dt) {
    const months = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<AppState>().buttonTheme;
    final colors = theme.colors;
    final colorA = colors[0];
    final colorB = colors.length > 1 ? colors[1] : colors[0];

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    Icon(HistoryType.conversation.icon,
                        color: HistoryType.conversation.color, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      widget.l10n.historyTypeLabel(HistoryType.conversation),
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
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        widget.service.toggleFavorite(widget.item.id);
                        setState(() => _isFavorite = !_isFavorite);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          _isFavorite
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color:
                              _isFavorite ? Colors.amber : Colors.white38,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDateFull(widget.item.createdAt),
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const Divider(color: Colors.white12, height: 20),
              ],
            ),
          ),
          Expanded(
            child: _turns.isEmpty
                ? const Center(
                    child: Icon(Icons.forum_outlined,
                        color: Colors.white12, size: 48),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      12, 0, 12,
                      24 + MediaQuery.of(context).viewPadding.bottom,
                    ),
                    itemCount: _turns.length,
                    itemBuilder: (_, i) {
                      final t = _turns[i];
                      final isA = t['isA'] as bool;
                      final original = t['original'] as String? ?? '';
                      final translated = t['translated'] as String? ?? '';
                      final audioPath = t['audioPath'] as String?;
                      final hasAudio = audioPath != null &&
                          File(audioPath).existsSync();
                      return _ConvHistoryBubble(
                        isA: isA,
                        original: original,
                        translated: translated,
                        fromLangName: isA ? _langAName : _langBName,
                        toLangName: isA ? _langBName : _langAName,
                        colorA: colorA,
                        colorB: colorB,
                        isPlaying: _playingIdx == i,
                        canPlay: hasAudio &&
                            (_playingIdx == null || _playingIdx == i),
                        onPlay: hasAudio ? () => _playTurn(i) : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConvHistoryBubble extends StatelessWidget {
  final bool isA;
  final String original;
  final String translated;
  final String fromLangName;
  final String toLangName;
  final Color colorA;
  final Color colorB;
  final bool isPlaying;
  final bool canPlay;
  final VoidCallback? onPlay;

  const _ConvHistoryBubble({
    required this.isA,
    required this.original,
    required this.translated,
    required this.fromLangName,
    required this.toLangName,
    required this.colorA,
    required this.colorB,
    required this.isPlaying,
    required this.canPlay,
    this.onPlay,
  });

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.read<AppState>().l10n.copied),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = isA ? colorA : colorB;

    return Align(
      alignment: isA ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        margin: EdgeInsets.only(
          bottom: 10,
          left: isA ? 0 : 32,
          right: isA ? 32 : 0,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: isA ? Radius.zero : const Radius.circular(14),
            bottomRight: isA ? const Radius.circular(14) : Radius.zero,
          ),
          border: Border.all(color: color.withOpacity(0.22), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  fromLangName,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _copy(context, original),
                  child: Icon(Icons.copy_rounded,
                      size: 13, color: color.withOpacity(0.45)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              original,
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
                  toLangName,
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      letterSpacing: 0.5),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _copy(context, translated),
                  child: const Icon(Icons.copy_rounded,
                      size: 13, color: Colors.white24),
                ),
              ],
            ),
            const SizedBox(height: 3),
            SelectableText(
              translated,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            if (onPlay != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: canPlay ? onPlay : null,
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
