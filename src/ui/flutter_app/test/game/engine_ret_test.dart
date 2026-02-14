// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// engine_ret_test.dart
//
// Tests for EngineRet data class.

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

  group('EngineRet', () {
    test('should store value, aiMoveType, and extMove', () {
      final ExtMove move = ExtMove('d6', side: PieceColor.white);
      final EngineRet ret = EngineRet(
        'bestmove d6',
        AiMoveType.traditional,
        move,
      );

      expect(ret.value, 'bestmove d6');
      expect(ret.aiMoveType, AiMoveType.traditional);
      expect(ret.extMove, isNotNull);
      expect(ret.extMove!.move, 'd6');
    });

    test('should allow null values', () {
      final EngineRet ret = EngineRet(null, null, null);

      expect(ret.value, isNull);
      expect(ret.aiMoveType, isNull);
      expect(ret.extMove, isNull);
    });

    test('should allow updating value', () {
      final EngineRet ret = EngineRet('initial', null, null);
      ret.value = 'updated';

      expect(ret.value, 'updated');
    });

    test('should work with all AiMoveType values', () {
      for (final AiMoveType type in AiMoveType.values) {
        final EngineRet ret = EngineRet('test', type, null);
        expect(ret.aiMoveType, type);
      }
    });
  });
}
