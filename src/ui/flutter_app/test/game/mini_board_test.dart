// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// mini_board_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/widgets/mini_board.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DB.instance = MockDB();
  });

  testWidgets('MiniBoard gives its painter the full board size', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: MiniBoard(boardLayout: 'O*******/********/@*******'),
            ),
          ),
        ),
      ),
    );

    final Finder boardPainter = find.descendant(
      of: find.byType(MiniBoard),
      matching: find.byType(CustomPaint),
    );

    expect(boardPainter, findsOneWidget);
    expect(tester.getSize(boardPainter), const Size(120, 120));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
