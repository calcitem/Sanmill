// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// mini_board_test.dart

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/color_settings.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';
import 'package:sanmill/game_page/services/mill.dart' show ExtMove, PieceColor;
import 'package:sanmill/game_page/widgets/mini_board.dart';
import 'package:sanmill/games/mill/mill_board_coordinate_maps.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/helpers/color_helpers/color_helper.dart';

import '../helpers/locale_helper.dart';
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
      makeTestableWidget(
        const Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: MiniBoard(boardLayout: 'O*******/********/@*******'),
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

  test('MiniBoardPainter parses a three-ring board layout', () {
    final MiniBoardPainter painter = MiniBoardPainter(
      boardLayout: 'O*******/********/*******@',
    );

    expect(painter.boardState[0], PieceColor.white);
    expect(painter.boardState[23], PieceColor.black);
    expect(painter.showCoordinates, isFalse);
  });

  testWidgets('coordinates are opt-in for analysis-sized boards', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      makeTestableWidget(
        const SizedBox.square(
          dimension: 240,
          child: MiniBoard(
            boardLayout: 'O*******/********/@*******',
            showCoordinates: true,
          ),
        ),
      ),
    );

    final CustomPaint customPaint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(MiniBoard),
        matching: find.byType(CustomPaint),
      ),
    );
    expect((customPaint.painter! as MiniBoardPainter).showCoordinates, isTrue);
  });

  test('quality badge anchors to the initiating piece or removed point', () {
    expect(
      MiniBoardPainter.badgeAnchorSquareForMove('b4'),
      MillBoardCoordinateMaps.notationToLegacySquare('b4'),
    );
    expect(
      MiniBoardPainter.badgeAnchorSquareForMove('a7-b6'),
      MillBoardCoordinateMaps.notationToLegacySquare('b6'),
    );
    expect(
      MiniBoardPainter.badgeAnchorSquareForMove('xb2'),
      MillBoardCoordinateMaps.notationToLegacySquare('b2'),
    );
  });

  test('quality badge symbols meet normal-text contrast for every NAG', () {
    for (int nag = 1; nag <= 6; nag++) {
      final Color background = MiniBoardPainter.qualityBadgeBackgroundColor(
        nag,
      );
      final Color foreground = MiniBoardPainter.qualityBadgeForegroundColor(
        nag,
      );
      expect(
        colorContrastRatio(foreground, background),
        greaterThanOrEqualTo(normalTextMinimumContrastRatio),
        reason: 'NAG \$$nag must remain readable.',
      );
    }
    expect(MiniBoardPainter.qualityBadgeForegroundColor(2), Colors.black);
    expect(MiniBoardPainter.qualityBadgeForegroundColor(6), Colors.black);
  });

  test('piece outlines and numbers contrast with light and dark pieces', () {
    expect(MiniBoardPainter.pieceOutlineColor(Colors.white), Colors.black);
    expect(MiniBoardPainter.pieceOutlineColor(Colors.black), Colors.white);
    for (final Color pieceColor in <Color>[Colors.white, Colors.black]) {
      expect(
        colorContrastRatio(
          MiniBoardPainter.pieceOutlineColor(pieceColor),
          pieceColor,
        ),
        greaterThanOrEqualTo(normalTextMinimumContrastRatio),
      );
      expect(
        colorContrastRatio(
          MiniBoardPainter.pieceNumberColor(pieceColor),
          pieceColor,
        ),
        greaterThanOrEqualTo(normalTextMinimumContrastRatio),
      );
    }
  });

  test('a white piece is painted with a visible dark outline', () async {
    DB().colorSettings = const ColorSettings(
      boardLineColor: Colors.black,
      boardBackgroundColor: Colors.white,
      whitePieceColor: Colors.white,
      blackPieceColor: Colors.black,
    );
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    const Size size = Size.square(200);
    canvas.drawColor(Colors.white, BlendMode.src);
    MiniBoardPainter(
      boardLayout: 'O*******/********/********',
    ).paint(canvas, size);
    final ui.Image image = await recorder.endRecording().toImage(200, 200);
    final ByteData data = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;

    Color pixelAt(int x, int y) {
      final int offset = (y * 200 + x) * 4;
      return Color.fromARGB(
        data.getUint8(offset + 3),
        data.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      );
    }

    final Color pieceCenter = pixelAt(100, 64);
    final Color pieceOutline = pixelAt(100, 55);
    expect(pieceCenter.computeLuminance(), greaterThan(0.9));
    expect(
      colorContrastRatio(pieceOutline, pieceCenter),
      greaterThanOrEqualTo(normalTextMinimumContrastRatio),
    );
    image.dispose();
  });

  testWidgets('piece numbers follow the main board display preference', (
    WidgetTester tester,
  ) async {
    DB().displaySettings = const DisplaySettings(isNumbersOnPiecesShown: true);
    await tester.pumpWidget(
      makeTestableWidget(
        const SizedBox.square(
          dimension: 240,
          child: MiniBoard(
            boardLayout: 'O*******/********/@*******',
            pieceNumbersByNode: <int, int>{0: 3, 16: 8},
          ),
        ),
      ),
    );

    final CustomPaint customPaint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(MiniBoard),
        matching: find.byType(CustomPaint),
      ),
    );
    final MiniBoardPainter painter = customPaint.painter! as MiniBoardPainter;
    expect(painter.showPieceNumbers, isTrue);
    expect(painter.pieceNumbersByNode, <int, int>{0: 3, 16: 8});
  });

  testWidgets('replay reads an imported NAG and anchors a capture chain', (
    WidgetTester tester,
  ) async {
    final PgnNode<ExtMove> initiating = PgnNode<ExtMove>(
      ExtMove('a7-b6', side: PieceColor.white),
    );
    final PgnNode<ExtMove> removal = PgnNode<ExtMove>(
      ExtMove('xb2', side: PieceColor.white, nags: <int>[5]),
    )..parent = initiating;
    initiating.children.add(removal);

    await tester.pumpWidget(
      makeTestableWidget(
        Center(
          child: SizedBox.square(
            dimension: 120,
            child: MiniBoard(
              boardLayout: 'O*******/********/@*******',
              extMove: removal.data,
              node: removal,
            ),
          ),
        ),
      ),
    );

    final CustomPaint customPaint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(MiniBoard),
        matching: find.byType(CustomPaint),
      ),
    );
    final MiniBoardPainter painter = customPaint.painter! as MiniBoardPainter;
    expect(painter.qualityNag, 5);
    expect(painter.badgeAnchorMove, 'a7-b6');

    final Finder qualitySemantics = find.byWidgetPredicate(
      (Widget widget) =>
          widget is Semantics &&
          (widget.properties.label ?? '').contains('!? Interesting'),
    );
    expect(qualitySemantics, findsOneWidget);
  });
}
