// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_controller_extended_test.dart
//
// Extended tests for GameController singleton, reset, state management,
// and notifiers.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  setUp(() {
    DB.instance = MockDB();
    initBitboards();
    SoundManager.instance = MockAudios();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'send':
            case 'shutdown':
            case 'startup':
              return null;
            case 'read':
              return 'bestmove d2';
            case 'isThinking':
              return false;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------
  group('GameController singleton', () {
    test('factory constructor should return same instance', () {
      final GameController c1 = GameController();
      final GameController c2 = GameController();
      expect(identical(c1, c2), isTrue);
    });

    test('instance should be accessible', () {
      expect(GameController.instance, isNotNull);
      expect(identical(GameController(), GameController.instance), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Reset
  // ---------------------------------------------------------------------------
  group('GameController.reset', () {
    test('reset should preserve gameMode', () {
      final GameController controller = GameController();
      controller.animationManager = MockAnimationManager();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      controller.reset();

      expect(controller.gameInstance.gameMode, GameMode.humanVsHuman);
    });

    test('reset should clear position to initial state', () {
      final GameController controller = GameController();
      controller.animationManager = MockAnimationManager();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      // Make some moves
      controller.reset(force: true);

      // After reset, position should be in placing phase
      expect(
        controller.position.phase == Phase.placing ||
            controller.position.phase == Phase.ready,
        isTrue,
      );
    });

    test('reset should clear focus and blur indices', () {
      final GameController controller = GameController();
      controller.animationManager = MockAnimationManager();
      controller.gameInstance.focusIndex = 8;
      controller.gameInstance.blurIndex = 12;

      controller.reset(force: true);

      expect(controller.gameInstance.focusIndex, isNull);
      expect(controller.gameInstance.blurIndex, isNull);
    });

    test('forced reset should work even during game', () {
      final GameController controller = GameController();
      controller.animationManager = MockAnimationManager();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      controller.reset(force: true);

      // Should not throw
      expect(controller.position, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Position access
  // ---------------------------------------------------------------------------
  group('GameController.position', () {
    test('should provide access to the game position', () {
      final GameController controller = GameController();

      expect(controller.position, isNotNull);
      expect(controller.position, isA<Position>());
    });

    test('position should have default sideToMove as white', () {
      final GameController controller = GameController();
      controller.animationManager = MockAnimationManager();
      controller.reset(force: true);

      expect(controller.position.sideToMove, PieceColor.white);
    });
  });

  // ---------------------------------------------------------------------------
  // Game instance access
  // ---------------------------------------------------------------------------
  group('GameController.gameInstance', () {
    test('should provide access to the Game object', () {
      final GameController controller = GameController();

      expect(controller.gameInstance, isNotNull);
      expect(controller.gameInstance, isA<Game>());
    });

    test('gameInstance players should have two entries', () {
      final GameController controller = GameController();

      expect(controller.gameInstance.players.length, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // Game recorder
  // ---------------------------------------------------------------------------
  group('GameController.gameRecorder', () {
    test('should provide access to the GameRecorder', () {
      final GameController controller = GameController();

      expect(controller.gameRecorder, isNotNull);
      expect(controller.gameRecorder, isA<GameRecorder>());
    });

    test('gameRecorder should have empty mainline after reset', () {
      final GameController controller = GameController();
      controller.animationManager = MockAnimationManager();
      controller.reset(force: true);

      expect(controller.gameRecorder.mainlineMoves, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Notifiers
  // ---------------------------------------------------------------------------
  group('GameController notifiers', () {
    test('headerTipNotifier should be accessible', () {
      final GameController controller = GameController();
      expect(controller.headerTipNotifier, isNotNull);
    });

    test('headerIconsNotifier should be accessible', () {
      final GameController controller = GameController();
      expect(controller.headerIconsNotifier, isNotNull);
    });

    test('gameResultNotifier should be accessible', () {
      final GameController controller = GameController();
      expect(controller.gameResultNotifier, isNotNull);
    });

    test('boardSemanticsNotifier should be accessible', () {
      final GameController controller = GameController();
      expect(controller.boardSemanticsNotifier, isNotNull);
    });

    test('setupPositionNotifier should be accessible', () {
      final GameController controller = GameController();
      expect(controller.setupPositionNotifier, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Engine state
  // ---------------------------------------------------------------------------
  group('GameController engine state', () {
    test('isEngineRunning should be false initially', () {
      final GameController controller = GameController();
      expect(controller.isEngineRunning, isFalse);
    });

    test('aiMoveType should have a default', () {
      final GameController controller = GameController();
      expect(controller.aiMoveType, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // disableStats
  // ---------------------------------------------------------------------------
  group('GameController.disableStats', () {
    test('should be settable', () {
      final GameController controller = GameController();
      controller.disableStats = true;
      expect(controller.disableStats, isTrue);

      controller.disableStats = false;
      expect(controller.disableStats, isFalse);
    });
  });
}
