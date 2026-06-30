// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../game_platform/game_session.dart' show GameAction, PlayerSeat;
import '../../../games/mill/mill_action_codec.dart';
import '../../../games/mill/native_mill_rules_port.dart';
import '../../../shared/database/database.dart';
import '../import_export/pgn.dart';
import '../mill.dart';

class SavedGamePreview {
  const SavedGamePreview({
    required this.boardLayout,
    required this.moveCount,
    this.lastMove,
    this.white,
    this.black,
    this.result,
    this.sideToMove,
  });

  final String? boardLayout;
  final int moveCount;
  final String? lastMove;
  final String? white;
  final String? black;
  final String? result;
  final PieceColor? sideToMove;

  bool get isOngoing => result?.trim() == '*';
}

class SavedGameSummary {
  const SavedGameSummary({
    required this.path,
    required this.filename,
    required this.modified,
    this.preview,
  });

  final String path;
  final String filename;
  final DateTime modified;
  final SavedGamePreview? preview;

  String get displayName => p.basenameWithoutExtension(filename);

  bool get isOngoing => preview?.isOngoing ?? false;
}

const SavedGameCatalog savedGameCatalog = SavedGameCatalog();

final class SavedGameCatalog {
  const SavedGameCatalog();

  Future<Directory?> recordsDirectory({bool create = true}) async {
    if (kIsWeb) {
      return null;
    }

    final bool isMobilePlatform = Platform.isAndroid || Platform.isIOS;

    if (!isMobilePlatform) {
      final String lastDirectory = DB().generalSettings.lastPgnSaveDirectory;
      if (lastDirectory.isNotEmpty) {
        final Directory lastDir = Directory(lastDirectory);
        if (lastDir.existsSync()) {
          return lastDir;
        }
      }
    }

    final Directory? base = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
    if (base == null) {
      return null;
    }

    final Directory records = Directory(p.join(base.path, 'records'));
    if (!records.existsSync()) {
      if (!create) {
        return null;
      }
      await records.create(recursive: true);
    }
    return records;
  }

  Future<List<SavedGameSummary>> listRecent({
    int? limit,
    bool includePreviews = false,
  }) async {
    assert(limit == null || limit > 0, 'Recent game limit must be positive.');
    final Directory? dir = await recordsDirectory(create: false);
    if (dir == null || !dir.existsSync()) {
      return const <SavedGameSummary>[];
    }

    final List<File> files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.toLowerCase().endsWith('.pgn'))
        .toList();

    files.sort((File a, File b) {
      return b.lastModifiedSync().compareTo(a.lastModifiedSync());
    });

