// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// chat_session_manager_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/models/chat_message.dart';
import 'package:sanmill/shared/services/chat_session_manager.dart';

void main() {
  late ChatSessionManager manager;

  setUp(() {
    manager = ChatSessionManager();
    manager.clearSession();
  });

  ChatMessage _makeMessage({
    required String id,
    required String content,
    bool isUser = true,
    bool isStreaming = false,
  }) {
    return ChatMessage(
      id: id,
      content: content,
      isUser: isUser,
      timestamp: DateTime.now(),
      isStreaming: isStreaming,
    );
  }

  // ---------------------------------------------------------------------------
  // Basic session management
  // ---------------------------------------------------------------------------
  group('Basic session management', () {
    test('should start empty', () {
      expect(manager.isEmpty, isTrue);
      expect(manager.messageCount, 0);
      expect(manager.messages, isEmpty);
    });

    test('addMessage should increase message count', () {
      manager.addMessage(_makeMessage(id: '1', content: 'Hello'));

      expect(manager.messageCount, 1);
      expect(manager.isEmpty, isFalse);
    });

    test('addMessage should preserve message content', () {
      final ChatMessage msg = _makeMessage(id: '1', content: 'Test content');
      manager.addMessage(msg);

      expect(manager.messages.first.content, 'Test content');
      expect(manager.messages.first.id, '1');
    });

    test('messages should be unmodifiable', () {
      manager.addMessage(_makeMessage(id: '1', content: 'Hello'));

      // The returned list should be unmodifiable
      expect(
        () => manager.messages.add(
          _makeMessage(id: '2', content: 'Injected'),
        ),
        throwsUnsupportedError,
      );
    });

    test('clearSession should remove all messages', () {
      manager.addMessage(_makeMessage(id: '1', content: 'Hello'));
      manager.addMessage(_makeMessage(id: '2', content: 'World'));

      manager.clearSession();

      expect(manager.isEmpty, isTrue);
      expect(manager.messageCount, 0);
      expect(manager.currentGameId, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Update and remove messages
  // ---------------------------------------------------------------------------
  group('Update and remove messages', () {
    test('updateMessage should replace the correct message', () {
      manager.addMessage(_makeMessage(id: '1', content: 'Original'));
      manager.addMessage(_makeMessage(id: '2', content: 'Other'));

      final ChatMessage updated = _makeMessage(id: '1', content: 'Updated');
      manager.updateMessage('1', updated);

      expect(manager.messages[0].content, 'Updated');
      expect(manager.messages[1].content, 'Other');
    });

    test('updateMessage should be a no-op for non-existent ID', () {
      manager.addMessage(_makeMessage(id: '1', content: 'Original'));

      final ChatMessage updated = _makeMessage(
        id: 'nonexistent',
        content: 'Updated',
      );
      manager.updateMessage('nonexistent', updated);

      expect(manager.messageCount, 1);
      expect(manager.messages[0].content, 'Original');
    });

    test('removeMessage should remove the correct message', () {
      manager.addMessage(_makeMessage(id: '1', content: 'First'));
      manager.addMessage(_makeMessage(id: '2', content: 'Second'));
      manager.addMessage(_makeMessage(id: '3', content: 'Third'));

      manager.removeMessage('2');

      expect(manager.messageCount, 2);
      expect(manager.messages[0].id, '1');
      expect(manager.messages[1].id, '3');
    });

    test('removeMessage should be a no-op for non-existent ID', () {
      manager.addMessage(_makeMessage(id: '1', content: 'First'));

      manager.removeMessage('nonexistent');

      expect(manager.messageCount, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Game change detection
  // ---------------------------------------------------------------------------
  group('Game change detection', () {
    test('first game ID should be set without reset', () {
      final bool reset = manager.checkAndResetIfGameChanged('game-1');

      expect(reset, isFalse);
      expect(manager.currentGameId, 'game-1');
    });

    test('same game ID should not trigger reset', () {
      manager.checkAndResetIfGameChanged('game-1');
      manager.addMessage(_makeMessage(id: '1', content: 'Hello'));

      final bool reset = manager.checkAndResetIfGameChanged('game-1');

      expect(reset, isFalse);
      expect(manager.messageCount, 1); // Message preserved
    });

    test('different game ID should trigger reset', () {
      manager.checkAndResetIfGameChanged('game-1');
      manager.addMessage(_makeMessage(id: '1', content: 'Hello'));

      final bool reset = manager.checkAndResetIfGameChanged('game-2');

      expect(reset, isTrue);
      expect(manager.messageCount, 0); // Messages cleared
      expect(manager.currentGameId, 'game-2');
    });

    test('null game ID should not trigger reset', () {
      manager.checkAndResetIfGameChanged('game-1');
      manager.addMessage(_makeMessage(id: '1', content: 'Hello'));

      final bool reset = manager.checkAndResetIfGameChanged(null);

      expect(reset, isFalse);
      expect(manager.messageCount, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Context window trimming
  // ---------------------------------------------------------------------------
  group('Context window trimming', () {
    test('should keep messages under limit', () {
      // Add more messages than the max context window
      for (int i = 0; i < 15; i++) {
        manager.addMessage(
          _makeMessage(id: '$i', content: 'Message $i'),
        );
      }

      // Should be trimmed to max context messages or less
      expect(manager.messageCount, lessThanOrEqualTo(10));
    });

    test('should preserve welcome message during trimming', () {
      // Add welcome message
      manager.addMessage(
        _makeMessage(
          id: 'welcome',
          content: 'Welcome to the game!',
          isUser: false,
        ),
      );

      // Add many subsequent messages
      for (int i = 0; i < 15; i++) {
        manager.addMessage(
          _makeMessage(id: '$i', content: 'Chat message $i'),
        );
      }

      // Welcome message should still be first
      expect(manager.messages.first.id, 'welcome');
    });

    test('token-based trimming with long messages', () {
      // Add a welcome message
      manager.addMessage(
        _makeMessage(id: 'welcome', content: 'Hi', isUser: false),
      );

      // Add very long messages to exceed token budget
      final String longContent = 'A' * 2000; // ~500 tokens each
      for (int i = 0; i < 10; i++) {
        manager.addMessage(
          _makeMessage(id: '$i', content: longContent),
        );
      }

      // Should be trimmed based on token count
      expect(manager.messageCount, lessThan(10));
    });
  });

  // ---------------------------------------------------------------------------
  // Token estimation
  // ---------------------------------------------------------------------------
  group('Token estimation', () {
    test('empty session should have 0 tokens', () {
      expect(manager.estimatedTokenUsage, 0);
    });

    test('short message should have reasonable token count', () {
      manager.addMessage(
        _makeMessage(id: '1', content: 'Hello world'),
      );

      // "Hello world" = 11 chars + 20 overhead = 31 chars / 4 ≈ 8 tokens
      expect(manager.estimatedTokenUsage, greaterThan(0));
      expect(manager.estimatedTokenUsage, lessThan(50));
    });

    test('longer messages should have more tokens', () {
      manager.addMessage(
        _makeMessage(id: '1', content: 'Short'),
      );
      final int shortTokens = manager.estimatedTokenUsage;

      manager.addMessage(
        _makeMessage(id: '2', content: 'A' * 400),
      );
      final int withLongTokens = manager.estimatedTokenUsage;

      expect(withLongTokens, greaterThan(shortTokens));
    });

    test('tokenBudgetRemaining should decrease with messages', () {
      final int initial = manager.tokenBudgetRemaining;

      manager.addMessage(
        _makeMessage(id: '1', content: 'Hello world'),
      );

      expect(manager.tokenBudgetRemaining, lessThan(initial));
    });

    test('isNearTokenLimit should be false for empty session', () {
      expect(manager.isNearTokenLimit, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Conversation history
  // ---------------------------------------------------------------------------
  group('Conversation history', () {
    test('empty session should return empty history', () {
      expect(manager.getConversationHistory(), '');
    });

    test('single welcome message should return empty history', () {
      manager.addMessage(
        _makeMessage(id: 'welcome', content: 'Welcome', isUser: false),
      );

      expect(manager.getConversationHistory(), '');
    });

    test('should format conversation correctly', () {
      manager.addMessage(
        _makeMessage(id: 'welcome', content: 'Welcome', isUser: false),
      );
      manager.addMessage(
        _makeMessage(id: '1', content: 'What is the best opening?'),
      );
      manager.addMessage(
        _makeMessage(
          id: '2',
          content: 'Consider d6 or f4.',
          isUser: false,
        ),
      );

      final String history = manager.getConversationHistory();

      expect(history, contains('RECENT CONVERSATION'));
      expect(history, contains('User: What is the best opening?'));
      expect(history, contains('Assistant: Consider d6 or f4.'));
    });

    test('should skip streaming messages in history', () {
      manager.addMessage(
        _makeMessage(id: 'welcome', content: 'Hi', isUser: false),
      );
      manager.addMessage(
        _makeMessage(id: '1', content: 'Question'),
      );
      manager.addMessage(
        _makeMessage(
          id: '2',
          content: 'Still typing...',
          isUser: false,
          isStreaming: true,
        ),
      );

      final String history = manager.getConversationHistory();

      expect(history, contains('User: Question'));
      expect(history, isNot(contains('Still typing...')));
    });

    test('should truncate very long messages in history', () {
      manager.addMessage(
        _makeMessage(id: 'welcome', content: 'Hi', isUser: false),
      );
      manager.addMessage(
        _makeMessage(id: '1', content: 'A' * 500),
      );

      final String history = manager.getConversationHistory();

      // Long message should be truncated with [truncated] marker
      expect(history, contains('[truncated]'));
    });
  });

  // ---------------------------------------------------------------------------
  // Session statistics
  // ---------------------------------------------------------------------------
  group('Session statistics', () {
    test('should return correct stats for empty session', () {
      final Map<String, dynamic> stats = manager.getSessionStats();

      expect(stats['messageCount'], 0);
      expect(stats['estimatedTokens'], 0);
      expect(stats['isNearLimit'], isFalse);
      expect(stats['gameId'], isNull);
    });

    test('should reflect current session state', () {
      manager.checkAndResetIfGameChanged('game-42');
      manager.addMessage(_makeMessage(id: '1', content: 'Hello'));
      manager.addMessage(_makeMessage(id: '2', content: 'World'));

      final Map<String, dynamic> stats = manager.getSessionStats();

      expect(stats['messageCount'], 2);
      expect(stats['estimatedTokens'], greaterThan(0));
      expect(stats['gameId'], 'game-42');
    });
  });

  // ---------------------------------------------------------------------------
  // Singleton behavior
  // ---------------------------------------------------------------------------
  group('Singleton behavior', () {
    test('factory constructor should return same instance', () {
      final ChatSessionManager m1 = ChatSessionManager();
      final ChatSessionManager m2 = ChatSessionManager();

      expect(identical(m1, m2), isTrue);
    });
  });
}
