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
}
