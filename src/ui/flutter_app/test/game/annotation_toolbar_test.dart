// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/annotation/annotation_manager.dart';
import 'package:sanmill/game_page/widgets/toolbars/game_toolbar.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

void main() {
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
    expect(find.bySemanticsLabel('Line tool'), findsOneWidget);
    expect(find.bySemanticsLabel('Select red'), findsOneWidget);

    await pumpToolbar(const Locale('zh'));
    expect(find.bySemanticsLabel('直线工具'), findsOneWidget);
    expect(find.bySemanticsLabel('选择红色'), findsOneWidget);
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
