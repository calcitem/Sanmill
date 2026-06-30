// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// import_service_test.dart
//
// End-to-end import tests that validate moves through the Rust kernel.
// Covers the PlayOK numeric format and the rule-variant regression where
// import validation must follow DB().ruleSettings instead of the default
// Nine Men's Morris rules.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_native_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Import validates moves through the Rust kernel, so the FFI bridge
  // must be initialized against the locally built library.
  setUpAll(initRustLibForTests);

  tearDownAll(disposeRustLibForTests);

  late MockDB mockDB;

  setUp(() {
    mockDB = MockDB();
    DB.instance = mockDB;
    SoundManager.instance = MockAudios();
    final GameController controller = GameController();
    controller.animationManager = MockAnimationManager();
    controller.reset(force: true);
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
  });

  group("ImportService PlayOK", () {
    test(
      "PlayOK numeric move list imports through the Rust kernel",
      () {
        // 1=a7 4=b6 2=d7 5=d6 3=g7 6=f6; "3x4" places g7 completing the
        // a7-d7-g7 mill and removes b6.
        const String playOkText =
            '[Site "PlayOK"]\n'
            '[Event "Mill Game"]\n'
            '1. 1 4 2. 2 5 3. 3x4 6';

        ImportService.import(playOkText);

        final GameRecorder? recorder = GameController().newGameRecorder;
        expect(recorder, isNotNull);
        expect(
          recorder!.mainlineMoves.map((ExtMove m) => m.move).toList(),
          <String>['a7', 'b6', 'd7', 'd6', 'g7', 'xb6', 'f6'],
          reason: 'PlayOK tokens must convert and replay through the kernel',
        );
      },
      skip: nativeLibrarySkipReason(),
    );

    test(
      "PlayOK move list with illegal move is rejected",
      () {
        // "x4" without a preceding mill is an illegal removal.
        const String playOkText =
            '[Site "PlayOK"]\n'
            '1. 1 4 2. x5';

        expect(
          () => ImportService.import(playOkText),
          throwsA(isA<ImportFormatException>()),
        );
      },
      skip: nativeLibrarySkipReason(),
    );
  });

  group("ImportService rule variants", () {
    test(
      "Twelve Men's Morris PGN validates under the active rules",
      () {
        // a7-b6-c5 is a diagonal mill only when hasDiagonalLines is true,
        // so "c5xd7" is legal in Twelve Men's Morris but illegal under the
        // default Nine Men's Morris rules.  Before import validation used
        // DB().ruleSettings this import was wrongly rejected.
        DB().ruleSettings = const TwelveMensMorrisRuleSettings();

        const String pgnText = '1. a7 d7 2. b6 d6 3. c5xd7 d5';

        ImportService.import(pgnText);

        final GameRecorder? recorder = GameController().newGameRecorder;
        expect(recorder, isNotNull);
        expect(
          recorder!.mainlineMoves.map((ExtMove m) => m.move).toList(),
          <String>['a7', 'd7', 'b6', 'd6', 'c5', 'xd7', 'd5'],
          reason: 'Diagonal-mill capture must be accepted under 12MM rules',
        );
      },
      skip: nativeLibrarySkipReason(),
    );

    test(
      "Same PGN is rejected under default Nine Men's Morris rules",
      () {
        // Sanity check for the inverse: with the default rules the c5
        // placement forms no mill, so the capture segment is illegal.
        const String pgnText = '1. a7 d7 2. b6 d6 3. c5xd7 d5';

        expect(
          () => ImportService.import(pgnText),
          throwsA(isA<ImportFormatException>()),
        );
      },
      skip: nativeLibrarySkipReason(),
    );
  });
}
