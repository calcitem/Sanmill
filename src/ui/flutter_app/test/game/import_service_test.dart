// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// import_service_test.dart
//
// End-to-end import tests that validate moves through the Rust kernel.
// Covers the PlayOK numeric format and the rule-variant regression where
// import validation must follow DB().ruleSettings instead of the default
// Nine Men's Morris rules.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';
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

    test(
      "reported 20-turn PlayOK game imports through the final capture",
      () {
        const String playOkText = '''
[Event "?"]
[Site "PlayOK"]
[Date "2026.03.11"]
[Round "-"]
[White "gyorgyusz"]
[Black "nft7489g"]
[Result "1-0"]
[Time "19:16:16"]
[TimeControl "300"]
[GameType "70,0"]
[WhiteElo "1265"]
[BlackElo "1147"]

1. 5 13 2. 20 19 3. 14 21 4. 7 8 5.
23 17 6. 12 16 7. 18 11 8. 4 6 9.
10 22 10.
23-24 22-23 11. 24-15 23-22 12.
15-3 13-9 13. 18-13 22-23 14. 5-2
17-18 15.
10-1x23 8-5 16. 7-8 16-17 17.
12-16 11-10 18. 4-11 5-4 19. 2-5
10-22 20.
3-15x22 1-0''';

        ImportService.import(playOkText);

        final GameRecorder recorder = GameController().newGameRecorder!;
        final List<String> moves = recorder.mainlineMoves
            .map((ExtMove move) => move.move)
            .toList(growable: false);
        expect(moves, hasLength(41));
        expect(
          recorder.mainlineMoves.every(
            (ExtMove move) => move.boardLayout?.length == 26,
          ),
          isTrue,
          reason: 'Every PlayOK move must provide a mini-board preview.',
        );
        expect(moves.take(10), <String>[
          'd6',
          'e4',
          'd2',
          'b2',
          'f4',
          'f2',
          'c5',
          'd5',
          'd1',
          'd3',
        ]);
        expect(moves.sublist(moves.length - 2), <String>['g7-g4', 'xa1']);
      },
      skip: nativeLibrarySkipReason(),
    );
  });

  group("ImportService PGN comments", () {
    test("Root comments are preserved on import", () {
      const String pgnText = '{Imported study note} 1. a7 d7';

      ImportService.import(pgnText);

      final GameRecorder? recorder = GameController().newGameRecorder;
      expect(recorder, isNotNull);
      expect(recorder!.rootComments, <String>['Imported study note']);
      expect(
        recorder.moveHistoryText,
        startsWith('{Imported study note} 1. a7 d7'),
      );
    }, skip: nativeLibrarySkipReason());
  });

  group("ImportService PGN mainline", () {
    test(
      "Tag-paired movetext is imported exactly once",
      () {
        const String pgnText = '''
[Event "Import test"]
[Variant "Nine Men's Morris"]
[Result "*"]

1. d6 f4 2. d2 b4 *''';

        ImportService.import(pgnText);

        final GameRecorder recorder = GameController().newGameRecorder!;
        expect(
          recorder.mainlineMoves.map((ExtMove move) => move.move),
          <String>['d6', 'f4', 'd2', 'b4'],
        );
        expect(recorder.pgnRoot.children, hasLength(1));

        int nodeCount(PgnNode<ExtMove> node) => node.children.fold<int>(
          node.data == null ? 0 : 1,
          (int count, PgnNode<ExtMove> child) => count + nodeCount(child),
        );
        expect(nodeCount(recorder.pgnRoot), 4);
      },
      skip: nativeLibrarySkipReason(),
    );
  });

  group("ImportService rule variants", () {
    test(
      "Known Variant uses record-scoped canonical rules without changing preferences",
      () {
        final Map<String, dynamic> preferenceBefore = DB().ruleSettings
            .toJson();
        const String pgnText =
            '[Variant "Twelve Men\'s Morris"]\n\n'
            '1. a7 d7 2. b6 d6 3. c5xd7 d5';

        ImportService.import(pgnText);

        final GameRecorder recorder = GameController().newGameRecorder!;
        expect(
          recorder.recordedRuleSettings?.toJson(),
          const TwelveMensMorrisRuleSettings().toJson(),
        );
        expect(DB().ruleSettings.toJson(), preferenceBefore);
      },
      skip: nativeLibrarySkipReason(),
    );

    test(
      "Custom Variant keeps the current rules as record-scoped rules",
      () {
        DB().ruleSettings = const TwelveMensMorrisRuleSettings();
        const String pgnText =
            '[Variant "Custom"]\n\n'
            '1. a7 d7 2. b6 d6 3. c5xd7 d5';

        ImportService.import(pgnText);

        final GameRecorder recorder = GameController().newGameRecorder!;
        expect(
          recorder.recordedRuleSettings?.toJson(),
          DB().ruleSettings.toJson(),
        );
      },
      skip: nativeLibrarySkipReason(),
    );

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
