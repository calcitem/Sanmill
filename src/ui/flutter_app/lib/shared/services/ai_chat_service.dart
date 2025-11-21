// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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
import '../config/prompt_defaults.dart';
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
  /// Incorporates user-configured LLM prompts for enhanced strategic understanding
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

      // Get user-configured prompts (or defaults)
      final String strategicKnowledge = _getStrategicKnowledgePrompt();

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

      // Start with strategic knowledge (user-configured or default)
      prompt.writeln(strategicKnowledge);
      prompt.writeln('\n---\n');

      // Add current game state
      prompt.writeln(
        '''
CURRENT GAME STATE:
- FEN Position: $fen
- Side to Move: $sideToMove
- Game Phase: $phase
- Current Action: $action
- White: $whitePiecesOnBoard on board, $whitePiecesInHand in hand
- Black: $blackPiecesOnBoard on board, $blackPiecesInHand in hand''',
      );

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

      // Add AI chat assistant specific instructions
      prompt.writeln(
        '''

---

AI CHAT ASSISTANT ROLE:
You are an expert Nine Men's Morris assistant providing context-aware strategic advice. Use the strategic knowledge and board reference above to analyze the current position and provide high-quality answers.

RESPONSE GUIDELINES:
1. Board Position Analysis:
   - Use the board reference to identify key positions and their connectivity
   - Analyze formed mills and potential mill formations using the mill combinations list
   - Evaluate piece distribution on cross points (d6, f4, d2, b4) vs corners
   - Assess mobility using the adjacency information provided

2. Strategic Recommendations:
   - Apply the strategic concepts (double mills, running mills, forks, etc.)
   - Consider phase-specific priorities from the strategic knowledge
   - Provide specific move suggestions with square notation (e.g., "d5-d4")
   - Explain reasoning using the evaluation criteria (material, mobility, mill threats)
   - Reference specific lines and positions from the board reference

3. Tactical Analysis:
   - Identify immediate threats and defensive needs
   - Count potential mills using the mill combinations reference
   - Suggest concrete alternatives when multiple good moves exist
   - Consider rule-specific tactics based on active variant

4. Response Style:
   - Be concise yet informative (2-4 paragraphs max unless asked for detail)
   - Use clear, strategic language from the expert reference
   - Reference specific board positions by notation (e.g., "the d6 cross point")
   - Use Markdown formatting for clarity (bold, lists, etc.)
   - Provide actionable, accurate advice grounded in the position

Apply the strategic knowledge, board reference, and analysis framework to provide expert guidance.''',
      );

      return prompt.toString();
    } catch (e) {
      // If any error occurs while accessing game state, fall back to default prompt
      return _getDefaultSystemPrompt();
    }
  }

  /// Get strategic knowledge prompt from user configuration or defaults
  /// Returns the LLM prompt header which contains comprehensive strategic knowledge
  String _getStrategicKnowledgePrompt() {
    try {
      final String configuredHeader = DB().generalSettings.llmPromptHeader;

      // If user has configured a custom prompt, use it
      if (configuredHeader.isNotEmpty) {
        return configuredHeader;
      }

      // Otherwise use the default strategic knowledge
      return PromptDefaults.llmPromptHeader;
    } catch (e) {
      // Fall back to default if any error occurs
      return PromptDefaults.llmPromptHeader;
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
