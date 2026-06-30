// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_opening_book_provider.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_rules_port.dart';
import 'package:sanmill/games/mill/opening_book/mill_opening_recognizer.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_repository.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../../helpers/mocks/mock_database.dart';
import '../../helpers/test_native_library.dart';
import 'opening_book/opening_book_test_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String? skip = nativeLibrarySkipReason();

  setUpAll(() async {
    await initRustLibForTests();
    OpeningBookRepository.instance.resetForTest();
    OpeningBookRepository.instance.assetLoader = loadOpeningBookAssetFromDisk;
    await OpeningBookRepository.instance.ensureLoaded();
  });

  tearDownAll(() {
    OpeningBookRepository.instance.resetForTest();
    disposeRustLibForTests();
  });

  setUp(() {
    DB.instance = MockDB();
  });

  group('MillOpeningBookProvider', () {
    test('returns a legal opening move for the initial 9mm position', () {
      (DB.instance! as MockDB).generalSettings = DB().generalSettings.copyWith(
        useOpeningBook: true,
      );

      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);
      final MillOpeningBookProvider provider = MillOpeningBookProvider(
        ruleSettings: const RuleSettings(),
        generalSettings: DB().generalSettings,
      );

      final GameAction? bookMove = provider.lookup(session);
      expect(bookMove, isNotNull);
      expect(
        session.legalActions.any(
          (GameAction action) =>
              action.payload['move'] == bookMove!.payload['move'],
        ),
        isTrue,
      );
    }, skip: skip);

    test('prefers a favoured opening move when the toggle is on', () {
      (DB.instance! as MockDB).generalSettings = DB().generalSettings.copyWith(
        useOpeningBook: true,
        preferFavoredOpenings: true,
        // Deterministic: the selector takes the best-ranked candidate.
        shufflingEnabled: false,
      );

      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);
      final MillOpeningBookProvider provider = MillOpeningBookProvider(
        ruleSettings: const RuleSettings(),
        generalSettings: DB().generalSettings,
        // Start of game: no placements yet (White to move).
        placementHistory: () => const <String>[],
      );

      final GameAction? bookMove = provider.lookup(session);
      expect(bookMove, isNotNull);

      // The chosen move must be a first move of a White-favoured named opening.
      final List<String> favored = MillOpeningRecognizer.favoredOpeningMoves(
        const <String>[],
        OpeningBookRepository.instance.openingsFor(isElFilja: false),
        'W',
      );
      expect(favored, isNotEmpty);
      expect(favored, contains(bookMove!.payload['move']));
    }, skip: skip);

    test('openingRandomness=0 always returns the best book move', () {
      (DB.instance! as MockDB).generalSettings = DB().generalSettings.copyWith(
        useOpeningBook: true,
        shufflingEnabled: true,
        openingRandomness: 0,
      );

      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);
      final MillOpeningBookProvider provider = MillOpeningBookProvider(
        ruleSettings: const RuleSettings(),
        generalSettings: DB().generalSettings,
      );

      // With bias=0 the selector always picks the first (best) candidate. Run
      // several times to confirm it is stable (not just lucky).
      final String? first =
          provider.lookup(session)?.payload['move'] as String?;
      expect(first, isNotNull);
      for (int i = 0; i < 8; i++) {
        final String? move =
            provider.lookup(session)?.payload['move'] as String?;
        expect(move, first);
      }
    }, skip: skip);

    test('returns null when useOpeningBook is disabled', () {
      (DB.instance! as MockDB).generalSettings = DB().generalSettings.copyWith(
        useOpeningBook: false,
      );

      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);
      final MillOpeningBookProvider provider = MillOpeningBookProvider(
        ruleSettings: const RuleSettings(),
        generalSettings: DB().generalSettings,
      );

      expect(provider.lookup(session), isNull);
    }, skip: skip);

    test('returns null for non-9mm rules', () {
      (DB.instance! as MockDB).generalSettings = DB().generalSettings.copyWith(
        useOpeningBook: true,
      );
      (DB.instance! as MockDB).ruleSettings = DB().ruleSettings.copyWith(
        piecesCount: 12,
        hasDiagonalLines: true,
      );

      final NativeMillGameSession session = NativeMillGameSession(
        rules: DB().ruleSettings,
      );
      addTearDown(session.dispose);
      final MillOpeningBookProvider provider = MillOpeningBookProvider(
        ruleSettings: DB().ruleSettings,
        generalSettings: DB().generalSettings,
      );

      expect(provider.lookup(session), isNull);
    }, skip: skip);

    test('skips FEN export outside placing phase', () {
      (DB.instance! as MockDB).generalSettings = DB().generalSettings.copyWith(
        useOpeningBook: true,
      );

      final _CountingFenSession session = _CountingFenSession(
        generalSettings: DB().generalSettings,
      );
      addTearDown(session.dispose);
      expect(
        session.loadFen(
          'OOOO@@@@/OOOO@@@@/O****@** w m s '
          '9 0 9 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes',
        ),
        isTrue,
      );
      expect(session.state.value.phase, 'moving');
      final MillOpeningBookProvider provider = MillOpeningBookProvider(
        ruleSettings: const RuleSettings(),
        generalSettings: DB().generalSettings,
      );

      expect(provider.lookup(session), isNull);
      expect(session.getFenCount, 0);
    }, skip: skip);
  });
}

class _CountingFenSession extends NativeMillGameSession {
  _CountingFenSession({GeneralSettings? generalSettings})
    : super.fromPort(NativeMillRulesPort(generalSettings: generalSettings));

  int getFenCount = 0;

  @override
  String getFen() {
    getFenCount++;
    return super.getFen();
  }
}
