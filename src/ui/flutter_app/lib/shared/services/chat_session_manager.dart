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

import 'package:sanmill/shared/models/chat_message.dart';

/// Manages chat session state, token limits, and auto-reset functionality
class ChatSessionManager {
  /// Singleton instance
  static final ChatSessionManager _instance = ChatSessionManager._internal();
  factory ChatSessionManager() => _instance;
  ChatSessionManager._internal();

  /// Chat message history for the current session
  final List<ChatMessage> _messages = <ChatMessage>[];

  /// Current game identifier (FEN or unique ID) to detect game changes
  String? _currentGameId;

  /// Maximum number of messages to keep in context window
  /// Helps manage token limits (approximately 4000 tokens with overhead)
  static const int _maxContextMessages = 10;

  /// Get all messages in the current session
  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);

  /// Add a message to the session
  void addMessage(ChatMessage message) {
    _messages.add(message);
    _trimContextWindow();
  }

  /// Update an existing message (for streaming updates)
  void updateMessage(String messageId, ChatMessage updatedMessage) {
    final int index = _messages.indexWhere((ChatMessage m) => m.id == messageId);
    if (index != -1) {
      _messages[index] = updatedMessage;
    }
  }

  /// Remove a message by ID
  void removeMessage(String messageId) {
    _messages.removeWhere((ChatMessage m) => m.id == messageId);
  }

  /// Clear all messages in the session
  void clearSession() {
    _messages.clear();
    _currentGameId = null;
  }

  /// Check if we should reset the session based on game state change
  /// Returns true if session was reset
  bool checkAndResetIfGameChanged(String? newGameId) {
    if (newGameId == null) {
      return false;
    }

    // If game ID has changed, reset the session
    if (_currentGameId != null && _currentGameId != newGameId) {
      clearSession();
      _currentGameId = newGameId;
      return true;
    }

    // Set initial game ID
    if (_currentGameId == null) {
      _currentGameId = newGameId;
    }

    return false;
  }

  /// Trim context window to manage token limits using sliding window
  /// Keeps welcome message + most recent messages within limit
  void _trimContextWindow() {
    if (_messages.length <= _maxContextMessages) {
      return;
    }

    // Keep the first message (welcome message) and most recent messages
    final ChatMessage? welcomeMessage = _messages.isNotEmpty ? _messages.first : null;
    final List<ChatMessage> recentMessages = _messages.skip(1).toList();

    // Keep only the most recent messages
    final int excessCount = recentMessages.length - (_maxContextMessages - 1);
    if (excessCount > 0) {
      recentMessages.removeRange(0, excessCount);
    }

    // Rebuild messages list
    _messages.clear();
    if (welcomeMessage != null) {
      _messages.add(welcomeMessage);
    }
    _messages.addAll(recentMessages);
  }

  /// Get conversation history as formatted string for context injection
  /// Excludes the welcome message and formats for LLM consumption
  String getConversationHistory() {
    if (_messages.length <= 1) {
      return '';
    }

    final StringBuffer buffer = StringBuffer();
    buffer.writeln('RECENT CONVERSATION:');

    // Skip welcome message (index 0) and get up to last 6 messages for context
    final int startIndex = _messages.length > 7 ? _messages.length - 6 : 1;
    for (int i = startIndex; i < _messages.length; i++) {
      final ChatMessage msg = _messages[i];
      if (msg.isStreaming) continue; // Skip incomplete messages

      final String role = msg.isUser ? 'User' : 'Assistant';
      buffer.writeln('$role: ${msg.content}');
    }

    return buffer.toString();
  }

  /// Get number of messages in current session
  int get messageCount => _messages.length;

  /// Check if session is empty
  bool get isEmpty => _messages.isEmpty;

  /// Get current game ID
  String? get currentGameId => _currentGameId;
}
