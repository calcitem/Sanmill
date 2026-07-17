// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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
    final PrivateGameRecord record = PrivateGameRecord.create(
      sourcePgn: '1. a7 b6 0-1',
      initialFen: null,
      result: '0-1',
      rules: const RuleSettings(),
      completedAt: DateTime(2024, 1, 27),
      white: 'Human',
      black: 'Human',
      humanSides: const <ReviewSide>{ReviewSide.white, ReviewSide.black},
      finalBoardLayout: '********/********/********',
      moveCount: 2,
    );

    await tester.pumpWidget(
      makeTestableWidget(
        ReviewHistoryPage(initialRecords: <PrivateGameRecord>[record]),
      ),
    );

    expect(find.text('Jan 27, 2024 · 0-1'), findsOneWidget);
    expect(find.text('0-1 · Jan 27, 2024'), findsNothing);
  });
}
