// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_page/services/mill.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../database/database.dart';
import '../models/llm_analysis.dart';
import 'llm_service.dart';

/// Builds the minimal typed game context accepted by [LlmService].
class AiChatService {
  factory AiChatService() => _instance;
  AiChatService._();

  static final AiChatService _instance = AiChatService._();
  final LlmService _llmService = LlmService();

  Future<LlmAnalysisResult> analyze({
    required LlmTask task,
    required String locale,
  }) {
    return _llmService.analyze(
      LlmAnalysisRequest(
        task: task,
        locale: locale,
        gameContext: _buildGameContext(task),
      ),
    );
  }

  LlmGameContext _buildGameContext(LlmTask task) {
    final GameController controller = GameController();
    final String? fen = controller.activeFen;
    if (!controller.isControllerReady ||
        controller.isDisposed ||
        fen == null ||
        fen.isEmpty) {
      throw const LlmException(LlmErrorCode.invalidResponse);
    }

    final MillBoardView view = controller.activeBoardView;
    final RuleSettings rules = DB().ruleSettings;
    final List<ExtMove> allMoves = controller.gameRecorder.mainlineMoves;
    final int limit = task == LlmTask.gameReview ? 120 : 10;
    final int start = allMoves.length > limit ? allMoves.length - limit : 0;
    final List<String> moves = <String>[
      for (int i = start; i < allMoves.length; i++)
        '${i + 1}. ${allMoves[i].notation}',
    ];

    return LlmGameContext(
      fen: fen,
      variant: _variantName(rules),
      sideToMove: view.sideToMove == PieceColor.white ? 'white' : 'black',
      phase: view.phase.name,
      action: view.action.name,
      whitePiecesOnBoard: view.pieceOnBoardCountFor(PieceColor.white),
      whitePiecesInHand: view.pieceInHandCountFor(PieceColor.white),
      blackPiecesOnBoard: view.pieceOnBoardCountFor(PieceColor.black),
      blackPiecesInHand: view.pieceInHandCountFor(PieceColor.black),
      rules: <String, Object?>{
        'piecesPerSide': rules.piecesCount,
        'diagonalLines': rules.hasDiagonalLines,
        'moveDuringPlacing': rules.mayMoveInPlacingPhase,
        'removeMultiple': rules.mayRemoveMultiple,
        'removeFromMillAlways': rules.mayRemoveFromMillsAlways,
        'flyingEnabled': rules.mayFly,
        'flyingPieceCount': rules.flyPieceCount,
        'custodianCapture': rules.enableCustodianCapture,
        'interventionCapture': rules.enableInterventionCapture,
        'leapCapture': rules.enableLeapCapture,
        'stalemateAction': rules.stalemateAction?.name,
      },
      moves: moves,
      movesTruncated: start > 0,
    );
  }

  String _variantName(RuleSettings rules) {
    if (rules.piecesCount == 12) {
      return 'twelve_mens_morris';
    }
    if (rules.piecesCount == 6) {
      return 'six_mens_morris';
    }
    if (rules.hasDiagonalLines) {
      return 'diagonal_mill_variant';
    }
    return 'nine_mens_morris';
  }

  bool isConfigured() => _llmService.isLlmConfigured();
}