    final Iterable<File> selected = limit == null ? files : files.take(limit);
    final List<SavedGameSummary> summaries = <SavedGameSummary>[];
    for (final File file in selected) {
      summaries.add(
        await _summaryForFile(file, includePreview: includePreviews),
      );
    }
    return summaries;
  }

  Future<String?> computeFinalBoardLayout(String pgnContent) async {
    return previewFromPgnContent(pgnContent).boardLayout;
  }

  SavedGamePreview previewFromPgnContent(String pgnContent) {
    final PgnGame<PgnNodeData> game = PgnGame.parsePgn(pgnContent);
    final _SavedGameReplayPreview replay = _replayMainlinePreview(game);
    return SavedGamePreview(
      boardLayout: replay.boardLayout,
      moveCount: replay.moveCount,
      lastMove: replay.lastMove,
      white: _headerValue(game.headers['White']),
      black: _headerValue(game.headers['Black']),
      result: _headerValue(game.headers['Result']),
      sideToMove: replay.sideToMove,
    );
  }

  Future<SavedGamePreview?> previewForPath(String path) async {
    assert(path.isNotEmpty, 'Saved game preview path must not be empty.');
    try {
      final String content = await File(path).readAsString();
      return previewFromPgnContent(content);
    } on Exception {
      return null;
    }
  }

  Future<SavedGameSummary> _summaryForFile(
    File file, {
    required bool includePreview,
  }) async {
    final SavedGamePreview? preview = includePreview
        ? await previewForPath(file.path)
        : null;
    return SavedGameSummary(
      path: file.path,
      filename: p.basename(file.path),
      modified: file.lastModifiedSync(),
      preview: preview,
    );
  }

  _SavedGameReplayPreview _replayMainlinePreview(PgnGame<PgnNodeData> game) {
    final String? fen = game.headers['FEN'];
    final NativeMillRulesPort port = NativeMillRulesPort(
      ruleSettings: DB().ruleSettings,
      generalSettings: DB().generalSettings,
    );
    int moveCount = 0;
    String? lastMove;
    String? boardLayout = boardLayoutFromMillFen(fen);
    PieceColor? sideToMove;

    try {
      if (fen != null && fen.isNotEmpty) {
        port.setFromFen(fen);
      }
      sideToMove = _pieceColorFromSeat(port.snapshot.activeSeat);

      for (final PgnNodeData node in game.moves.mainline()) {
        final String san = node.san.trim().toLowerCase();
        if (san.isEmpty) {
          continue;
        }
        final List<String> segments = _splitSan(san);
        for (final String segment in segments) {
          final String standard = _toStandardMove(segment);
          if (standard.isEmpty) {
            continue;
          }
          moveCount++;
          lastMove = standard;
          final GameAction? action = _legalActionForMoveString(port, standard);
          if (action == null) {
            continue;
          }
          port.apply(action);
          boardLayout = boardLayoutFromMillFen(port.exportFen()) ?? boardLayout;
          sideToMove = _pieceColorFromSeat(port.snapshot.activeSeat);
        }
      }
    } finally {
      port.dispose();
    }

    return _SavedGameReplayPreview(
      boardLayout: boardLayout,
      moveCount: moveCount,
      lastMove: lastMove,
      sideToMove: sideToMove,
    );
  }

  static GameAction? _legalActionForMoveString(
    NativeMillRulesPort port,
    String move,
  ) {
    for (final GameAction action in port.legalActions) {
      if (MillActionCodec.moveStringFrom(action) == move) {
        return action;
      }
    }
    return null;
  }

  static PieceColor? _pieceColorFromSeat(PlayerSeat seat) {
    return switch (seat) {
      PlayerSeat.first => PieceColor.white,
      PlayerSeat.second => PieceColor.black,
      PlayerSeat.none => null,
    };
  }

  String? boardLayoutFromMillFen(String? fen) {
    if (fen == null || fen.isEmpty || fen.length < 26) {
      return null;
    }
    final int spaceIndex = fen.indexOf(' ');
    final int end = spaceIndex == -1 ? fen.length : spaceIndex;
    if (end < 26) {
      return null;
    }
    return fen.substring(0, 26);
  }

  static List<String> _splitSan(String san) {
    final String cleaned = san.replaceAll(RegExp(r'\{[^}]*\}'), '').trim();

    if (cleaned.contains('x')) {
      if (cleaned.startsWith('x')) {
        final RegExp regex = RegExp(r'(x[a-g][1-7])');
        return regex
            .allMatches(cleaned)
            .map((RegExpMatch match) => match.group(0)!)
            .toList();
      }
      final int firstCapture = cleaned.indexOf('x');
      if (firstCapture > 0) {
        final String firstSegment = cleaned.substring(0, firstCapture);
        final RegExp regex = RegExp(r'(x[a-g][1-7])');
        final String remainingSan = cleaned.substring(firstCapture);
        final List<String> captures = regex
            .allMatches(remainingSan)
            .map((RegExpMatch match) => match.group(0)!)
            .toList();
        return <String>[firstSegment, ...captures];
      }
    }
    return <String>[cleaned];
  }

  static String _toStandardMove(String token) {
    final String move = token.trim().toLowerCase();
    if (move == 'p' ||
        move == '*' ||
        move == 'x' ||
        move == 'xx' ||
        move == 'xxx') {
      return '';
    }
    if (RegExp(r'^x[a-g][1-7]$').hasMatch(move)) {
      return move.substring(0, 3);
    }
    if (RegExp(r'^[a-g][1-7]-[a-g][1-7]$').hasMatch(move)) {
      return move;
    }
    if (RegExp(r'^[a-g][1-7]$').hasMatch(move)) {
      return move;
    }
    if (move == '1-0' || move == '0-1' || move == '1/2-1/2') {
      return '';
    }
    return '';
  }

  static String? _headerValue(String? value) {
    if (value == null || value.isEmpty || value == '?') {
      return null;
    }
    return value;
  }
}

class _SavedGameReplayPreview {
  const _SavedGameReplayPreview({
    required this.boardLayout,
    required this.moveCount,
    required this.lastMove,
    required this.sideToMove,
  });

  final String? boardLayout;
  final int moveCount;
  final String? lastMove;
  final PieceColor? sideToMove;
}
