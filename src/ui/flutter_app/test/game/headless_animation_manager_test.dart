// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// headless_animation_manager_test.dart
//
// Tests for HeadlessAnimationManager - a vsync-free AnimationManager.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/animation/headless_animation_manager.dart';
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

  group('HeadlessAnimationManager', () {
    test('should create without error', () {
      // HeadlessAnimationManager needs GameController singleton,
      // which is initialized when accessed
      final GameController controller = GameController();
      controller.reset();

      expect(
        () => HeadlessAnimationManager(),
        returnsNormally,
      );
    });

    test('should have allowAnimations set to false', () {
      final GameController controller = GameController();
      controller.reset();

      final HeadlessAnimationManager manager = HeadlessAnimationManager();
      expect(manager.allowAnimations, isFalse);
    });

    test('should provide animation controllers', () {
      final GameController controller = GameController();
      controller.reset();

      final HeadlessAnimationManager manager = HeadlessAnimationManager();

      expect(manager.placeAnimationController, isNotNull);
      expect(manager.moveAnimationController, isNotNull);
      expect(manager.removeAnimationController, isNotNull);
    });

    test('should provide animations', () {
      final GameController controller = GameController();
      controller.reset();

      final HeadlessAnimationManager manager = HeadlessAnimationManager();

      expect(manager.placeAnimation, isNotNull);
      expect(manager.moveAnimation, isNotNull);
      expect(manager.removeAnimation, isNotNull);
    });

    test('dispose should not throw', () {
      final GameController controller = GameController();
      controller.reset();

      final HeadlessAnimationManager manager = HeadlessAnimationManager();

      expect(() => manager.dispose(), returnsNormally);
    });
  });
}
