// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/annotation/annotation_manager.dart';
import 'package:sanmill/game_page/widgets/toolbars/game_toolbar.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  test('tracks whether committed board annotations would be discarded', () {
    final AnnotationManager manager = AnnotationManager();
    addTearDown(manager.dispose);

    expect(manager.hasAnnotations, isFalse);
    manager.addShape(
      AnnotationLine(
        start: Offset.zero,
        end: const Offset(20, 20),
        color: Colors.blue,
      ),
    );
    expect(manager.hasAnnotations, isTrue);

    manager.clear();
    expect(manager.hasAnnotations, isFalse);
  });

  testWidgets('cross marker follows the rendered board size and position', (
    WidgetTester tester,
  ) async {
    final Database? previousDatabase = Database.instance;
    Database.instance = MockDB();
    addTearDown(() => Database.instance = previousDatabase);
    AppTheme.boardPadding = 28;

    final AnnotationManager manager = AnnotationManager()
      ..currentTool = AnnotationTool.cross;
    addTearDown(manager.dispose);
    final GlobalKey boardKey = GlobalKey();
    const Key overlayKey = Key('resizable_annotation_overlay');
    late StateSetter setHostState;
    double boardExtent = 320;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              setHostState = setState;
              return SizedBox(
                width: 600,
                height: 600,
                child: Stack(
                  children: <Widget>[
                    Center(
                      child: SizedBox.square(
                        key: boardKey,
                        dimension: boardExtent,
                      ),
                    ),
                    Positioned.fill(
                      child: AnnotationOverlay(
                        key: overlayKey,
                        annotationManager: manager,
                        gameBoardKey: boardKey,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    Offset expectedOuterPoint() {
      final Offset boardTopLeft = tester.getTopLeft(find.byKey(boardKey));
      final Offset overlayTopLeft = tester.getTopLeft(find.byKey(overlayKey));
      return boardTopLeft +
          Offset(AppTheme.boardPadding, AppTheme.boardPadding) -
          overlayTopLeft;
    }

    final Offset initialOuterPoint = expectedOuterPoint();
    await tester.tapAt(
      tester.getTopLeft(find.byKey(overlayKey)) + initialOuterPoint,
    );
    await tester.pump();

    final AnnotationCross cross = manager.shapes.single as AnnotationCross;
    expect(cross.boardPoint, Offset.zero);
    expect((cross.point - initialOuterPoint).distance, lessThan(0.01));
    double expectedHalfExtent(double extent) {
      final double innerWidth = math.max(0, extent - AppTheme.boardPadding * 2);
      final double pieceDiameter = math.max(
        0,
        innerWidth * DB().displaySettings.pieceWidth / 6 - 1,
      );
      return pieceDiameter / 2;
    }

    expect(cross.crossSize, closeTo(expectedHalfExtent(boardExtent), 0.01));
    final double expandedCrossSize = cross.crossSize;

    setHostState(() => boardExtent = 180);
    await tester.pump();
    await tester.pump();

    expect(cross.crossSize, lessThan(expandedCrossSize));
    expect(cross.crossSize, closeTo(expectedHalfExtent(boardExtent), 0.01));
    expect((cross.point - expectedOuterPoint()).distance, lessThan(0.01));
  });

  testWidgets('localizes annotation toolbar semantics in English and Chinese', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final AnnotationManager manager = AnnotationManager();
    addTearDown(manager.dispose);

    Future<void> pumpToolbar(Locale locale) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: AnnotationToolbar(
              annotationManager: manager,
              isAnnotationMode: true,
              onToggleAnnotationMode: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpToolbar(const Locale('en'));
    expect(find.text('Drawing colors'), findsOneWidget);
    expect(find.bySemanticsLabel('Select green'), findsOneWidget);
    expect(find.bySemanticsLabel('Line tool'), findsOneWidget);
    expect(find.bySemanticsLabel('Select red'), findsOneWidget);
    expect(find.bySemanticsLabel('Select blue'), findsOneWidget);
    expect(find.bySemanticsLabel('Select yellow'), findsOneWidget);
    expect(find.bySemanticsLabel('Select white'), findsNothing);
    expect(find.bySemanticsLabel('Select black'), findsNothing);

    await pumpToolbar(const Locale('zh'));
    expect(find.text('绘图颜色'), findsOneWidget);
    expect(find.bySemanticsLabel('选择绿色'), findsOneWidget);
    expect(find.bySemanticsLabel('直线工具'), findsOneWidget);
    expect(find.bySemanticsLabel('选择红色'), findsOneWidget);
    expect(find.bySemanticsLabel('选择蓝色'), findsOneWidget);
    expect(find.bySemanticsLabel('选择黄色'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('keeps collapsed annotation entry clear of the bottom bar', (
    WidgetTester tester,
  ) async {
    final AnnotationManager manager = AnnotationManager();
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              AnnotationToolbarLayer(
                annotationManager: manager,
                isAnnotationMode: false,
                onToggleAnnotationMode: () {},
              ),
            ],
          ),
        ),
      ),
    );

    final Rect rect = tester.getRect(
      find.byKey(const Key('annotation_toolbar_surface')),
    );
    expect(rect.width, lessThan(100));
    expect(rect.top, 8);
    expect(rect.right, 792);
    expect(rect.bottom, lessThan(544));
  });

  testWidgets('keeps expanded annotation palette beside a landscape board', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(844, 390)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final AnnotationManager manager = AnnotationManager();
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              AnnotationToolbarLayer(
                annotationManager: manager,
                isAnnotationMode: true,
                onToggleAnnotationMode: () {},
              ),
            ],
          ),
        ),
      ),
    );

    final Rect rect = tester.getRect(
      find.byKey(const Key('annotation_toolbar_surface')),
    );
    expect(rect.width, 454);
    expect(rect.left, 390);
    expect(rect.right, 844);
    expect(rect.bottom, 390);
  });

  testWidgets('provides a material surface for the expanded controls', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final AnnotationManager manager = AnnotationManager();
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Stack(
          children: <Widget>[
            AnnotationToolbarLayer(
              annotationManager: manager,
              isAnnotationMode: true,
              onToggleAnnotationMode: () {},
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Line tool'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
