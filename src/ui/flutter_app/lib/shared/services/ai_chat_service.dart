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

import 'package:sanmill/game_page/services/controller/game_controller.dart';
import 'package:sanmill/game_page/services/engine/position.dart';
import 'package:sanmill/game_page/services/engine/types.dart';
import 'package:sanmill/shared/services/llm_service.dart';

/// AI chat assistant service for discussing game strategy and positions
class AiChatService {
  /// Singleton instance
  static final AiChatService _instance = AiChatService._internal();
  factory AiChatService() => _instance;
  AiChatService._internal();

  final LlmService _llmService = LlmService();

  /// Generate a system prompt that includes the current board state
  String _generateSystemPrompt() {
    try {
      final GameController controller = GameController();

      // Safety check: ensure controller is ready and not disposed
      if (!controller.isControllerReady || controller.isDisposed) {
        return _getDefaultSystemPrompt();
      }

      final Position position = controller.position;
      final String? fen = position.fen;

      // If FEN is not available, fall back to default prompt
      if (fen == null || fen.isEmpty) {
        return _getDefaultSystemPrompt();
      }

      // Get game state information
      final String sideToMove = position.sideToMove == PieceColor.white
          ? "White"
          : "Black";
      final String phase = _getPhaseDescription(position.phase);
      final String action = _getActionDescription(position.action);

      final int whitePiecesOnBoard = position.pieceOnBoardCount[PieceColor.white] ?? 0;
      final int whitePiecesInHand = position.pieceInHandCount[PieceColor.white] ?? 0;
      final int blackPiecesOnBoard = position.pieceOnBoardCount[PieceColor.black] ?? 0;
      final int blackPiecesInHand = position.pieceInHandCount[PieceColor.black] ?? 0;

    return '''You are an expert Nine Men's Morris (Mill) game assistant. Help the player analyze positions, suggest strategies, and answer questions about the game.

CURRENT GAME STATE:
- FEN Position: $fen
- Side to Move: $sideToMove
- Game Phase: $phase
- Current Action: $action
- White Pieces: $whitePiecesOnBoard on board, $whitePiecesInHand in hand
- Black Pieces: $blackPiecesOnBoard on board, $blackPiecesInHand in hand

NINE MEN'S MORRIS RULES:
1. The game has three phases: Placing (9 pieces each), Moving, and Flying (when down to 3 pieces)
2. A "mill" is formed when three pieces are in a row (horizontally or vertically)
3. Forming a mill allows you to remove an opponent's piece
4. The goal is to reduce the opponent to 2 pieces or block all their moves

When analyzing positions:
- Consider the current board position shown in the FEN string
- Evaluate piece placement and potential mills
- Suggest strategic moves based on the current phase
- Explain the reasoning behind your suggestions
- Be concise but informative

Provide helpful, context-aware advice based on the current game state.''';
    } catch (e) {
      // If any error occurs while accessing game state, fall back to default prompt
      return _getDefaultSystemPrompt();
    }
  }

  String _getDefaultSystemPrompt() {
    return '''You are an expert Nine Men's Morris (Mill) game assistant. Help players learn strategies, understand rules, and improve their gameplay.

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

  /// Send a chat message and get streaming response
  /// Returns a Stream<String> of response chunks for typewriter effect
  Stream<String> sendMessage(String userMessage) async* {
    final String systemPrompt = _generateSystemPrompt();

    // Use the LLM service with custom system prompt for context-aware responses
    await for (final String chunk in _llmService.generateResponseWithCustomPrompt(
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
