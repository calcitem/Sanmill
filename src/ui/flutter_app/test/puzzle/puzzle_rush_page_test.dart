// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/puzzle/pages/puzzle_rush_page.dart';

import '../helpers/locale_helper.dart';

void main() {
  testWidgets('legacy Puzzle Rush opens the untimed continuous challenge', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(makeTestableWidget(const PuzzleRushPage()));
    await tester.pump();

    expect(
      find.byKey(const Key('puzzle_streak_setup_scaffold')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('puzzle_rush_setup_scaffold')), findsNothing);
    expect(find.byIcon(Icons.timer_outlined), findsNothing);
  });
}
