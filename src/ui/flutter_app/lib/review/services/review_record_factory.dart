// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_page/services/import_export/pgn.dart';
import '../../game_page/services/mill.dart';
import '../../puzzle/models/rule_variant.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../models/review_models.dart';

abstract final class ReviewRecordFactory {
  static PrivateGameRecord fromCurrentGame({String? importedSourcePgn}) {
    final GameController controller = GameController();
    final GameRecorder recorder = controller.gameRecorder;
    final Game game = controller.gameInstance;
    final Player whitePlayer = game.getPlayerByColor(PieceColor.white);
    final Player blackPlayer = game.getPlayerByColor(PieceColor.black);
    String result = recorder.gameResultPgn;
    String white = whitePlayer.isAi ? 'AI' : 'Human';
    String black = blackPlayer.isAi ? 'AI' : 'Human';
    Set<ReviewSide> humanSides = <ReviewSide>{
      if (!whitePlayer.isAi) ReviewSide.white,
      if (!blackPlayer.isAi) ReviewSide.black,
    };
    final String source = importedSourcePgn?.trim() ?? '';
    if (source.isNotEmpty) {
      try {
        final PgnGame<PgnNodeData> importedGame = PgnGame.parsePgn(source);
        white = _nonEmptyHeader(importedGame.headers['White']) ?? white;
        black = _nonEmptyHeader(importedGame.headers['Black']) ?? black;
        result = _pgnResult(importedGame.headers['Result']) ?? result;
        humanSides = <ReviewSide>{
          if (white.toLowerCase() != 'ai') ReviewSide.white,
          if (black.toLowerCase() != 'ai') ReviewSide.black,
        };
      } on FormatException {
        // Non-PGN formats such as PlayOK still archive the normalized game.
      }
    }
    final String movetext = _movetextWithResult(
      recorder.moveHistoryText,
      result,
    );
    final String sourcePgn = ImportService.addTagPairs(
      movetext,
      resultOverride: result,
    );
    final String? finalBoardLayout = recorder.mainlineMoves.isEmpty
        ? _boardLayout(controller.activeBoardView.fen)
        : recorder.mainlineMoves.last.boardLayout ??
              _boardLayout(controller.activeBoardView.fen);

    return PrivateGameRecord.create(
      sourcePgn: sourcePgn,
      initialFen: recorder.setupPosition,
      result: result,
      rules: controller.ruleSettingsForActiveBoard,
      completedAt: DateTime.now(),
      white: white,
      black: black,
      humanSides: humanSides,
      finalBoardLayout: finalBoardLayout,
      moveCount: recorder.mainlineMoves.length,
    );
  }

  static PrivateGameRecord fromPgn({
    required String sourcePgn,
    required RuleSettings currentRules,
    required DateTime completedAt,
    String? finalBoardLayout,
  }) {
    final PgnGame<PgnNodeData> game = PgnGame.parsePgn(sourcePgn);
    final String white = game.headers['White']?.trim() ?? '?';
    final String black = game.headers['Black']?.trim() ?? '?';
    final Set<ReviewSide> humanSides = <ReviewSide>{
      if (white.toLowerCase() != 'ai') ReviewSide.white,
      if (black.toLowerCase() != 'ai') ReviewSide.black,
    };
    final RuleSettings rules =
        RuleVariant.canonicalSettingsFromPgn(game.headers['Variant']) ??
        currentRules;
    return PrivateGameRecord.create(
      sourcePgn: sourcePgn,
      initialFen: game.headers['FEN'],
      result: game.headers['Result'] ?? '*',
      rules: rules,
      completedAt: completedAt,
      white: white,
      black: black,
      humanSides: humanSides,
      finalBoardLayout: finalBoardLayout,
      moveCount: game.moves.mainline().length,
    );
  }

  static String? _boardLayout(String? fen) {
    if (fen == null || fen.isEmpty) {
      return null;
    }
    final String board = fen.trim().split(RegExp(r'\s+')).first;
    return board.length == 26 ? board : null;
  }

  static String? _nonEmptyHeader(String? value) {
    final String normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  static String? _pgnResult(String? value) {
    final String normalized = value?.trim() ?? '';
    return switch (normalized) {
      '1-0' || '0-1' || '1/2-1/2' || '*' => normalized,
      _ => null,
    };
  }

  static String _movetextWithResult(String movetext, String result) {
    return movetext.replaceFirst(RegExp(r'(?:1-0|0-1|1/2-1/2|\*)\s*$'), result);
  }
}
