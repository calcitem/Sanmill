// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// notifiers_test.dart
//
// Tests for game notifiers: HeaderTipNotifier, GameResultNotifier,
// HeaderIconsNotifier, BoardSemanticsNotifier, SetupPositionNotifier.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  setUp(() {
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    DB.instance = MockDB();
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
    binding.platformDispatcher.clearAllTestValues();
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

    test('showTip should not request a Snackbar without a screen reader', () {
      final HeaderTipNotifier notifier = HeaderTipNotifier();
      notifier.showTip('Test');

      expect(notifier.showSnackBar, isFalse);
    });

    test('showTip follows the system screen-reader state', () {
      binding.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      final HeaderTipNotifier notifier = HeaderTipNotifier();

      notifier.showTip('Test');

      expect(notifier.showSnackBar, isTrue);
    });

    test('showTip recognizes a desktop semantics request', () {
      binding.platformDispatcher.semanticsEnabledTestValue = true;
      final HeaderTipNotifier notifier = HeaderTipNotifier();

      notifier.showTip('Test');

      expect(notifier.showSnackBar, isTrue);
    });

    test('multiple showTip calls should update to latest', () {
      final HeaderTipNotifier notifier = HeaderTipNotifier();
      notifier.showTip('First', snackBar: false);
      notifier.showTip('Second', snackBar: false);
      notifier.showTip('Third', snackBar: false);

      expect(notifier.message, 'Third');
    });

    test('clear should discard the previous game message and kind', () {
      final HeaderTipNotifier notifier = HeaderTipNotifier();
      notifier.showTip('Last move: a4-a1', kind: HeaderTipKind.openingInfo);

      notifier.clear();

      expect(notifier.message, isEmpty);
      expect(notifier.kind, HeaderTipKind.general);
      expect(notifier.showSnackBar, isFalse);
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

    // 'showResult should detect game over from position' was
    // removed: the legacy `Position.setGameOver` mirror is gone
    // with the rule-machine cleanup, and the native session does
    // not yet expose a "force terminate" primitive.  Equivalent
    // coverage will land alongside the Rust-backed terminator
    // primitive.

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
  // SetupPositionNotifier removed along with setup-position editor.

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
