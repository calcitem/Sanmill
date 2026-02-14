// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// chat_message_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/models/chat_message.dart';

void main() {
  group('ChatMessage', () {
    final DateTime baseTime = DateTime(2026, 2, 14, 10, 0, 0);

    group('constructor', () {
      test('should store all required fields', () {
        final ChatMessage msg = ChatMessage(
          id: 'msg-1',
          content: 'Hello',
          isUser: true,
          timestamp: baseTime,
        );

        expect(msg.id, 'msg-1');
        expect(msg.content, 'Hello');
        expect(msg.isUser, isTrue);
        expect(msg.timestamp, baseTime);
        expect(msg.isStreaming, isFalse);
      });

      test('should accept optional isStreaming flag', () {
        final ChatMessage msg = ChatMessage(
          id: 'msg-2',
          content: 'Streaming...',
          isUser: false,
          timestamp: baseTime,
          isStreaming: true,
        );

        expect(msg.isStreaming, isTrue);
      });
    });

    group('copyWith', () {
      test('should return identical message when no arguments given', () {
        final ChatMessage original = ChatMessage(
          id: 'msg-1',
          content: 'Hello',
          isUser: true,
          timestamp: baseTime,
          isStreaming: true,
        );

        final ChatMessage copy = original.copyWith();

        expect(copy.id, original.id);
        expect(copy.content, original.content);
        expect(copy.isUser, original.isUser);
        expect(copy.timestamp, original.timestamp);
        expect(copy.isStreaming, original.isStreaming);
      });

      test('should override only the content', () {
        final ChatMessage original = ChatMessage(
          id: 'msg-1',
          content: 'Hello',
          isUser: true,
          timestamp: baseTime,
        );

        final ChatMessage updated = original.copyWith(
          content: 'Hello World',
        );

        expect(updated.content, 'Hello World');
        expect(updated.id, original.id);
        expect(updated.isUser, original.isUser);
        expect(updated.timestamp, original.timestamp);
      });

      test('should override only the isStreaming flag', () {
        final ChatMessage original = ChatMessage(
          id: 'msg-1',
          content: 'Hello',
          isUser: false,
          timestamp: baseTime,
          isStreaming: true,
        );

        final ChatMessage updated = original.copyWith(isStreaming: false);

        expect(updated.isStreaming, isFalse);
        expect(updated.content, original.content);
      });

      test('should allow overriding all fields at once', () {
        final ChatMessage original = ChatMessage(
          id: 'msg-1',
          content: 'Hello',
          isUser: true,
          timestamp: baseTime,
        );
        final DateTime newTime = DateTime(2026, 3, 1);

        final ChatMessage updated = original.copyWith(
          id: 'msg-2',
          content: 'Updated',
          isUser: false,
          timestamp: newTime,
          isStreaming: true,
        );

        expect(updated.id, 'msg-2');
        expect(updated.content, 'Updated');
        expect(updated.isUser, isFalse);
        expect(updated.timestamp, newTime);
        expect(updated.isStreaming, isTrue);
      });
    });

    group('immutability', () {
      test('copyWith should return a new instance', () {
        final ChatMessage original = ChatMessage(
          id: 'msg-1',
          content: 'Hello',
          isUser: true,
          timestamp: baseTime,
        );

        final ChatMessage copy = original.copyWith(content: 'Changed');

        // Original should be unchanged
        expect(original.content, 'Hello');
        expect(copy.content, 'Changed');
      });
    });
  });
}
