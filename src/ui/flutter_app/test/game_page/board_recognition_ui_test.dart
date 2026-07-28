// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sanmill/game_page/pages/board_corner_editor_page.dart';
import 'package:sanmill/game_page/pages/board_recognition_review_dialog.dart';
import 'package:sanmill/game_page/services/board_image_recognition.dart';
import 'package:sanmill/game_page/services/board_recognition_geometry.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  testWidgets('corner editor rejects a crossed quadrilateral and can reset', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final Uint8List bytes = _plainImageBytes(640, 480);
    const BoardImageCorners detected = BoardImageCorners(
      topLeft: Offset(0.18, 0.14),
      topRight: Offset(0.86, 0.18),
      bottomRight: Offset(0.82, 0.87),
      bottomLeft: Offset(0.13, 0.82),
    );

    await tester.pumpWidget(
      _localizedApp(
        BoardCornerEditorPage(
          imageBytes: bytes,
          imageSize: const Size(640, 480),
          initialCorners: detected,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder confirm = find.byKey(const Key('board_corner_editor_confirm'));
    final Finder reset = find.byKey(const Key('board_corner_editor_reset'));
    final Offset initialTopLeft = tester.getCenter(
      find.byKey(const Key('board_corner_handle_0')),
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: confirm),
      findsNothing,
    );
    expect(tester.getCenter(confirm).dy, tester.getCenter(reset).dy);
    expect(
      tester.getCenter(confirm).dx,
      greaterThan(tester.getCenter(reset).dx),
    );
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.drag(
      find.byKey(const Key('board_corner_handle_0')),
      const Offset(320, 420),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('board_corner_editor_invalid')), findsOne);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(reset);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('board_corner_editor_invalid')), findsNothing);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    expect(
      tester.getCenter(find.byKey(const Key('board_corner_handle_0'))),
      initialTopLeft,
    );
  });

  testWidgets('corner editor applies an asynchronous corner suggestion', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final Completer<BoardImageCorners?> suggestion =
        Completer<BoardImageCorners?>();
    const BoardImageCorners detected = BoardImageCorners(
      topLeft: Offset(0.18, 0.14),
      topRight: Offset(0.86, 0.18),
      bottomRight: Offset(0.82, 0.87),
      bottomLeft: Offset(0.13, 0.82),
    );

    await tester.pumpWidget(
      _localizedApp(
        BoardCornerEditorPage(
          imageBytes: _plainImageBytes(640, 480),
          imageSize: const Size(640, 480),
          cornerSuggestion: suggestion.future,
        ),
      ),
    );
    await tester.pump();

    final Finder progress = find.byKey(
      const Key('board_corner_editor_detection_progress'),
    );
    final Finder topLeftHandle = find.byKey(const Key('board_corner_handle_0'));
    expect(progress, findsOne);
    final Offset defaultPosition = tester.getCenter(topLeftHandle);

    suggestion.complete(detected);
    await tester.pump();

    expect(progress, findsNothing);
    final Offset detectedPosition = tester.getCenter(topLeftHandle);
    expect(detectedPosition, isNot(defaultPosition));

    await tester.drag(topLeftHandle, const Offset(30, 20));
    await tester.pump();
    await tester.tap(find.byKey(const Key('board_corner_editor_reset')));
    await tester.pump();

    expect(tester.getCenter(topLeftHandle), detectedPosition);
  });

  testWidgets('corner editor preserves edits made before detection finishes', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final Completer<BoardImageCorners?> suggestion =
        Completer<BoardImageCorners?>();

    await tester.pumpWidget(
      _localizedApp(
        BoardCornerEditorPage(
          imageBytes: _plainImageBytes(640, 480),
          imageSize: const Size(640, 480),
          cornerSuggestion: suggestion.future,
        ),
      ),
    );
    await tester.pump();

    final Finder topLeftHandle = find.byKey(const Key('board_corner_handle_0'));
    await tester.drag(topLeftHandle, const Offset(30, 20));
    await tester.pump();
    final Offset editedPosition = tester.getCenter(topLeftHandle);

    suggestion.complete(
      const BoardImageCorners(
        topLeft: Offset(0.30, 0.25),
        topRight: Offset(0.86, 0.18),
        bottomRight: Offset(0.82, 0.87),
        bottomLeft: Offset(0.13, 0.82),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('board_corner_editor_detection_progress')),
      findsNothing,
    );
    expect(tester.getCenter(topLeftHandle), editedPosition);
  });

  testWidgets('review dialog cycles pieces and blocks an empty result', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final List<BoardPoint> points =
        BoardRecognitionGeometry.createCanonicalBoardPoints();
    final Map<int, PieceColor> pieces = <int, PieceColor>{
      for (int index = 0; index < 24; index++) index: PieceColor.none,
      0: PieceColor.white,
      4: PieceColor.black,
    };
    final BoardRecognitionResult result = BoardRecognitionResult.success(
      pieces: pieces,
      confidences: <int, double>{
        for (int index = 0; index < 24; index++) index: 0.9,
        0: 0.4,
      },
      rectifiedImageBytes: _plainImageBytes(768, 768),
      boardPoints: points,
      processedWidth: 768,
      processedHeight: 768,
      debugInfo: BoardRecognitionDebugInfo(),
    );

    await tester.pumpWidget(
      _localizedApp(
        Scaffold(body: BoardRecognitionReviewDialog(result: result)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Tap a point to cycle through empty, white, and black. '
        'Review yellow-outlined points and tap them if the result is '
        'incorrect.',
      ),
      findsOne,
    );
    final Finder board = find.byKey(
      const Key('board_recognition_review_board'),
    );
    final Rect boardRect = tester.getRect(board);
    Offset pointPosition(int index) => Offset(
      boardRect.left + points[index].x / 768 * boardRect.width,
      boardRect.top + points[index].y / 768 * boardRect.height,
    );

    await tester.tapAt(pointPosition(0));
    await tester.pump();
    expect(find.text('White pieces: 0'), findsOne);
    expect(find.text('Black pieces: 2'), findsOne);

    await tester.tapAt(pointPosition(0));
    await tester.tapAt(pointPosition(4));
    await tester.pump();

    final ElevatedButton applyButton = tester.widget<ElevatedButton>(
      find.byKey(const Key('board_recognition_review_apply')),
    );
    expect(applyButton.onPressed, isNull);
  });
}

Widget _localizedApp(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    home: home,
  );
}

Uint8List _plainImageBytes(int width, int height) {
  final img.Image image = img.Image(
    width: width,
    height: height,
    numChannels: 3,
  );
  image.clear(img.ColorRgb8(160, 130, 90));
  return Uint8List.fromList(img.encodePng(image));
}
