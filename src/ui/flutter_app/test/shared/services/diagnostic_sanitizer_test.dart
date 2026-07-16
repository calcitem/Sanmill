// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/services/diagnostic_sanitizer.dart';

void main() {
  group('DiagnosticSanitizer', () {
    test('redacts credentials, identifiers, addresses and paths', () {
      const String token = 'abcde12345abcde12345abcde12345abcd';
      final String input = <String>[
        'mail=user@example.com',
        'url=https://private.example/path?q=1',
        'ip=192.168.1.42',
        'mac=aa:bb:cc:dd:ee:ff',
        r'path=C:\Users\Alice\secret.txt',
        'path=/Users/alice/secret.txt',
        'Authorization: Bearer secret-value',
        'api_key=top-secret',
        'token=$token',
      ].join('\n');

      final String sanitized = DiagnosticSanitizer.sanitizeText(
        input,
        reportSalt: 'report-salt',
      );

      expect(sanitized, isNot(contains('user@example.com')));
      expect(sanitized, isNot(contains('private.example')));
      expect(sanitized, isNot(contains('192.168.1.42')));
      expect(sanitized, isNot(contains('aa:bb:cc:dd:ee:ff')));
      expect(sanitized, isNot(contains('Alice')));
      expect(sanitized, isNot(contains('alice')));
      expect(sanitized, isNot(contains('secret-value')));
      expect(sanitized, isNot(contains('top-secret')));
      expect(sanitized, isNot(contains(token)));
    });

    test('move text drops player tags, comments and variations', () {
      const String input = r'''
[Event "Private club"]
[White "Alice"]
[Black "Bob"]
[FEN "example-fen"]
[Result "1-0"]

1. a1 (1. d6 {private comment}) d6 2. g1 $12 1-0
''';

      final String sanitized = DiagnosticSanitizer.sanitizeMoveText(input);

      expect(sanitized, contains('[FEN "example-fen"]'));
      expect(sanitized, contains('[Result "1-0"]'));
      expect(sanitized, isNot(contains('Alice')));
      expect(sanitized, isNot(contains('Bob')));
      expect(sanitized, isNot(contains('Private club')));
      expect(sanitized, isNot(contains('private comment')));
      expect(sanitized, isNot(contains(r'$12')));
    });

    test('legacy raw content is represented only by length metadata', () {
      final Map<String, dynamic> sanitized =
          DiagnosticSanitizer.sanitizeLegacyPayload(<String, dynamic>{
            'pgnContent': '[White "Alice"] secret moves',
            'filePath': '/Users/alice/private.pgn',
            'includeVariations': false,
          });

      expect(sanitized['lengthBucket'], isNotEmpty);
      expect(sanitized['includeVariations'], isFalse);
      expect(sanitized, isNot(contains('pgnContent')));
      expect(sanitized, isNot(contains('filePath')));
      expect(sanitized.toString(), isNot(contains('Alice')));
    });

    test('session identifiers use a report-local stable hash', () {
      const String input =
          'session_id=session-1234567890\n'
          '[Remote][LAN][host][session8][round123][connected] '
          'peer=peer5678';
      final String first = DiagnosticSanitizer.sanitizeText(
        input,
        reportSalt: 'report-one',
      );
      final String repeated = DiagnosticSanitizer.sanitizeText(
        input,
        reportSalt: 'report-one',
      );
      final String anotherReport = DiagnosticSanitizer.sanitizeText(
        input,
        reportSalt: 'report-two',
      );

      expect(first, repeated);
      expect(first, isNot(anotherReport));
      expect(first, isNot(contains('session-1234567890')));
      expect(first, isNot(contains('session8')));
      expect(first, isNot(contains('round123')));
      expect(first, isNot(contains('peer5678')));
      expect(first, contains('<hash:'));
    });
  });
}
