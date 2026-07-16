// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// saved_games_page.dart

import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/app_styles.dart';
import '../../shared/utils/helpers/text_helpers/safe_text_editing_controller.dart';
import '../../shared/widgets/lichess_list_section.dart';
import '../services/mill.dart';
import '../services/save_load/saved_game_catalog.dart';
import 'mini_board.dart';

/// A single saved game entry with metadata for preview.
class SavedGameEntry {
  SavedGameEntry({
    required this.path,
    required this.filename,
    required this.modified,
    this.boardLayout,
    this.error,
    this.isLoading = true,
    this.previewTimedOut = false,
  });

  final String path;
  final String filename;
  final DateTime modified;
  String? boardLayout;
  String? error;
  bool isLoading;
  bool previewTimedOut;
  Timer? timeoutTimer;
}

/// A page that lists saved PGN files with a MiniBoard preview.
class SavedGamesPage extends StatefulWidget {
  const SavedGamesPage({super.key, this.onGameLoaded});

  final VoidCallback? onGameLoaded;

  @override
  State<SavedGamesPage> createState() => _SavedGamesPageState();
}

enum _SavedGameAction { rename, delete }

class _SavedGamesPageState extends State<SavedGamesPage> {
  final List<SavedGameEntry> _entries = <SavedGameEntry>[];
  bool _loading = true;
  bool _isReversedOrder = false;
  final Set<Timer> _previewTimeoutTimers = <Timer>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _cancelAllPreviewTimeouts();
    super.dispose();
  }

  void _schedulePreviewTimeout(SavedGameEntry entry) {
    _clearEntryTimeout(entry);
    Timer? timer;
    timer = Timer(const Duration(seconds: 3), () {
      final Timer? activeTimer = timer;
      if (activeTimer == null) {
        return;
      }
      if (!mounted || !_entries.contains(entry)) {
        _previewTimeoutTimers.remove(activeTimer);
        if (identical(entry.timeoutTimer, activeTimer)) {
          entry.timeoutTimer = null;
        }
        return;
      }
      if (!entry.isLoading) {
        _previewTimeoutTimers.remove(activeTimer);
        if (identical(entry.timeoutTimer, activeTimer)) {
          entry.timeoutTimer = null;
        }
        return;
      }
      setState(() {
        entry.isLoading = false;
        entry.previewTimedOut = true;
      });
      _previewTimeoutTimers.remove(activeTimer);
      if (identical(entry.timeoutTimer, activeTimer)) {
        entry.timeoutTimer = null;
      }
    });
    entry.timeoutTimer = timer;
    if (timer != null) {
      _previewTimeoutTimers.add(timer);
    }
  }

  void _clearEntryTimeout(SavedGameEntry entry) {
    final Timer? timer = entry.timeoutTimer;
    if (timer != null) {
      timer.cancel();
      _previewTimeoutTimers.remove(timer);
      entry.timeoutTimer = null;
    }
  }

  void _cancelAllPreviewTimeouts() {
    for (final Timer timer in _previewTimeoutTimers) {
      timer.cancel();
    }
    _previewTimeoutTimers.clear();
    for (final SavedGameEntry entry in _entries) {
      entry.timeoutTimer = null;
    }
  }

  Future<void> _refresh() async {
    _cancelAllPreviewTimeouts();
    setState(() {
      _loading = true;
      _entries.clear();
    });

    final Directory? dir = await _recordsDirectory();
    if (dir == null) {
      setState(() {
        _loading = false;
      });
      return;
    }

    final List<File> files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.toLowerCase().endsWith('.pgn'))
        .toList();

    files.sort((File a, File b) {
      final DateTime am = a.lastModifiedSync();
      final DateTime bm = b.lastModifiedSync();
      // Sort by modification time, newest first by default
      return _isReversedOrder ? am.compareTo(bm) : bm.compareTo(am);
    });

    final List<SavedGameEntry> initial = files
        .map<SavedGameEntry>(
          (File f) => SavedGameEntry(
            path: f.path,
            filename: p.basename(f.path),
            modified: f.lastModifiedSync(),
          ),
        )
        .toList();

    setState(() {
      _entries.addAll(initial);
    });

    for (final SavedGameEntry entry in initial) {
      entry.isLoading = true;
      entry.previewTimedOut = false;
      _schedulePreviewTimeout(entry);
    }

    // Compute previews asynchronously
    for (int i = 0; i < _entries.length; i++) {
      final SavedGameEntry e = _entries[i];
      try {
        final String content = await File(e.path).readAsString();
        final String? layout = await _computeFinalBoardLayout(content);
        if (!mounted) {
          return;
        }
        if (!_entries.contains(e)) {
          continue;
        }
        final String sanitizedLayout = layout ?? '';
        if (sanitizedLayout.isNotEmpty) {
          _clearEntryTimeout(e);
          setState(() {
            e.error = null;
            e.boardLayout = sanitizedLayout;
            e.isLoading = false;
            e.previewTimedOut = false;
          });
        } else {
          setState(() {
            e.error = null;
            e.boardLayout = '';
            e.isLoading = true;
            e.previewTimedOut = false;
          });
        }
      } catch (err) {
        if (!mounted) {
          return;
        }
        if (!_entries.contains(e)) {
          continue;
        }
        _clearEntryTimeout(e);
        setState(() {
          e.error = err.toString();
          e.boardLayout = '';
          e.isLoading = false;
          e.previewTimedOut = true;
        });
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
    });
  }

  /// Determine the records directory. Mirrors LoadService behavior.
  Future<Directory?> _recordsDirectory() async {
    return savedGameCatalog.recordsDirectory();
  }

  /// Compute the final board layout for a PGN content without mutating global state.
  Future<String?> _computeFinalBoardLayout(String pgnContent) async {
    return savedGameCatalog.computeFinalBoardLayout(pgnContent);
  }

  /// Create and share a zip file containing all PGN files from records directory
  Future<void> _shareRecords() async {
    try {
      final Directory? recordsDir = await _recordsDirectory();
      if (recordsDir == null || !recordsDir.existsSync()) {
        // No records directory found, silently return
        return;
      }

      // Get all PGN files
      final List<File> pgnFiles = recordsDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.toLowerCase().endsWith('.pgn'))
          .toList();

      if (pgnFiles.isEmpty) {
        // No PGN files found, silently return
        return;
      }

      // Create zip archive
      final Archive archive = Archive();

      for (final File pgnFile in pgnFiles) {
        final Uint8List fileBytes = await pgnFile.readAsBytes();
        final String fileName = p.basename(pgnFile.path);
        final ArchiveFile archiveFile = ArchiveFile(
          fileName,
          fileBytes.length,
          fileBytes,
        );
        archive.addFile(archiveFile);
      }

      // Encode zip
      final List<int> encodedBytes = ZipEncoder().encode(archive);
      final Uint8List zipBytes = Uint8List.fromList(encodedBytes);

      // Create temporary zip file
      final Directory tempDir = await getTemporaryDirectory();
      final String timestamp = DateFormat(
        'yyyyMMdd_HHmmss',
      ).format(DateTime.now());
      final String zipFileName = 'sanmill-records_$timestamp.zip';
      final File zipFile = File(p.join(tempDir.path, zipFileName));
      await zipFile.writeAsBytes(zipBytes);

      // Share the zip file
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(zipFile.path)],
          text: 'Sanmill saved games',
        ),
      );
    } catch (e) {
      // Show error message using existing localized text
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).error(e.toString()))),
        );
      }
    }
  }

  /// Delete a saved game file
  Future<void> _deleteGame(SavedGameEntry e) async {
    try {
      final File file = File(e.path);
      if (file.existsSync()) {
        await file.delete();
        // Remove from list and refresh UI
        setState(() {
          _entries.remove(e);
        });
      }
    } catch (error) {
      // Show error message using existing localized text
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).error(error.toString()))),
        );
      }
    }
  }

  Future<void> _confirmDeleteGame(SavedGameEntry e) async {
    final bool shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(S.of(context).confirm),
              content: Text('${S.of(context).delete} ${e.filename}'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(S.of(context).cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(S.of(context).delete),
                ),
              ],
            );
          },
        ) ??
        false;
    if (shouldDelete) {
      await _deleteGame(e);
    }
  }

  /// Rename a saved game file
  Future<void> _renameGame(SavedGameEntry e) async {
    final TextEditingController controller = SafeTextEditingController();
    // Extract filename without extension for editing
    final String currentName = p.basenameWithoutExtension(e.filename);
    controller.text = currentName;

    final String? newName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).renameGame),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: S.of(context).filename,
              suffixText: '.pgn',
            ),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).cancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(S.of(context).rename),
            ),
          ],
        );
      },
    );

    if (newName == null || newName.isEmpty || newName == currentName) {
      return; // User cancelled or no change
    }

    try {
      final File oldFile = File(e.path);
      final String newPath = p.join(p.dirname(e.path), '$newName.pgn');
      final File newFile = File(newPath);

      // Check if new filename already exists
      if (newFile.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context).fileAlreadyExists('$newName.pgn')),
            ),
          );
        }
        return;
      }

      // Rename the file
      await oldFile.rename(newPath);

      // Refresh the entire list to reflect the rename
      _refresh();
    } catch (error) {
      // Show error message using existing localized text
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).error(error.toString()))),
        );
      }
    }
  }

  Future<void> _pickAndPreview() async {
    try {
      // On desktop platforms, use last saved directory as initial directory
      final bool isMobilePlatform =
          !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      final String lastDirectory = isMobilePlatform
          ? ''
          : DB().generalSettings.lastPgnSaveDirectory;

      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['pgn'],
        initialDirectory: lastDirectory.isNotEmpty ? lastDirectory : null,
      );

      if (result == null || result.files.single.path == null) {
        return;
      }

      final String path = result.files.single.path!;
      final File file = File(path);
      final String content = await file.readAsString();

      // Compute layout
      final String? layout = await _computeFinalBoardLayout(content);

      if (!mounted) {
        return;
      }

      // Show dialog
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          final ColorScheme colorScheme = Theme.of(context).colorScheme;
          return AlertDialog(
            title: Text(p.basename(path)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AspectRatio(
                    aspectRatio: 1.0,
                    child: MiniBoard(boardLayout: layout ?? ''),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    path,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(S.of(context).cancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openGame(
                    SavedGameEntry(
                      path: path,
                      filename: p.basename(path),
                      modified: file.lastModifiedSync(),
                    ),
                  );
                },
                child: Text(S.of(context).ok),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).error(e.toString()))),
        );
      }
    }
  }

  Future<void> _openGame(SavedGameEntry e) async {
    await LoadService.loadGame(context, e.path, isRunning: true);
    final VoidCallback? onGameLoaded = widget.onGameLoaded;
    // Close the SavedGamesPage after loading the game.
    if (mounted) {
      Navigator.of(context).pop();
    }
    if (onGameLoaded != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onGameLoaded());
    }
  }

  /// Batch import PGN files from a zip archive
  Future<void> _batchImportFromZip() async {
    try {
      // Use FilePicker to select a zip file
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['zip'],
      );

      if (result == null || result.files.single.path == null) {
        return;
      }

      final String zipPath = result.files.single.path!;
      final File zipFile = File(zipPath);

      if (!zipFile.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).error('File not found'))),
          );
        }
        return;
      }

      // Read and decode the zip file
      final List<int> zipBytes = await zipFile.readAsBytes();
      final Archive archive = ZipDecoder().decodeBytes(zipBytes);

      // Get the records directory
      final Directory? recordsDir = await _recordsDirectory();
      if (recordsDir == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context).error('Records directory not found')),
            ),
          );
        }
        return;
      }

      int importedCount = 0;

      // Extract all PGN files from the archive
      for (final ArchiveFile file in archive) {
        if (file.isFile && file.name.toLowerCase().endsWith('.pgn')) {
          // Extract filename from path (in case zip contains directories)
          final String filename = p.basename(file.name);
          final String targetPath = p.join(recordsDir.path, filename);
          final File targetFile = File(targetPath);

          // Write the file content
          final List<int> content = file.content as List<int>;
          await targetFile.writeAsBytes(content);
          importedCount++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).pgnFilesImported(importedCount)),
          ),
        );

        // Refresh the list to show newly imported files
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).error(e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextTheme textTheme = theme.textTheme;
    final S strings = S.of(context);
    final String sortLabel = _isReversedOrder
        ? strings.sortNewestFirst
        : strings.sortOldestFirst;

    return Scaffold(
      key: const Key('saved_games_page_scaffold'),
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(strings.loadGame),
        actions: <Widget>[
          // Browse button
          IconButton(
            icon: Icon(Icons.folder_open, semanticLabel: strings.openGameFile),
            tooltip: strings.openGameFile,
            onPressed: _pickAndPreview,
          ),
          // Batch import button
          IconButton(
            icon: Icon(
              Icons.file_upload,
              semanticLabel: strings.importGameArchive,
            ),
            tooltip: strings.importGameArchive,
            onPressed: _batchImportFromZip,
          ),
          // Sort order button
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (Widget child, Animation<double> anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: _isReversedOrder
                  ? Icon(
                      FluentIcons.arrow_sort_up_24_regular,
                      key: const ValueKey<String>('ascending'),
                      semanticLabel: sortLabel,
                    )
                  : Icon(
                      FluentIcons.arrow_sort_down_24_regular,
                      key: const ValueKey<String>('descending'),
                      semanticLabel: sortLabel,
                    ),
            ),
            tooltip: sortLabel,
            onPressed: () {
              setState(() {
                _isReversedOrder = !_isReversedOrder;
              });
              // Refresh the list with new sort order
              _refresh();
            },
          ),
          // Share button
          IconButton(
            icon: Icon(Icons.share, semanticLabel: strings.exportGameArchive),
            tooltip: strings.exportGameArchive,
            onPressed: _shareRecords,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? Center(
              child: Text(
                strings.none,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView(
              key: const Key('saved_games_page_list'),
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              children: <Widget>[
                LichessListSection(
                  header: Text(strings.recentGames),
                  cardKey: const Key('saved_games_page_section'),
                  hasLeading: false,
                  children: <Widget>[
                    for (final SavedGameEntry entry in _entries)
                      _SavedGameListTile(
                        key: Key('saved_game_${entry.path}'),
                        entry: entry,
                        onOpen: () => _openGame(entry),
                        onRename: () => _renameGame(entry),
                        onDelete: () => _confirmDeleteGame(entry),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _SavedGameListTile extends StatelessWidget {
  const _SavedGameListTile({
    super.key,
    required this.entry,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final SavedGameEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String modified = DateFormat.yMMMd().add_Hm().format(
      entry.modified.toLocal(),
    );
    final double contentOpacity = entry.previewTimedOut ? 0.5 : 1.0;

    return InkWell(
      onTap: onOpen,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: contentOpacity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: <Widget>[
              _SavedGamePreview(entry: entry),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppStyles.tileTitle.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      modified,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppStyles.tileSubtitle.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: AppStyles.subtitleOpacity,
                        ),
                      ),
                    ),
                    if (entry.error != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        entry.error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppStyles.tileSubtitle.copyWith(
                          color: colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<_SavedGameAction>(
                tooltip: strings.menu,
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
                onSelected: (_SavedGameAction action) {
                  switch (action) {
                    case _SavedGameAction.rename:
                      onRename();
                      break;
                    case _SavedGameAction.delete:
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_SavedGameAction>>[
                      PopupMenuItem<_SavedGameAction>(
                        value: _SavedGameAction.rename,
                        child: ListTile(
                          leading: const Icon(Icons.edit_rounded),
                          title: Text(strings.rename),
                        ),
                      ),
                      PopupMenuItem<_SavedGameAction>(
                        value: _SavedGameAction.delete,
                        child: ListTile(
                          leading: Icon(
                            Icons.delete_rounded,
                            color: colorScheme.error,
                          ),
                          title: Text(
                            strings.delete,
                            style: TextStyle(color: colorScheme.error),
                          ),
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
}

class _SavedGamePreview extends StatelessWidget {
  const _SavedGamePreview({required this.entry});

  final SavedGameEntry entry;

  @override
  Widget build(BuildContext context) {
    final String? boardLayout = entry.boardLayout;
    if (boardLayout != null && boardLayout.isNotEmpty) {
      return SizedBox.square(
        dimension: 72,
        child: MiniBoard(boardLayout: boardLayout),
      );
    }

    final Color boardBackgroundColor = DB().colorSettings.boardBackgroundColor;
    final Color pieceHighlightColor = DB().colorSettings.pieceHighlightColor;
    return Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: boardBackgroundColor,
        borderRadius: BorderRadius.circular(
          DB().displaySettings.boardCornerRadius,
        ),
      ),
      child: entry.error == null
          ? entry.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const SizedBox(width: 18, height: 18)
          : Icon(Icons.error_outline, color: pieceHighlightColor),
    );
  }
}
