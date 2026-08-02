// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/annotation/annotation_manager.dart';
import 'package:sanmill/game_page/services/painters/painters.dart';
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

  testWidgets('centers the selection highlight around annotation text', (
    WidgetTester tester,
  ) async {
    final AnnotationManager manager = AnnotationManager();
    addTearDown(manager.dispose);
    final AnnotationText annotation = AnnotationText(
      point: const Offset(100, 80),
      text: 'A',
      color: Colors.red,
    );
    manager
      ..addShape(annotation)
      ..selectShape(annotation);
    final TextPainter textPainter = TextPainter(
      text: const TextSpan(
        text: 'A',
        style: TextStyle(color: Colors.red, fontSize: 16),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final Rect expectedHighlight = Rect.fromCenter(
      center: annotation.point,
      width: textPainter.width,
      height: textPainter.height,
    ).inflate(5);

    void paint(Canvas canvas) {
      AnnotationPainter(manager).paint(canvas, const Size.square(200));
    }

    expect(
      paint,
      paints
        ..paragraph()
        ..rect(
          rect: expectedHighlight,
          style: PaintingStyle.stroke,
          strokeWidth: 3,
        ),
    );
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

  testWidgets(
    'all board annotations follow board resize, movement, and rotation',
    (WidgetTester tester) async {
      final Database? previousDatabase = Database.instance;
      Database.instance = MockDB();
      addTearDown(() => Database.instance = previousDatabase);
      AppTheme.boardPadding = 28;

      final AnnotationManager manager = AnnotationManager();
      addTearDown(manager.dispose);
      final GlobalKey boardKey = GlobalKey();
      const Key overlayKey = Key('all_shapes_annotation_overlay');
      late StateSetter setHostState;
      double boardExtent = 320;
      bool isFlipped = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
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
                        child: RotatedBox(
                          quarterTurns: isFlipped ? 2 : 0,
                          child: SizedBox.square(
                            key: boardKey,
                            dimension: boardExtent,
                          ),
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

      Offset overlayPointForBoardPoint(Offset boardPoint) {
        final RenderBox boardBox =
            boardKey.currentContext!.findRenderObject()! as RenderBox;
        final RenderBox overlayBox =
            tester.renderObject(find.byKey(overlayKey)) as RenderBox;
        final Offset boardLocal = offsetFromPointWithInnerSize(
          boardPoint,
          boardBox.size,
        );
        return overlayBox.globalToLocal(boardBox.localToGlobal(boardLocal));
      }

      Offset overlayPointForBoardFraction(Offset boardFraction) {
        final RenderBox boardBox =
            boardKey.currentContext!.findRenderObject()! as RenderBox;
        final RenderBox overlayBox =
            tester.renderObject(find.byKey(overlayKey)) as RenderBox;
        final Offset boardLocal = Offset(
          boardBox.size.width * boardFraction.dx,
          boardBox.size.height * boardFraction.dy,
        );
        return overlayBox.globalToLocal(boardBox.localToGlobal(boardLocal));
      }

      Future<void> tapBoardPoint(AnnotationTool tool, Offset point) async {
        manager.currentTool = tool;
        final Offset overlayTopLeft = tester.getTopLeft(find.byKey(overlayKey));
        await tester.tapAt(overlayTopLeft + overlayPointForBoardPoint(point));
        await tester.pump();
      }

      await tapBoardPoint(AnnotationTool.circle, Offset.zero);
      await tapBoardPoint(AnnotationTool.dot, const Offset(3, 0));
      await tapBoardPoint(AnnotationTool.cross, const Offset(6, 0));
      await tapBoardPoint(AnnotationTool.line, const Offset(0, 3));
      await tapBoardPoint(AnnotationTool.line, const Offset(6, 3));
      await tapBoardPoint(AnnotationTool.arrow, const Offset(0, 6));
      await tapBoardPoint(AnnotationTool.arrow, const Offset(6, 6));

      const Offset rectStartFraction = Offset(0.2, 0.25);
      const Offset rectEndFraction = Offset(0.8, 0.75);
      manager.currentTool = AnnotationTool.rect;
      final Offset overlayTopLeft = tester.getTopLeft(find.byKey(overlayKey));
      await tester.tapAt(
        overlayTopLeft + overlayPointForBoardFraction(rectStartFraction),
      );
      await tester.pump();
      await tester.tapAt(
        overlayTopLeft + overlayPointForBoardFraction(rectEndFraction),
      );
      await tester.pump();

      manager.currentTool = AnnotationTool.text;
      await tester.tapAt(
        overlayTopLeft + overlayPointForBoardPoint(const Offset(3, 6)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final AnnotationCircle circle = manager.shapes
          .whereType<AnnotationCircle>()
          .single;
      final AnnotationDot dot = manager.shapes
          .whereType<AnnotationDot>()
          .single;
      final AnnotationCross cross = manager.shapes
          .whereType<AnnotationCross>()
          .single;
      final AnnotationLine line = manager.shapes
          .whereType<AnnotationLine>()
          .single;
      final AnnotationArrow arrow = manager.shapes
          .whereType<AnnotationArrow>()
          .single;
      final AnnotationRect rect = manager.shapes
          .whereType<AnnotationRect>()
          .single;
      final AnnotationText annotationText = manager.shapes
          .whereType<AnnotationText>()
          .single;

      expect(circle.boardPoint, Offset.zero);
      expect(dot.boardPoint, const Offset(3, 0));
      expect(line.startBoardPoint, const Offset(0, 3));
      expect(line.endBoardPoint, const Offset(6, 3));
      expect(arrow.startBoardPoint, const Offset(0, 6));
      expect(arrow.endBoardPoint, const Offset(6, 6));
      expect(rect.startBoardFraction, isNotNull);
      expect(rect.endBoardFraction, isNotNull);
      expect(annotationText.boardPoint, const Offset(3, 6));

      final double initialCircleRadius = circle.radius;
      final double initialDotRadius = dot.radius;
      final double initialTextScale = annotationText.visualScale;

      setHostState(() => boardExtent = 180);
      await tester.pump();
      await tester.pump();

      expect(circle.radius, lessThan(initialCircleRadius));
      expect(dot.radius, lessThan(initialDotRadius));
      expect(annotationText.visualScale, lessThan(initialTextScale));
      expect(
        (circle.center - overlayPointForBoardPoint(Offset.zero)).distance,
        lessThan(0.01),
      );
      expect(
        (dot.point - overlayPointForBoardPoint(const Offset(3, 0))).distance,
        lessThan(0.01),
      );
      expect(
        (cross.point - overlayPointForBoardPoint(const Offset(6, 0))).distance,
        lessThan(0.01),
      );
      expect(
        (line.start - overlayPointForBoardPoint(const Offset(0, 3))).distance,
        lessThan(0.01),
      );
      expect(
        (line.end - overlayPointForBoardPoint(const Offset(6, 3))).distance,
        lessThan(0.01),
      );
      expect(
        (arrow.start - overlayPointForBoardPoint(const Offset(0, 6))).distance,
        lessThan(0.01),
      );
      expect(
        (arrow.end - overlayPointForBoardPoint(const Offset(6, 6))).distance,
        lessThan(0.01),
      );
      expect(
        (rect.start - overlayPointForBoardFraction(rect.startBoardFraction!))
            .distance,
        lessThan(0.01),
      );
      expect(
        (rect.end - overlayPointForBoardFraction(rect.endBoardFraction!))
            .distance,
        lessThan(0.01),
      );
      expect(
        (annotationText.point - overlayPointForBoardPoint(const Offset(3, 6)))
            .distance,
        lessThan(0.01),
      );

      final Offset circleBeforeFlip = circle.center;
      setHostState(() => isFlipped = true);
      await tester.pump();
      await tester.pump();

      expect((circle.center - circleBeforeFlip).distance, greaterThan(1));
      expect(
        (circle.center - overlayPointForBoardPoint(Offset.zero)).distance,
        lessThan(0.01),
      );
      expect(
        (arrow.end - overlayPointForBoardPoint(const Offset(6, 6))).distance,
        lessThan(0.01),
      );
      expect(
        (rect.start - overlayPointForBoardFraction(rect.startBoardFraction!))
            .distance,
        lessThan(0.01),
      );
    },
  );

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
