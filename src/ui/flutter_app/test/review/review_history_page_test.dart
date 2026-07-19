// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/review/models/review_models.dart';
import 'package:sanmill/review/widgets/review_history_page.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/locale_helper.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  setUp(() => DB.instance = MockDB());

  testWidgets('uses the home-page date and result order', (
    WidgetTester tester,
  ) async {
    final PrivateGameRecord record = _record(
      pgn: '1. a7 b6 0-1',
      result: '0-1',
      completedAt: DateTime(2024, 1, 27),
      white: 'Human',
      black: 'Human',
    );

    await tester.pumpWidget(
      makeTestableWidget(
        ReviewHistoryPage(initialRecords: <PrivateGameRecord>[record]),
      ),
    );

    expect(find.text('Game history'), findsOneWidget);
    expect(find.text('Jan 27, 2024 · 0-1'), findsOneWidget);
    expect(find.text('0-1 · Jan 27, 2024'), findsNothing);
  });

  testWidgets('searches local history by player result and date', (
    WidgetTester tester,
  ) async {
    final PrivateGameRecord aliceGame = _record(
      pgn: '1. a7 b6 1-0',
      result: '1-0',
      completedAt: DateTime(2024, 1, 27),
      white: 'Alice',
      black: 'Bob',
    );
    final PrivateGameRecord carolGame = _record(
      pgn: '1. d6 f4 0-1',
      result: '0-1',
      completedAt: DateTime(2024, 2, 2),
      white: 'Carol',
      black: 'Dana',
    );

    await tester.pumpWidget(
      makeTestableWidget(
        ReviewHistoryPage(
          initialRecords: <PrivateGameRecord>[aliceGame, carolGame],
        ),
      ),
    );

    expect(find.byKey(const Key('review_history_search')), findsOneWidget);
    await tester.tap(find.byKey(const Key('review_history_search')));
    await tester.pump();

    final Finder searchField = find.byKey(
      const Key('review_history_search_field'),
    );
    expect(searchField, findsOneWidget);
    expect(find.byKey(const Key('review_history_search')), findsNothing);
    expect(find.byKey(const Key('review_history_search_clear')), findsNothing);

    await tester.enterText(searchField, 'alice');
    await tester.pump();
    expect(
      find.byKey(const Key('review_history_search_clear')),
      findsOneWidget,
    );
    expect(find.text('Alice – Bob'), findsOneWidget);
    expect(find.text('Carol – Dana'), findsNothing);

    await tester.enterText(searchField, '0-1');
    await tester.pump();
    expect(find.text('Alice – Bob'), findsNothing);
    expect(find.text('Carol – Dana'), findsOneWidget);

    await tester.enterText(searchField, 'Feb 2, 2024');
    await tester.pump();
    expect(find.text('Carol – Dana'), findsOneWidget);

    await tester.enterText(searchField, 'missing');
    await tester.pump();
    expect(find.byKey(const Key('review_history_no_matches')), findsOneWidget);
    expect(find.text('No matching games'), findsOneWidget);

    await tester.tap(find.byKey(const Key('review_history_search_clear')));
    await tester.pump();
    expect(searchField, findsOneWidget);
    expect(find.text('Alice – Bob'), findsOneWidget);
    expect(find.text('Carol – Dana'), findsOneWidget);

    await tester.enterText(searchField, 'alice');
    await tester.pump();
    await tester.tap(find.byKey(const Key('review_history_search_close')));
    await tester.pump();
    expect(searchField, findsNothing);
    expect(find.text('Alice – Bob'), findsOneWidget);
    expect(find.text('Carol – Dana'), findsOneWidget);
  });
}

PrivateGameRecord _record({
  required String pgn,
  required String result,
  required DateTime completedAt,
  required String white,
  required String black,
}) {
  return PrivateGameRecord.create(
    sourcePgn: pgn,
    initialFen: null,
    result: result,
    rules: const RuleSettings(),
    completedAt: completedAt,
    white: white,
    black: black,
    humanSides: const <ReviewSide>{ReviewSide.white, ReviewSide.black},
    finalBoardLayout: '********/********/********',
    moveCount: 2,
  );
}
