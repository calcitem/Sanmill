// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// mill_helpers_test.dart
//
// Tests for top-level mill.dart functions and enums.

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

  late MockDB mockDB;

  setUp(() {
    mockDB = MockDB();
    DB.instance = mockDB;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  // ---------------------------------------------------------------------------
  // MoveQuality enum
  // ---------------------------------------------------------------------------
  group('MoveQuality', () {
    test('should have five values', () {
      expect(MoveQuality.values.length, 5);
    });

    test('should include all expected values', () {
      expect(
        MoveQuality.values,
        containsAll(<MoveQuality>[
          MoveQuality.normal,
          MoveQuality.minorGoodMove,
          MoveQuality.majorGoodMove,
          MoveQuality.minorBadMove,
          MoveQuality.majorBadMove,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // GameResult NAG strings
  // ---------------------------------------------------------------------------
  group('GameResult.toNagString', () {
    test('should return correct NAG strings', () {
      expect(GameResult.win.toNagString(), '1-0');
      expect(GameResult.lose.toNagString(), '0-1');
      expect(GameResult.draw.toNagString(), '1/2-1/2');
    });
  });

  // ---------------------------------------------------------------------------
  // GameOverReason enum
  // ---------------------------------------------------------------------------
  group('GameOverReason', () {
    test('should include all expected values', () {
      expect(GameOverReason.values.length, 11);
      expect(
        GameOverReason.values,
        containsAll(<GameOverReason>[
          GameOverReason.loseFewerThanThree,
          GameOverReason.loseNoLegalMoves,
          GameOverReason.loseFullBoard,
          GameOverReason.loseResign,
          GameOverReason.loseTimeout,
          GameOverReason.drawThreefoldRepetition,
          GameOverReason.drawFiftyMove,
          GameOverReason.drawEndgameFiftyMove,
          GameOverReason.drawFullBoard,
          GameOverReason.drawStalemateCondition,
          GameOverReason.drawAgreement,
        ]),
      );
    });
  });
}
