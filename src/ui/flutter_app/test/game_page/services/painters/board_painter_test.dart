// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/services/painters/painters.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';

import '../../../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DB.instance = MockDB()
      ..displaySettings = const DisplaySettings(
        isNotationsShown: true,
        isPieceCountInHandShown: false,
      );
    AppTheme.boardPadding = 28;
    GameController().reset();
  });

  tearDown(() => DB.instance = null);

  testWidgets('adds rotated top and right coordinates only for OTB play', (
    WidgetTester tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    void paintNormal(Canvas canvas) {
      BoardPainter(
        context,
        null,
        shouldDrawBackground: false,
        shouldDrawMillLines: false,
        shouldDrawAnalysisOverlay: false,
      ).paint(canvas, const Size.square(350));
    }

    void paintOverTheBoard(Canvas canvas) {
      BoardPainter(
        context,
        null,
        shouldDrawBackground: false,
        shouldDrawMillLines: false,
        shouldDrawAnalysisOverlay: false,
        showOppositeNotations: true,
      ).paint(canvas, const Size.square(350));
    }

    expect(paintNormal, paintsExactlyCountTimes(#drawParagraph, 14));
    expect(paintNormal, paintsExactlyCountTimes(#rotate, 0));
    expect(paintOverTheBoard, paintsExactlyCountTimes(#drawParagraph, 28));
    expect(paintOverTheBoard, paintsExactlyCountTimes(#rotate, 14));
  });
}
