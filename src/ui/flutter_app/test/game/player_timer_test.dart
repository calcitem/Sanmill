// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// player_timer_test.dart
//
// Tests for PlayerTimer state management (not actual timer ticking,
// which requires a running game loop).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/services/player_timer.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
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
    // Ensure timer is reset before each test
    PlayerTimer.instance.reset();
  });

  tearDown(() {
    PlayerTimer.instance.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------
  group('PlayerTimer singleton', () {
    test('factory constructor should return same instance', () {
      final PlayerTimer t1 = PlayerTimer();
      final PlayerTimer t2 = PlayerTimer();
      expect(identical(t1, t2), isTrue);
    });

    test('instance should be accessible', () {
      expect(PlayerTimer.instance, isNotNull);
      expect(identical(PlayerTimer(), PlayerTimer.instance), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Initial state
  // ---------------------------------------------------------------------------
  group('PlayerTimer initial state', () {
    test('should not be active initially', () {
      expect(PlayerTimer.instance.isActive, isFalse);
    });

    test('remaining time should be 0 initially', () {
      expect(PlayerTimer.instance.remainingTime, 0);
    });

    test('remainingTimeNotifier should be 0', () {
      expect(PlayerTimer.instance.remainingTimeNotifier.value, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Reset
  // ---------------------------------------------------------------------------
  group('PlayerTimer reset', () {
    test('reset should stop timer and clear remaining time', () {
      PlayerTimer.instance.reset();

      expect(PlayerTimer.instance.isActive, isFalse);
      expect(PlayerTimer.instance.remainingTime, 0);
      expect(PlayerTimer.instance.remainingTimeNotifier.value, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Stop
  // ---------------------------------------------------------------------------
  group('PlayerTimer stop', () {
    test('stop should deactivate timer', () {
      PlayerTimer.instance.stop();
      expect(PlayerTimer.instance.isActive, isFalse);
    });

    test('stop when not active should be a no-op', () {
      PlayerTimer.instance.stop();
      PlayerTimer.instance.stop(); // Double stop
      expect(PlayerTimer.instance.isActive, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Retired clock compatibility
  // ---------------------------------------------------------------------------
  group('PlayerTimer compatibility', () {
    test('legacy human time settings cannot start a countdown', () {
      DB().generalSettings = const GeneralSettings(humanMoveTime: 30);
      final GameController controller = GameController();
      controller.gameInstance.gameMode = GameMode.humanVsAi;
      controller.gameRecorder.reset();
      controller.gameRecorder.appendMove(ExtMove('d6', side: PieceColor.white));

      PlayerTimer.instance.start();

      expect(PlayerTimer.instance.status, PlayerTimerStatus.stopped);
      expect(PlayerTimer.instance.isActive, isFalse);
      expect(PlayerTimer.instance.remainingTime, 0);
      expect(PlayerTimer.instance.remainingTimeNotifier.value, 0);
    });

    test('same-device games delegate timing to OfflineBoardClock', () {
      DB().generalSettings = const GeneralSettings(humanMoveTime: 30);
      final GameController controller = GameController();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;
      controller.gameRecorder.reset();
      controller.gameRecorder.appendMove(ExtMove('d6', side: PieceColor.white));

      PlayerTimer.instance.start();

      expect(PlayerTimer.instance.status, PlayerTimerStatus.stopped);
      expect(PlayerTimer.instance.remainingTime, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // ValueNotifier
  // ---------------------------------------------------------------------------
  group('PlayerTimer ValueNotifier', () {
    test('remainingTimeNotifier should be a ValueNotifier<int>', () {
      expect(
        PlayerTimer.instance.remainingTimeNotifier,
        isA<ValueNotifier<int>>(),
      );
    });

    test('notifier value should update on reset', () {
      // Set some state then reset
      PlayerTimer.instance.remainingTimeNotifier.value = 30;
      PlayerTimer.instance.reset();

      expect(PlayerTimer.instance.remainingTimeNotifier.value, 0);
    });
  });
}
