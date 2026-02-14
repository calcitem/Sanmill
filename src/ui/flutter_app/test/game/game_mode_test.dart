// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_mode_test.dart
//
// Tests for GameMode enum, Game class, Player class, and related logic.

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

  // ---------------------------------------------------------------------------
  // GameMode enum
  // ---------------------------------------------------------------------------
  group('GameMode enum', () {
    test('should have eight modes', () {
      expect(GameMode.values.length, 8);
    });

    test('should include all expected modes', () {
      expect(
        GameMode.values,
        containsAll(<GameMode>[
          GameMode.humanVsAi,
          GameMode.humanVsHuman,
          GameMode.aiVsAi,
          GameMode.setupPosition,
          GameMode.puzzle,
          GameMode.humanVsCloud,
          GameMode.humanVsLAN,
          GameMode.testViaLAN,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // GameMode.whoIsAI
  // ---------------------------------------------------------------------------
  group('GameMode.whoIsAI', () {
    test('humanVsAi with aiMovesFirst=false: black is AI', () {
      (DB.instance as MockDB).generalSettings =
          DB().generalSettings.copyWith(aiMovesFirst: false);

      final Map<PieceColor, bool> who = GameMode.humanVsAi.whoIsAI;
      expect(who[PieceColor.white], isFalse);
      expect(who[PieceColor.black], isTrue);
    });

    test('humanVsAi with aiMovesFirst=true: white is AI', () {
      (DB.instance as MockDB).generalSettings =
          DB().generalSettings.copyWith(aiMovesFirst: true);

      final Map<PieceColor, bool> who = GameMode.humanVsAi.whoIsAI;
      expect(who[PieceColor.white], isTrue);
      expect(who[PieceColor.black], isFalse);
    });

    test('humanVsHuman: neither is AI', () {
      final Map<PieceColor, bool> who = GameMode.humanVsHuman.whoIsAI;
      expect(who[PieceColor.white], isFalse);
      expect(who[PieceColor.black], isFalse);
    });

    test('aiVsAi: both are AI', () {
      final Map<PieceColor, bool> who = GameMode.aiVsAi.whoIsAI;
      expect(who[PieceColor.white], isTrue);
      expect(who[PieceColor.black], isTrue);
    });

    test('setupPosition: neither is AI', () {
      final Map<PieceColor, bool> who = GameMode.setupPosition.whoIsAI;
      expect(who[PieceColor.white], isFalse);
      expect(who[PieceColor.black], isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Player class
  // ---------------------------------------------------------------------------
  group('Player', () {
    test('should store color and isAi', () {
      final Player player = Player(color: PieceColor.white, isAi: false);
      expect(player.color, PieceColor.white);
      expect(player.isAi, isFalse);
    });

    test('isAi should be mutable', () {
      final Player player = Player(color: PieceColor.black, isAi: true);
      player.isAi = false;
      expect(player.isAi, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Game class
  // ---------------------------------------------------------------------------
  group('Game', () {
    test('should initialize with given game mode', () {
      final Game game = Game(gameMode: GameMode.humanVsHuman);
      expect(game.gameMode, GameMode.humanVsHuman);
    });

    test('should have two players (white and black)', () {
      final Game game = Game(gameMode: GameMode.humanVsHuman);
      expect(game.players.length, 2);
    });

    test('getPlayerByColor should return correct player', () {
      final Game game = Game(gameMode: GameMode.humanVsHuman);

      final Player white = game.getPlayerByColor(PieceColor.white);
      expect(white.color, PieceColor.white);

      final Player black = game.getPlayerByColor(PieceColor.black);
      expect(black.color, PieceColor.black);
    });

    test('getPlayerByColor should handle non-player colors', () {
      final Game game = Game(gameMode: GameMode.humanVsHuman);

      final Player draw = game.getPlayerByColor(PieceColor.draw);
      expect(draw.color, PieceColor.draw);
      expect(draw.isAi, isFalse);

      final Player nobody = game.getPlayerByColor(PieceColor.nobody);
      expect(nobody.color, PieceColor.nobody);
      expect(nobody.isAi, isFalse);

      final Player none = game.getPlayerByColor(PieceColor.none);
      expect(none.color, PieceColor.none);

      final Player marked = game.getPlayerByColor(PieceColor.marked);
      expect(marked.color, PieceColor.marked);
    });

    test('changing gameMode should update AI assignments', () {
      final Game game = Game(gameMode: GameMode.humanVsHuman);

      // In humanVsHuman, both should be non-AI
      expect(game.getPlayerByColor(PieceColor.white).isAi, isFalse);
      expect(game.getPlayerByColor(PieceColor.black).isAi, isFalse);

      // Switch to aiVsAi
      game.gameMode = GameMode.aiVsAi;
      expect(game.getPlayerByColor(PieceColor.white).isAi, isTrue);
      expect(game.getPlayerByColor(PieceColor.black).isAi, isTrue);
    });

    test('focusIndex and blurIndex should be null initially', () {
      final Game game = Game(gameMode: GameMode.humanVsHuman);
      expect(game.focusIndex, isNull);
      expect(game.blurIndex, isNull);
    });

    test('changing gameMode should clear focus and blur indices', () {
      final Game game = Game(gameMode: GameMode.humanVsHuman);
      game.focusIndex = 8;
      game.blurIndex = 12;

      game.gameMode = GameMode.aiVsAi;

      expect(game.focusIndex, isNull);
      expect(game.blurIndex, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // AiMoveType
  // ---------------------------------------------------------------------------
  group('AiMoveType', () {
    test('should have five values', () {
      expect(AiMoveType.values.length, 5);
    });

    test('should include all expected types', () {
      expect(
        AiMoveType.values,
        containsAll(<AiMoveType>[
          AiMoveType.unknown,
          AiMoveType.traditional,
          AiMoveType.perfect,
          AiMoveType.consensus,
          AiMoveType.openingBook,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // aiMoveTypeIcons
  // ---------------------------------------------------------------------------
  group('aiMoveTypeIcons', () {
    test('should have entries for all AiMoveType values', () {
      for (final AiMoveType type in AiMoveType.values) {
        expect(
          aiMoveTypeIcons.containsKey(type),
          isTrue,
          reason: 'Missing icon for $type',
        );
      }
    });
  });
}
