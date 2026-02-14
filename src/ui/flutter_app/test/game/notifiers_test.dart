// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// notifiers_test.dart
//
// Tests for game notifiers: HeaderTipNotifier, GameResultNotifier,
// HeaderIconsNotifier, BoardSemanticsNotifier, SetupPositionNotifier.

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
  // HeaderTipNotifier
  // ---------------------------------------------------------------------------
  group('HeaderTipNotifier', () {
    test('initial message should be empty', () {
      final HeaderTipNotifier notifier = HeaderTipNotifier();
      expect(notifier.message, '');
    });

    test('showTip should update message', () {
      final HeaderTipNotifier notifier = HeaderTipNotifier();
      notifier.showTip('Hello', snackBar: false);

      expect(notifier.message, 'Hello');
    });

    test('showTip should set showSnackBar based on screenReaderSupport', () {
      // Default: screenReaderSupport = false
      final HeaderTipNotifier notifier = HeaderTipNotifier();
      notifier.showTip('Test', snackBar: true);

      // screenReaderSupport is false by default in MockDB,
      // so showSnackBar should be false
      expect(notifier.showSnackBar, isFalse);
    });

    test('multiple showTip calls should update to latest', () {
      final HeaderTipNotifier notifier = HeaderTipNotifier();
      notifier.showTip('First', snackBar: false);
      notifier.showTip('Second', snackBar: false);
      notifier.showTip('Third', snackBar: false);

      expect(notifier.message, 'Third');
    });
  });

  // ---------------------------------------------------------------------------
  // GameResultNotifier
  // ---------------------------------------------------------------------------
  group('GameResultNotifier', () {
    test('initial state should have no result', () {
      final GameResultNotifier notifier = GameResultNotifier();

      expect(notifier.hasResult, isFalse);
      expect(notifier.isVisible, isFalse);
      expect(notifier.force, isFalse);
      expect(notifier.winner, isNull);
      expect(notifier.reason, isNull);
    });

    test('clearResult should reset all state', () {
      final GameResultNotifier notifier = GameResultNotifier();

      // Simulate having a result
      notifier.showResult(force: true);

      // Clear it
      notifier.clearResult();

      expect(notifier.hasResult, isFalse);
      expect(notifier.isVisible, isFalse);
      expect(notifier.winner, isNull);
      expect(notifier.reason, isNull);
    });

    test('hideResult should only hide visibility', () {
      final GameResultNotifier notifier = GameResultNotifier();

      notifier.hideResult();

      expect(notifier.isVisible, isFalse);
    });

    test('showResult should detect game over from position', () {
      // Set up a game over state
      final GameController controller = GameController();
      controller.animationManager = MockAnimationManager();
      controller.reset(force: true);
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      controller.position.setGameOver(
        PieceColor.white,
        GameOverReason.loseFewerThanThree,
      );

      final GameResultNotifier notifier = controller.gameResultNotifier;
      notifier.showResult();

      expect(notifier.hasResult, isTrue);
      expect(notifier.isVisible, isTrue);
      expect(notifier.winner, PieceColor.white);
    });

    test('showResult with force flag', () {
      final GameController controller = GameController();
      controller.animationManager = MockAnimationManager();
      controller.reset(force: true);

      final GameResultNotifier notifier = controller.gameResultNotifier;
      notifier.showResult(force: true);

      expect(notifier.force, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // HeaderIconsNotifier
  // ---------------------------------------------------------------------------
  group('HeaderIconsNotifier', () {
    test('should be accessible from GameController', () {
      final GameController controller = GameController();
      expect(controller.headerIconsNotifier, isNotNull);
      expect(controller.headerIconsNotifier, isA<HeaderIconsNotifier>());
    });
  });

  // ---------------------------------------------------------------------------
  // BoardSemanticsNotifier
  // ---------------------------------------------------------------------------
  group('BoardSemanticsNotifier', () {
    test('should be accessible from GameController', () {
      final GameController controller = GameController();
      expect(controller.boardSemanticsNotifier, isNotNull);
      expect(controller.boardSemanticsNotifier, isA<BoardSemanticsNotifier>());
    });
  });

  // ---------------------------------------------------------------------------
  // SetupPositionNotifier
  // ---------------------------------------------------------------------------
  group('SetupPositionNotifier', () {
    test('should be accessible from GameController', () {
      final GameController controller = GameController();
      expect(controller.setupPositionNotifier, isNotNull);
      expect(controller.setupPositionNotifier, isA<SetupPositionNotifier>());
    });
  });

  // ---------------------------------------------------------------------------
  // ChangeNotifier behavior
  // ---------------------------------------------------------------------------
  group('Notifier listener behavior', () {
    test('HeaderTipNotifier should notify listeners on showTip', () async {
      final HeaderTipNotifier notifier = HeaderTipNotifier();
      bool wasNotified = false;

      notifier.addListener(() {
        wasNotified = true;
      });

      notifier.showTip('Test', snackBar: false);

      // showTip uses Future.delayed(Duration.zero), so we need to pump
      await Future<void>.delayed(Duration.zero);

      expect(wasNotified, isTrue);

      notifier.removeListener(() {});
    });

    test('GameResultNotifier should notify on clearResult', () {
      final GameResultNotifier notifier = GameResultNotifier();
      bool wasNotified = false;

      notifier.addListener(() {
        wasNotified = true;
      });

      notifier.clearResult();

      expect(wasNotified, isTrue);
    });

    test('GameResultNotifier should notify on hideResult', () {
      final GameResultNotifier notifier = GameResultNotifier();
      bool wasNotified = false;

      notifier.addListener(() {
        wasNotified = true;
      });

      notifier.hideResult();

      expect(wasNotified, isTrue);
    });
  });
}
