// This file is part of Sanmill.
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import '../../game_page/services/mill.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../database/database.dart';
import 'chat_session_manager.dart';
import 'llm_service.dart';

/// AI chat assistant service for discussing game strategy and positions
/// Features deep game integration with move history, variant rules, and context management
class AiChatService {
  factory AiChatService() => _instance;
  AiChatService._internal();

  /// Singleton instance
  static final AiChatService _instance = AiChatService._internal();

  final LlmService _llmService = LlmService();
  final ChatSessionManager _sessionManager = ChatSessionManager();

  /// Generate a comprehensive system prompt with deep game integration
  /// Includes board state, move history, variant rules, and conversation context
  String _generateSystemPrompt() {
    try {
      final GameController controller = GameController();

      // Safety check: ensure controller is ready and not disposed
      if (!controller.isControllerReady || controller.isDisposed) {
        return _getDefaultSystemPrompt();
      }

      final Position position = controller.position;
      final String? fen = position.fen;

      // Check if game has changed and auto-reset session if needed
      if (_sessionManager.checkAndResetIfGameChanged(fen)) {
        // Session was reset due to new game
      }

      // If FEN is not available, fall back to default prompt
      if (fen == null || fen.isEmpty) {
        return _getDefaultSystemPrompt();
      }

      // Get current game state
      final String sideToMove = position.sideToMove == PieceColor.white
          ? "White"
          : "Black";
      final String phase = _getPhaseDescription(position.phase);
      final String action = _getActionDescription(position.action);

      final int whitePiecesOnBoard =
          position.pieceOnBoardCount[PieceColor.white] ?? 0;
      final int whitePiecesInHand =
          position.pieceInHandCount[PieceColor.white] ?? 0;
      final int blackPiecesOnBoard =
          position.pieceOnBoardCount[PieceColor.black] ?? 0;
      final int blackPiecesInHand =
          position.pieceInHandCount[PieceColor.black] ?? 0;

      // Get move history
      final String moveHistory = _getMoveHistory(controller.gameRecorder);

      // Get active variant rules
      final String variantRules = _getVariantRulesDescription();

      // Get recent conversation history for context continuity
      final String conversationHistory = _sessionManager
          .getConversationHistory();

      // Build comprehensive system prompt
      final StringBuffer prompt = StringBuffer();

      prompt.writeln('''
You are an expert Nine Men's Morris (Mill) game assistant with deep knowledge of game strategy, tactics, and variants. Your role is to provide context-aware, strategic advice based on the current game state.

CURRENT GAME STATE:
- FEN Position: $fen
- Side to Move: $sideToMove
- Game Phase: $phase
- Current Action: $action
- White: $whitePiecesOnBoard on board, $whitePiecesInHand in hand
- Black: $blackPiecesOnBoard on board, $blackPiecesInHand in hand''');

      // Add move history if available
      if (moveHistory.isNotEmpty) {
        prompt.writeln('\n$moveHistory');
      }

      // Add variant-specific rules
      if (variantRules.isNotEmpty) {
        prompt.writeln('\n$variantRules');
      }

      // Add conversation history for context
      if (conversationHistory.isNotEmpty) {
        prompt.writeln('\n$conversationHistory');
      }

      prompt.writeln(
        '''
STRATEGIC ANALYSIS GUIDELINES:
1. Board Position Analysis:
   - Identify formed mills and potential mill formations
   - Evaluate piece distribution and control of key positions
   - Assess blocking and mobility advantages

2. Phase-Specific Strategy:
   - Placing Phase: Focus on building mill potential, controlling corners/centers
   - Moving Phase: Emphasize mill formation, piece mobility, opponent restriction
   - Flying Phase (3 pieces): Exploit mobility advantage, create unstoppable threats

3. Tactical Considerations:
   - Count potential mills for each side
   - Identify forced sequences and threats
   - Evaluate endgame winning chances
   - Consider rule-specific tactics based on active variant

4. Move Recommendations:
   - Provide specific move suggestions with square notation (e.g., "d5-d4")
   - Explain the strategic reasoning behind suggestions
   - Consider both offensive (mill formation) and defensive (blocking) moves
   - Adapt advice to the current rule variant

RESPONSE STYLE:
- Be concise yet informative (2-4 paragraphs max unless asked for detail)
- Use clear, strategic language
- Reference specific board positions when relevant
- Provide actionable advice based on current game state
- Use Markdown formatting for clarity (bold, lists, etc.)

Provide expert, context-aware advice to help the player improve their position.''',
      );

      return prompt.toString();
    } catch (e) {
      // If any error occurs while accessing game state, fall back to default prompt
      return _getDefaultSystemPrompt();
    }
  }

  String _getDefaultSystemPrompt() {
    return '''
You are an expert Nine Men's Morris (Mill) game assistant. Help players learn strategies, understand rules, and improve their gameplay.

NINE MEN'S MORRIS RULES:
1. The game has three phases: Placing (9 pieces each), Moving, and Flying (when down to 3 pieces)
2. A "mill" is formed when three pieces are in a row (horizontally or vertically)
3. Forming a mill allows you to remove an opponent's piece
4. The goal is to reduce the opponent to 2 pieces or block all their moves

Provide helpful advice about Nine Men's Morris strategy and tactics.''';
  }

  String _getPhaseDescription(Phase phase) {
    switch (phase) {
      case Phase.placing:
        return "Placing Phase - Players are placing their initial pieces";
      case Phase.moving:
        return "Moving Phase - All pieces placed, players are moving pieces";
      case Phase.gameOver:
        return "Game Over";
      case Phase.ready:
        return "Ready to Start";
    }
  }

