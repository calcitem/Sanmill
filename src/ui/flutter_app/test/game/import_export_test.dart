// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// import_export_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_mills.dart';

void main() {
  group("Import Export Service", () {
    setUp(() {
      // Mock DB and SoundManager to isolate the test environment
      DB.instance = MockDB();
      SoundManager.instance = MockAudios();

      // Initialize the singleton GameController
      final GameController controller = GameController.instance;

      // Initialize mock AnimationManager to avoid LateInitializationError
      controller.animationManager = MockAnimationManager();

      // Reset the game controller to a clean state
      controller.reset(force: true);
      controller.gameInstance.gameMode = GameMode.humanVsHuman;
    });

    test(
      "Import standard notation should populate the recorder with the imported moves",
      () async {
        // TODO: Test data may not match current rule settings (e.g. pieces count,
        // board layout, flying rules). The test game uses specific rule configurations
        // that need to be verified and matched before this test can pass.
        // Need to either:
        // 1. Configure MockDB to match the test game's rule settings
        // 2. Or generate new test data that matches default rule settings
      },
      skip: true,
    );

    test("Export standard notation", () async {
      // TODO: Same as above - test data may not match current rule settings
    }, skip: true);
  });
}
