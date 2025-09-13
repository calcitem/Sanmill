// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// saved_games_page.dart

import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/app_theme.dart';
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
  });

  final String path;
  final String filename;
  final DateTime modified;
  String? boardLayout;
  String? error;
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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
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
      return bm.compareTo(am);
    });

    final List<SavedGameEntry> initial = files
        .map<SavedGameEntry>((File f) => SavedGameEntry(
              path: f.path,
              filename: p.basename(f.path),
              modified: f.lastModifiedSync(),
            ))
        .toList();

    setState(() {
      _entries.addAll(initial);
    });

    // Compute previews asynchronously
    for (int i = 0; i < _entries.length; i++) {
      final SavedGameEntry e = _entries[i];
      try {
        final String content = await File(e.path).readAsString();
        final String? layout = await _computeFinalBoardLayout(content);
        if (!mounted) {
          return;
        }
        setState(() {
          e.boardLayout = layout ?? '';
        });
      } catch (err) {
        if (!mounted) {
          return;
        }
        setState(() {
          e.error = err.toString();
          e.boardLayout = '';
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
      return records;
    } catch (_) {
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
        final ArchiveFile archiveFile =
            ArchiveFile(fileName, fileBytes.length, fileBytes);
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
      final String timestamp =
          DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
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
                    final String subtitle =
                        DateFormat.yMd().add_Hms().format(e.modified.toLocal());
                    return InkWell(
                      onTap: () => _openGame(e),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8.0, vertical: 6.0),
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
                          child: Row(
                            children: <Widget>[
                              // Left: MiniBoard preview
                              SizedBox(
                                width: 100,
                                height: 100,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: e.boardLayout != null &&
                                          e.boardLayout!.isNotEmpty
                                      ? MiniBoard(
                                          boardLayout: e.boardLayout!,
                                        )
                                      : Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: DB()
                                                .colorSettings
                                                .boardBackgroundColor,
                                            borderRadius: BorderRadius.circular(
                                                DB()
                                                    .displaySettings
                                                    .boardCornerRadius),
                                          ),
                                          child: e.error == null
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2),
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
                                      vertical: 12.0, horizontal: 8.0),
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
                                            fontSize: 12),
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
                                              fontSize: 12),
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
                    );
                  },
                ),
    );
  }
}
