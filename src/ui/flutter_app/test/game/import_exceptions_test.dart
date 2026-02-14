// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// import_exceptions_test.dart
//
// Tests for import-related exception classes.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  setUp(() {
    DB.instance = MockDB();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  group('ImportFormatException', () {
    test('should be a FormatException', () {
      const ImportFormatException ex = ImportFormatException();
      expect(ex, isA<FormatException>());
    });

    test('default message should be "Cannot import"', () {
      const ImportFormatException ex = ImportFormatException();
      expect(ex.message, 'Cannot import');
    });

    test('should accept custom source string', () {
      const ImportFormatException ex = ImportFormatException('bad data');
      expect(ex.message, 'bad data');
    });

    test('toString should return only the message without prefix', () {
      const ImportFormatException ex = ImportFormatException('test error');
      // The overridden toString returns just the message
      expect(ex.toString(), 'test error');
    });

    test('toString for default should return "Cannot import"', () {
      const ImportFormatException ex = ImportFormatException();
      expect(ex.toString(), 'Cannot import');
    });

    test('should be throwable and catchable as FormatException', () {
      expect(
        () => throw const ImportFormatException('test'),
        throwsFormatException,
      );
    });

    test('should be catchable specifically', () {
      try {
        throw const ImportFormatException('specific');
      } on ImportFormatException catch (e) {
        expect(e.message, 'specific');
      }
    });
  });
}
