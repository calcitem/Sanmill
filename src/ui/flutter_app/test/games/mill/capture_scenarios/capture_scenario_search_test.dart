// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// capture_scenario_search_test.dart
//
// Native-session replay of curated custodian / intervention capture
// scenarios (migrated from master `integration_test/automated_move_*`).
//
// Two strict invariants of the Rust/FRB native pipeline:
//   1. Negative move lists are rejected by the kernel importer.
//   2. Every curated positive scenario imports, replays, and yields a legal
//      search move.
//
// AI move-sequence parity with master is intentionally NOT asserted: those
// `expectedSequences` were placeholder values tied to the retired C++ engine.
// Rule correctness is covered by `crates/tgf-mill/src/rules/tests.rs`.

// ignore_for_file: avoid_redundant_argument_values

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../../../helpers/mocks/mock_animation_manager.dart';
import '../../../helpers/mocks/mock_audios.dart';
import '../../../helpers/mocks/mock_database.dart';
import '../../../helpers/test_native_library.dart';
import 'capture_scenario_test_data.dart';
import 'capture_scenario_test_models.dart';
import 'capture_scenario_test_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initRustLibForTests);
  tearDownAll(disposeRustLibForTests);

  setUp(() {
    DB.instance = MockDB();
    SoundManager.instance = MockAudios();
    final GameController controller = GameController();
    controller.animationManager = MockAnimationManager();
    controller.reset(force: true);
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
    DB().generalSettings = const GeneralSettings(
      usePerfectDatabase: false,
      shufflingEnabled: false,
    );
  });

  group('Capture scenario native search', () {
    for (final MoveListTestCase testCase in CaptureScenarioTestData.negatives) {
      test(
        'negative: ${testCase.id} is rejected by importer',
        () async {
          final TestCaseResult result =
              await CaptureScenarioTestRunner.runTestCase(testCase);
          expect(
            result.importFailed,
            isTrue,
            reason: '${testCase.id} should be rejected by the importer',
          );
        },
        skip: nativeLibrarySkipReason(),
      );
    }

    for (final MoveListTestCase testCase in CaptureScenarioTestData.positives) {
      test(
        'positive: ${testCase.id} imports, replays, and searches a legal move',
        () async {
          final TestCaseResult result =
              await CaptureScenarioTestRunner.runTestCase(testCase);
          expect(
            result.passed,
            isTrue,
            reason: '${testCase.id}: ${result.errorMessage}',
          );
        },
        skip: nativeLibrarySkipReason(),
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  });
}
