// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_page/services/import_export/pgn.dart';
import '../../game_page/services/mill.dart';
import '../../puzzle/models/rule_variant.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../models/review_models.dart';

abstract final class ReviewRecordFactory {
  static PrivateGameRecord fromCurrentGame() {
    final GameController controller = GameController();
    final GameRecorder recorder = controller.gameRecorder;
    final Game game = controller.gameInstance;
    final Player whitePlayer = game.getPlayerByColor(PieceColor.white);
    final Player blackPlayer = game.getPlayerByColor(PieceColor.black);
    final String movetext = recorder.moveHistoryText;
    final String sourcePgn = ImportService.addTagPairs(movetext);
    final Set<ReviewSide> humanSides = <ReviewSide>{
      if (!whitePlayer.isAi) ReviewSide.white,
      if (!blackPlayer.isAi) ReviewSide.black,
    };
    final String? finalBoardLayout = recorder.mainlineMoves.isEmpty
        ? _boardLayout(controller.activeBoardView.fen)
        : recorder.mainlineMoves.last.boardLayout ??
              _boardLayout(controller.activeBoardView.fen);

    return PrivateGameRecord.create(
      sourcePgn: sourcePgn,
      initialFen: recorder.setupPosition,
      result: recorder.gameResultPgn,
      rules: controller.ruleSettingsForActiveBoard,
      completedAt: DateTime.now(),
      white: whitePlayer.isAi ? 'AI' : 'Human',
      black: blackPlayer.isAi ? 'AI' : 'Human',
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
}
