// SPDX-License-Identifier: GPL-3.0-or-later
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
import '../../shared/themes/app_theme.dart';
import '../../shared/utils/helpers/text_helpers/safe_text_editing_controller.dart';
import '../services/import_export/pgn.dart';
import '../services/mill.dart';
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
  const SavedGamesPage({super.key});

  @override
  State<SavedGamesPage> createState() => _SavedGamesPageState();
}

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

    final List<FileSystemEntity> allEntities = dir.listSync(recursive: true);
    debugPrint(
      '[SavedGamesPage] Total entities in directory: ${allEntities.length}',
    );

    final List<File> files = allEntities.whereType<File>().where((File f) {
      final bool isPgn = f.path.toLowerCase().endsWith('.pgn');
      if (isPgn) {
        debugPrint('[SavedGamesPage] Found PGN file: ${f.path}');
      }
      return isPgn;
    }).toList();

    debugPrint('[SavedGamesPage] Total PGN files found: ${files.length}');

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
    try {
      // On Android/iOS, always use the app's private records directory.
      // User-selected directories (via SAF) cannot be enumerated with
      // Directory.listSync() due to Scoped Storage restrictions in Android 11+.
      final bool isMobilePlatform =
          !kIsWeb && (Platform.isAndroid || Platform.isIOS);

      if (!isMobilePlatform) {
        // On desktop platforms, try to use the last saved directory if it exists
        final String lastDirectory = DB().generalSettings.lastPgnSaveDirectory;
        debugPrint('[SavedGamesPage] lastPgnSaveDirectory: "$lastDirectory"');

        if (lastDirectory.isNotEmpty) {
          final Directory lastDir = Directory(lastDirectory);
          final bool exists = lastDir.existsSync();
          debugPrint('[SavedGamesPage] Directory exists: $exists');

          if (exists) {
            debugPrint(
              '[SavedGamesPage] Using last saved directory: $lastDirectory',
            );
            return lastDir;
          }
        }
      }

      // Fallback to default records directory
      debugPrint('[SavedGamesPage] Using default records directory');
      Directory? base;
      if (!kIsWeb && Platform.isAndroid) {
        base = await getExternalStorageDirectory();
      } else {
        base = await getApplicationDocumentsDirectory();
      }
      if (base == null) {
        return null;
      }
      final Directory records = Directory(p.join(base.path, 'records'));
      if (!records.existsSync()) {
        records.createSync(recursive: true);
      }
      debugPrint('[SavedGamesPage] Records directory: ${records.path}');
      return records;
    } catch (e) {
      debugPrint('[SavedGamesPage] Error: $e');
      return null;
    }
  }

  /// Compute the final board layout for a PGN content without mutating global state.
  Future<String?> _computeFinalBoardLayout(String pgnContent) async {
    // Parse the PGN string (supports headers and comments)
    final PgnGame<PgnNodeData> game = PgnGame.parsePgn(pgnContent);

    final String? fen = game.headers['FEN'];

    // Helper to split complex tokens like "b6xd3" into ["b6", "xd3"].
    List<String> splitSan(String san) {
      san = san.replaceAll(RegExp(r'\{[^}]*\}'), '').trim();

      if (san.contains('x')) {
        if (san.startsWith('x')) {
          final RegExp regex = RegExp(r'(x[a-g][1-7])');
          return regex
              .allMatches(san)
              .map((RegExpMatch m) => m.group(0)!)
              .toList();
        } else {
          final int firstX = san.indexOf('x');
          if (firstX > 0) {
            final String firstSegment = san.substring(0, firstX);
            final RegExp regex = RegExp(r'(x[a-g][1-7])');
            final String remainingSan = san.substring(firstX);
            final List<String> xs = regex
                .allMatches(remainingSan)
                .map((RegExpMatch m) => m.group(0)!)
                .toList();
            return <String>[firstSegment, ...xs];
          } else {
            final RegExp regex = RegExp(r'(x[a-g][1-7])');
            return regex
                .allMatches(san)
                .map((RegExpMatch m) => m.group(0)!)
                .toList();
          }
        }
      }
      return <String>[san];
    }

    // Validate/normalize move token to the standard notation expected by engine.
    String toStandard(String token) {
      final String t = token.trim().toLowerCase();
      if (t == 'p' || t == '*' || t == 'x' || t == 'xx' || t == 'xxx') {
        // Pass/invalid markers do not change the board for preview.
        return '';
      }
      if (RegExp(r'^x[a-g][1-7]$').hasMatch(t)) {
        return t.substring(0, 3);
      }
      if (RegExp(r'^[a-g][1-7]-[a-g][1-7]$').hasMatch(t)) {
        return t;
      }
      if (RegExp(r'^[a-g][1-7]$').hasMatch(t)) {
        return t;
      }
      // Ignore result tokens like 1-0, 0-1, 1/2-1/2
      if (t == '1-0' || t == '0-1' || t == '1/2-1/2') {
        return '';
      }
      // Unknown token, ignore in preview
      return '';
    }

    // Build a simple mainline PgnNode<ExtMove> tree to reuse engine replay.
    final PgnNode<ExtMove> root = PgnNode<ExtMove>();
    PgnNode<ExtMove> cur = root;

    for (final PgnNodeData node in game.moves.mainline()) {
      final String san = node.san.trim().toLowerCase();
      if (san.isEmpty) {
        continue;
      }
      final List<String> segments = splitSan(san);
      for (final String seg in segments) {
        final String u = toStandard(seg);
        if (u.isEmpty) {
          continue;
        }
        final ExtMove em = ExtMove(u, side: PieceColor.white);
        final PgnNode<ExtMove> child = PgnNode<ExtMove>(em);
        child.parent = cur;
        cur.children.add(child);
        cur = child;
      }
    }

    // Fill boardLayout for each node via internal engine replay (does not affect UI state).
    ImportService.fillAllNodesBoardLayout(root, setupFen: fen);

    // Traverse to the last node on the mainline to fetch its layout.
    PgnNode<ExtMove> t = root;
    PgnNode<ExtMove>? last;
    while (t.children.isNotEmpty) {
      t = t.children.first;
      last = t;
    }

    if (last?.data?.boardLayout != null &&
        last!.data!.boardLayout!.isNotEmpty) {
      return last.data!.boardLayout;
    }

    // If there are no moves, but FEN exists, produce a layout from FEN directly.
    if (fen != null && fen.isNotEmpty) {
      final Position pos = Position();
      if (!pos.setFen(fen)) {
        return '';
      }
      return pos.generateBoardLayoutAfterThisMove();
    }
    return '';
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
      if (encodedBytes == null) {
        throw Exception('Failed to encode archive');
      }
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
          title: Text(S.of(context).filename),
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
              child: Text(S.of(context).ok),
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
            SnackBar(content: Text('File $newName.pgn already exists')),
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

      final FilePickerResult? result = await FilePicker.platform.pickFiles(
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
                    style: TextStyle(
                      fontSize: 12,
                      color: DB().colorSettings.messageColor.withValues(
                        alpha: 0.7,
                      ),
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
    // Close the SavedGamesPage after loading the game
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appBarTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          S.of(context).loadGame,
          style: AppTheme.appBarTheme.titleTextStyle,
        ),
        actions: <Widget>[
          // Browse button
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: S.of(context).loadGame,
            onPressed: _pickAndPreview,
          ),
          // Sort order button
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (Widget child, Animation<double> anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: _isReversedOrder
                  ? const Icon(
                      FluentIcons.arrow_sort_up_24_regular,
                      key: ValueKey<String>('ascending'),
                    )
                  : const Icon(
                      FluentIcons.arrow_sort_down_24_regular,
                      key: ValueKey<String>('descending'),
                    ),
            ),
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
            icon: const Icon(Icons.share),
            tooltip: S.of(context).exportGame,
            onPressed: _shareRecords,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? Center(
              child: Text(
                S.of(context).none,
                style: TextStyle(color: DB().colorSettings.messageColor),
              ),
            )
          : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (BuildContext context, int index) {
                final SavedGameEntry e = _entries[index];
                final Color textColor = DB().colorSettings.messageColor;
                final String title = e.filename;
                // Format date according to user's locale without milliseconds
                final String subtitle = DateFormat.yMd().add_Hms().format(
                  e.modified.toLocal(),
                );
                final double contentOpacity = e.previewTimedOut ? 0.5 : 1.0;
                return Dismissible(
                  key: Key(e.path),
                  // Background for swipe right to left (delete)
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 20.0),
                    color: Colors.blue,
                    child: const Icon(
                      Icons.edit,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  // Secondary background for swipe left to right (edit)
                  secondaryBackground: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20.0),
                    color: Colors.red,
                    child: const Icon(
                      Icons.delete,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  confirmDismiss: (DismissDirection direction) async {
                    if (direction == DismissDirection.endToStart) {
                      // Swipe left to right shows delete - need confirmation
                      return await showDialog<bool>(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: Text(S.of(context).confirm),
                                content: Text(
                                  '${S.of(context).delete} ${e.filename}',
                                ),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: Text(S.of(context).cancel),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: Text(S.of(context).delete),
                                  ),
                                ],
                              );
                            },
                          ) ??
                          false;
                    } else {
                      // Swipe right to left shows edit - no confirmation needed, just trigger rename
                      _renameGame(e);
                      return false; // Don't actually dismiss the item
                    }
                  },
                  onDismissed: (DismissDirection direction) {
                    if (direction == DismissDirection.endToStart) {
                      _deleteGame(e);
                    }
                    // Note: edit action is handled in confirmDismiss, so no action needed here
                  },
                  child: InkWell(
                    onTap: () => _openGame(e),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 6.0,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: DB().colorSettings.darkBackgroundColor,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 2,
                              offset: Offset(2, 2),
                            ),
                          ],
                        ),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 250),
                          opacity: contentOpacity,
                          child: Row(
                            children: <Widget>[
                              // Left: MiniBoard preview
                              SizedBox(
                                width: 100,
                                height: 100,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child:
                                      e.boardLayout != null &&
                                          e.boardLayout!.isNotEmpty
                                      ? MiniBoard(boardLayout: e.boardLayout!)
                                      : Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: DB()
                                                .colorSettings
                                                .boardBackgroundColor,
                                            borderRadius: BorderRadius.circular(
                                              DB()
                                                  .displaySettings
                                                  .boardCornerRadius,
                                            ),
                                          ),
                                          child: e.error == null
                                              ? e.isLoading
                                                    ? const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      )
                                                    : const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                      )
                                              : Icon(
                                                  Icons.error_outline,
                                                  color: DB()
                                                      .colorSettings
                                                      .pieceHighlightColor,
                                                ),
                                        ),
                                ),
                              ),
                              // Right: file info
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12.0,
                                    horizontal: 8.0,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: textColor.withAlpha(180),
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (e.error != null) ...<Widget>[
                                        const SizedBox(height: 8),
                                        Text(
                                          e.error!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: DB()
                                                .colorSettings
                                                .pieceHighlightColor,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.chevron_right),
                                color: textColor,
                                onPressed: () => _openGame(e),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
