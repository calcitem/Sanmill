// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// zobrist_test.dart
//
// Tests for Zobrist hashing through Position's StateInfo key.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
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
    initBitboards();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  group('Zobrist hashing via Position.st.key', () {
    test('new Position should have initial key of 0', () {
      final Position p = Position();
      expect(p.st.key, 0);
    });

    test('two default positions should have the same initial key', () {
      final Position p1 = Position();
      final Position p2 = Position();
      expect(p1.st.key, equals(p2.st.key));
    });

    test('setting same FEN should produce same key', () {
      const String fen =
          'O@O*****/********/******** w p p 3 6 3 6 0 0 0 0 0 0 0 0 1';

      final Position p1 = Position();
      p1.setFen(fen);

      final Position p2 = Position();
      p2.setFen(fen);

      expect(p1.st.key, equals(p2.st.key));
    });

    test('different FEN should produce different keys', () {
      final Position p1 = Position();
      p1.setFen('O@O*****/********/******** w p p 3 6 3 6 0 0 0 0 0 0 0 0 1');

      final Position p2 = Position();
      p2.setFen('********/O@O*****/******** w p p 3 6 3 6 0 0 0 0 0 0 0 0 1');

      expect(p1.st.key, isNot(equals(p2.st.key)));
    });
  });

  // ---------------------------------------------------------------------------
  // StateInfo
  // ---------------------------------------------------------------------------
  group('StateInfo', () {
    test('should have initial values of 0', () {
      final StateInfo info = StateInfo();
      expect(info.key, 0);
      expect(info.rule50, 0);
      expect(info.pliesFromNull, 0);
    });

    test('should be mutable', () {
      final StateInfo info = StateInfo();
      info.key = 42;
      info.rule50 = 10;
      info.pliesFromNull = 5;

      expect(info.key, 42);
      expect(info.rule50, 10);
      expect(info.pliesFromNull, 5);
    });
  });

  // ---------------------------------------------------------------------------
  // SquareAttribute
  // ---------------------------------------------------------------------------
  group('SquareAttribute', () {
    test('should store placedPieceNumber', () {
      final SquareAttribute attr = SquareAttribute(placedPieceNumber: 5);
      expect(attr.placedPieceNumber, 5);
    });

    test('default placedPieceNumber is 0', () {
      final SquareAttribute attr = SquareAttribute(placedPieceNumber: 0);
      expect(attr.placedPieceNumber, 0);
    });
  });
}
