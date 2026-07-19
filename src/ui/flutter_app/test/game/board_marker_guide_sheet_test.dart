// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/widgets/board_marker_guide_sheet.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DB.instance = MockDB());
  tearDown(() => DB.instance = null);

  testWidgets('shows every board marker as a visual and semantic guide', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(480, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final SemanticsHandle semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(body: BoardMarkerGuideSheet()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Board marker guide'), findsOneWidget);
    for (final String label in <String>[
      'Selected piece',
      'Legal destination',
      'Removable piece',
      'Completed move',
      'Move awaiting removal',
      'Hint or best suggestion',
      'Secondary engine line',
      'Threat',
      'Move quality',
      'Drawing colors',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    for (final String marker in <String>[
      'selected',
      'legalDestination',
      'removable',
      'completedMove',
      'pendingRemoval',
      'bestSuggestion',
      'secondarySuggestion',
      'threat',
    ]) {
      expect(find.byKey(Key('board_marker_sample_$marker')), findsOneWidget);
    }
    semantics.dispose();
  });

  testWidgets('uses the Simplified Chinese marker terminology', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(body: BoardMarkerGuideSheet()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('棋盘标记说明'), findsOneWidget);
    expect(find.text('已完成着法'), findsOneWidget);
    expect(find.text('提示或最佳建议'), findsOneWidget);
  });
}
