// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sanmill/game_page/services/board_image_recognition.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/board_recognition_debug_view.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  testWidgets('shows localized board-recognition diagnostic stages', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final Uint8List imageBytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 1, height: 1)),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: BoardRecognitionDebugView(
              imageBytes: imageBytes,
              boardPoints: const <BoardPoint>[],
              resultMap: const <int, PieceColor>{},
              processedImageWidth: 1,
              processedImageHeight: 1,
              debugInfo: BoardRecognitionDebugInfo(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1. Original image'), findsOneWidget);
    expect(find.text('7. Point detection'), findsOneWidget);
    expect(find.text('10. Final result'), findsOneWidget);
    expect(find.text('Board recognition failed.'), findsWidgets);
    expect(find.textContaining('Final Recognition'), findsNothing);
    expect(find.textContaining('Nine-piece Chess'), findsNothing);
  });
}
