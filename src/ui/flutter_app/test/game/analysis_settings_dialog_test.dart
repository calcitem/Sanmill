// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/analysis_mode.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/play_area.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DB.instance = MockDB();
    GameController().gameInstance.gameMode = GameMode.analysis;
  });

  tearDown(() {
    AnalysisMode.disable();
    DB.instance = null;
  });

  testWidgets('Material analysis settings use standard dismissal affordances', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpDialogHost(tester, platform: TargetPlatform.android);

    await _openDialog(tester);

    expect(
      find.byKey(const Key('play_area_analysis_settings_sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_settings_close')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_analysis_settings_cancel')),
      findsNothing,
    );

    final Finder dismissBarrier = find.bySemanticsLabel('Dismiss');
    expect(dismissBarrier, findsOneWidget);
    final SemanticsNode dismissNode = tester.getSemantics(dismissBarrier);
    expect(
      dismissNode.getSemanticsData().hasAction(SemanticsAction.dismiss),
      isTrue,
    );
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      dismissNode.id,
      SemanticsAction.dismiss,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('play_area_analysis_settings_sheet')),
      findsNothing,
    );

    await _openDialog(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('play_area_analysis_settings_sheet')),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('iOS analysis settings keep a system Cancel action', (
    WidgetTester tester,
  ) async {
    await _pumpDialogHost(tester, platform: TargetPlatform.iOS);

    await _openDialog(tester);

    expect(
      find.byKey(const Key('play_area_analysis_settings_close')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_analysis_settings_cancel')),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('play_area_analysis_settings_cancel')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('play_area_analysis_settings_sheet')),
      findsNothing,
    );
  });
}

Future<void> _pumpDialogHost(
  WidgetTester tester, {
  required TargetPlatform platform,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      localizationsDelegates: sanmillLocalizationsDelegates,
      supportedLocales: S.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (BuildContext context) {
          return Scaffold(
            body: TextButton(
              key: const Key('open_analysis_settings'),
              onPressed: () => unawaited(
                showAnalysisSettingsSheet(context, strings: S.of(context)),
              ),
              child: const Text('Open settings'),
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open_analysis_settings')));
  await tester.pumpAndSettle();
}
