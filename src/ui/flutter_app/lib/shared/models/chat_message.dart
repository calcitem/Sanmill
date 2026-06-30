// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

/// Chat message model for AI chat assistant
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.isStreaming = false,
  });

  /// Unique identifier for the message
  final String id;

  /// Message content
  final String content;

  /// Whether this message is from the user (true) or AI assistant (false)
  final bool isUser;

  /// Timestamp when the message was created
  final DateTime timestamp;

  /// Whether the message is currently streaming (being received)
  final bool isStreaming;

  /// Create a copy of this message with updated fields
  ChatMessage copyWith({
    String? id,
    String? content,
    bool? isUser,
    DateTime? timestamp,
    bool? isStreaming,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}
