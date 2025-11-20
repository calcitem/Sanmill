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

import '../models/chat_message.dart';

/// Manages chat session state with intelligent token-aware context management
///
/// Features:
/// - Sliding window context to manage token limits
/// - Approximate token counting for cost optimization
/// - Auto-reset on game changes
/// - Conversation history extraction
class ChatSessionManager {
  factory ChatSessionManager() => _instance;
  ChatSessionManager._internal();

  /// Singleton instance
  static final ChatSessionManager _instance = ChatSessionManager._internal();

  /// Chat message history for the current session
  final List<ChatMessage> _messages = <ChatMessage>[];

  /// Current game identifier (FEN or unique ID) to detect game changes
  String? _currentGameId;

  /// Maximum number of messages to keep in context window
  /// Optimized for ~4000 token context limit (average ~400 tokens per exchange)
  static const int _maxContextMessages = 10;

  /// Maximum total tokens to maintain in context (conservative limit)
  static const int _maxContextTokens = 3500;

  /// Get all messages in the current session
  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);

  /// Add a message to the session with intelligent context management
  void addMessage(ChatMessage message) {
    _messages.add(message);
    _trimContextWindow();
  }

  /// Update an existing message (for streaming updates)
  void updateMessage(String messageId, ChatMessage updatedMessage) {
    final int index = _messages.indexWhere(
      (ChatMessage m) => m.id == messageId,
    );
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
    _currentGameId ??= newGameId;

    return false;
  }

  /// Trim context window using intelligent sliding window with token awareness
  /// Keeps welcome message + most recent messages within token budget
  void _trimContextWindow() {
    if (_messages.length <= 2) {
      return; // Keep at least welcome + 1 exchange
    }

    // Calculate approximate token usage
    final int estimatedTokens = _estimateTotalTokens();

    // If under budget and message count OK, no trimming needed
    if (estimatedTokens <= _maxContextTokens &&
        _messages.length <= _maxContextMessages) {
      return;
    }

    // Keep the first message (welcome message) and most recent messages
    final ChatMessage? welcomeMessage = _messages.isNotEmpty
        ? _messages.first
        : null;
    final List<ChatMessage> recentMessages = _messages.skip(1).toList();

    // Trim by message count
    if (recentMessages.length > (_maxContextMessages - 1)) {
      final int excessCount = recentMessages.length - (_maxContextMessages - 1);
      recentMessages.removeRange(0, excessCount);
    }

    // Additional token-based trimming if still over budget
    while (recentMessages.length > 2 &&
        _estimateTokensForMessages(recentMessages) > _maxContextTokens) {
      // Remove oldest non-welcome messages first (FIFO)
      recentMessages.removeAt(0);
    }

    // Rebuild messages list
    _messages.clear();
    if (welcomeMessage != null) {
      _messages.add(welcomeMessage);
    }
    _messages.addAll(recentMessages);
  }

  /// Estimate total tokens in current context
  /// Uses simplified token estimation: ~4 chars per token (rough approximation)
  int _estimateTotalTokens() {
    return _estimateTokensForMessages(_messages);
  }

  /// Estimate tokens for a list of messages
  /// More accurate estimation considering message structure
  int _estimateTokensForMessages(List<ChatMessage> messageList) {
    int totalChars = 0;

    for (final ChatMessage msg in messageList) {
      // Count content characters
      totalChars += msg.content.length;

      // Add overhead for role markers and formatting (~20 chars per message)
      totalChars += 20;
    }

    // Convert chars to tokens (rough estimate: 4 chars ≈ 1 token)
    // This is conservative for English text; actual ratio varies by content
    return (totalChars / 4).ceil();
  }

  /// Get conversation history as formatted string for context injection
  /// Excludes the welcome message and formats for LLM consumption
  /// Intelligently limits based on token budget
  String getConversationHistory() {
    if (_messages.length <= 1) {
      return '';
    }

    final StringBuffer buffer = StringBuffer();
    buffer.writeln('RECENT CONVERSATION:');

    // Skip welcome message (index 0) and get recent messages
    // Limit to last 6 messages (3 exchanges) to conserve tokens
    final int startIndex = _messages.length > 7 ? _messages.length - 6 : 1;
    int includedMessages = 0;

    for (int i = startIndex; i < _messages.length; i++) {
      final ChatMessage msg = _messages[i];
      if (msg.isStreaming) {
        continue; // Skip incomplete messages
      }

      final String role = msg.isUser ? 'User' : 'Assistant';
      final String truncatedContent = _truncateIfNeeded(msg.content, 300);
      buffer.writeln('$role: $truncatedContent');
      includedMessages++;
    }

    // Return empty if no messages were included
    if (includedMessages == 0) {
      return '';
    }

    return buffer.toString();
  }

  /// Truncate message content if too long to save tokens
  String _truncateIfNeeded(String content, int maxLength) {
    if (content.length <= maxLength) {
      return content;
    }
    return '${content.substring(0, maxLength)}... [truncated]';
  }

  /// Get current token usage estimate for monitoring
  int get estimatedTokenUsage => _estimateTotalTokens();

  /// Get token budget remaining
  int get tokenBudgetRemaining {
    final int used = estimatedTokenUsage;
    return _maxContextTokens - used;
  }

  /// Check if context is approaching token limit (>80% usage)
  bool get isNearTokenLimit => estimatedTokenUsage > (_maxContextTokens * 0.8);

  /// Get number of messages in current session
  int get messageCount => _messages.length;

  /// Check if session is empty
  bool get isEmpty => _messages.isEmpty;

  /// Get current game ID
  String? get currentGameId => _currentGameId;

  /// Get statistics for debugging/monitoring
  Map<String, dynamic> getSessionStats() {
    return <String, dynamic>{
      'messageCount': messageCount,
      'estimatedTokens': estimatedTokenUsage,
      'tokenBudgetRemaining': tokenBudgetRemaining,
      'isNearLimit': isNearTokenLimit,
      'gameId': _currentGameId,
    };
  }
}