  String _getActionDescription(Act action) {
    switch (action) {
      case Act.place:
        return "Place a piece on the board";
      case Act.select:
        return "Select a piece to move";
      case Act.remove:
        return "Remove an opponent's piece (mill formed)";
    }
  }

  /// Get move history from game recorder
  /// Returns formatted move history string or empty if no history
  String _getMoveHistory(GameRecorder recorder) {
    try {
      final List<ExtMove> moves = recorder.mainlineMoves;

      if (moves.isEmpty) {
        return '';
      }

      final StringBuffer buffer = StringBuffer();
      buffer.writeln('\nMOVE HISTORY:');

      // Show last 10 moves to avoid token bloat
      final int startIndex = moves.length > 10 ? moves.length - 10 : 0;

      for (int i = startIndex; i < moves.length; i++) {
        final ExtMove move = moves[i];
        final int moveNumber = i + 1;

        // Format move notation
        buffer.writeln('$moveNumber. ${_formatMove(move)}');
      }

      if (startIndex > 0) {
        buffer.writeln(
          '(Showing last ${moves.length - startIndex} of ${moves.length} moves)',
        );
      }

      return buffer.toString();
    } catch (e) {
      return '';
    }
  }

  /// Format a move for display
  String _formatMove(ExtMove move) {
    try {
      // Basic move formatting - can be enhanced with more detail
      return move.notation;
    } catch (e) {
      return move.move;
    }
  }

  /// Get description of active variant rules
  /// Returns formatted rules string highlighting deviations from standard Nine Men's Morris
  String _getVariantRulesDescription() {
    try {
      final RuleSettings rules = DB().ruleSettings;
      final StringBuffer buffer = StringBuffer();

      // Detect variant type
      final bool isStandard =
          rules.piecesCount == 9 &&
          !rules.hasDiagonalLines &&
          !rules.mayMoveInPlacingPhase;

      if (isStandard &&
          !rules.enableCustodianCapture &&
          !rules.enableInterventionCapture &&
          !rules.enableLeapCapture) {
        return ''; // Standard Nine Men's Morris, no special rules needed
      }

      buffer.writeln('\nACTIVE VARIANT RULES:');

      // Variant identification
      if (rules.piecesCount == 12) {
        buffer.writeln("- Variant: Twelve Men's Morris (12 pieces per player)");
      } else if (rules.piecesCount == 6) {
        buffer.writeln("- Variant: Six Men's Morris (6 pieces per player)");
      } else if (rules.hasDiagonalLines) {
        buffer.writeln('- Variant: Morabaraba (with diagonal lines)');
      }

      // Special rules
      if (rules.mayMoveInPlacingPhase) {
        buffer.writeln('- Players can move pieces during placing phase');
      }

      if (rules.mayRemoveMultiple) {
        buffer.writeln('- Multiple pieces can be removed in one turn');
      }

      if (rules.mayRemoveFromMillsAlways) {
        buffer.writeln('- Pieces in mills can always be removed');
      }

      if (!rules.mayFly) {
        buffer.writeln(
          '- Flying is disabled (pieces cannot move anywhere when down to 3)',
        );
      }

      if (rules.flyPieceCount != 3) {
        buffer.writeln(
          '- Flying enabled at ${rules.flyPieceCount} pieces (not standard 3)',
        );
      }

      // Capture variants
      if (rules.enableCustodianCapture) {
        buffer.writeln(
          '- Custodian capture enabled (sandwich opponent pieces)',
        );
      }

      if (rules.enableInterventionCapture) {
        buffer.writeln('- Intervention capture enabled');
      }

      if (rules.enableLeapCapture) {
        buffer.writeln('- Leap capture enabled (jump over pieces)');
      }

      // Stalemate and board full actions
      final StalemateAction? stalemateAction = rules.stalemateAction;
      if (stalemateAction != null &&
          stalemateAction != StalemateAction.endWithStalemateLoss) {
        buffer.writeln(
          '- Stalemate action: ${_getStalemateActionDescription(stalemateAction)}',
        );
      }

      return buffer.toString();
    } catch (e) {
      return '';
    }
  }

  /// Get human-readable stalemate action description
  String _getStalemateActionDescription(StalemateAction action) {
    switch (action) {
      case StalemateAction.endWithStalemateLoss:
        return 'Loss for player with no moves';
      case StalemateAction.changeSideToMove:
        return 'Change side to move';
      case StalemateAction.removeOpponentsPieceAndMakeNextMove:
        return 'Remove opponent piece and continue';
      case StalemateAction.removeOpponentsPieceAndChangeSideToMove:
        return 'Remove opponent piece and change turn';
      case StalemateAction.endWithStalemateDraw:
        return 'Draw';
    }
  }

  /// Get session manager for external access (e.g., dialog)
  ChatSessionManager get sessionManager => _sessionManager;

  /// Send a chat message and get streaming response
  /// Returns a `Stream<String>` of response chunks for typewriter effect
  Stream<String> sendMessage(String userMessage) async* {
    final String systemPrompt = _generateSystemPrompt();

    // Use the LLM service with custom system prompt for context-aware responses
    await for (final String chunk
        in _llmService.generateResponseWithCustomPrompt(
          systemPrompt: systemPrompt,
          userPrompt: userMessage,
        )) {
      yield chunk;
    }
  }

  /// Check if the LLM is configured and ready to use
  bool isConfigured() {
    return _llmService.isLlmConfigured();
  }
}
