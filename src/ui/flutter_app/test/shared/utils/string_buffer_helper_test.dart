// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// string_buffer_helper_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/helpers/string_helpers/string_buffer_helper.dart';

import '../../helpers/mocks/mock_database.dart';

void main() {
  late MockDB mockDB;

  setUp(() {
    mockDB = MockDB();
    DB.instance = mockDB;
  });

  // ---------------------------------------------------------------------------
  // writeSpace
  // ---------------------------------------------------------------------------
  group('CustomStringBuffer.writeSpace', () {
    test('should append content followed by a space', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writeSpace('hello');

      expect(buffer.toString(), 'hello ');
    });

    test('should append just a space with default argument', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writeSpace();

      expect(buffer.toString(), ' ');
    });

    test('should handle numbers', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writeSpace(42);

      expect(buffer.toString(), '42 ');
    });
  });

  // ---------------------------------------------------------------------------
  // writeNumber
  // ---------------------------------------------------------------------------
  group('CustomStringBuffer.writeNumber', () {
    test('should write number followed by period', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writeNumber(1);

      expect(buffer.toString(), '1.');
    });

    test('should handle multi-digit numbers', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writeNumber(42);

      expect(buffer.toString(), '42.');
    });

    test('should handle zero', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writeNumber(0);

      expect(buffer.toString(), '0.');
    });

    test('chained writeNumber calls', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writeNumber(1);
      buffer.writeSpace();
      buffer.writeNumber(2);

      expect(buffer.toString(), '1. 2.');
    });
  });

  // ---------------------------------------------------------------------------
  // writeComma - screen reader support OFF
  // ---------------------------------------------------------------------------
  group('CustomStringBuffer.writeComma (screenReaderSupport off)', () {
    setUp(() {
      mockDB.generalSettings = const GeneralSettings(

      );
    });

    test('should write content + newline without comma', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writeComma('hello');

      expect(buffer.toString(), 'hello\n');
    });

    test('should write empty content + newline by default', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writeComma();

      expect(buffer.toString(), '\n');
    });
  });

  // ---------------------------------------------------------------------------
  // writeComma - screen reader support ON
  // ---------------------------------------------------------------------------
  group('CustomStringBuffer.writeComma (screenReaderSupport on)', () {
    setUp(() {
      mockDB.generalSettings = const GeneralSettings(screenReaderSupport: true);
    });

    test('should write content with comma + newline', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writeComma('hello');

      expect(buffer.toString(), 'hello,\n');
    });

    test('should write comma + newline by default', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writeComma();

      expect(buffer.toString(), ',\n');
    });
  });

  // ---------------------------------------------------------------------------
  // writePeriod - screen reader support OFF
  // ---------------------------------------------------------------------------
  group('CustomStringBuffer.writePeriod (screenReaderSupport off)', () {
    setUp(() {
      mockDB.generalSettings = const GeneralSettings(

      );
    });

    test('should write content + newline without period', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writePeriod('hello');

      expect(buffer.toString(), 'hello\n');
    });

    test('should write empty content + newline by default', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writePeriod();

      expect(buffer.toString(), '\n');
    });
  });

  // ---------------------------------------------------------------------------
  // writePeriod - screen reader support ON
  // ---------------------------------------------------------------------------
  group('CustomStringBuffer.writePeriod (screenReaderSupport on)', () {
    setUp(() {
      mockDB.generalSettings = const GeneralSettings(screenReaderSupport: true);
    });

    test('should write content with period + newline', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writePeriod('hello');

      expect(buffer.toString(), 'hello.\n');
    });

    test('should write period + newline by default', () {
      final StringBuffer buffer = StringBuffer();
      buffer.writePeriod();

      expect(buffer.toString(), '.\n');
    });
  });

  // ---------------------------------------------------------------------------
  // Combined usage
  // ---------------------------------------------------------------------------
  group('Combined usage', () {
    test('should build a complete numbered list with screen reader', () {
      mockDB.generalSettings = const GeneralSettings(screenReaderSupport: true);

      final StringBuffer buffer = StringBuffer();
      buffer.writeNumber(1);
      buffer.writeSpace('d6');
      buffer.writeComma('f4');

      expect(buffer.toString(), '1.d6 f4,\n');
    });
  });
}
