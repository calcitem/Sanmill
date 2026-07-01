// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/analysis/analysis_service.dart';
import 'package:sanmill/game_page/services/analysis_mode.dart';
import 'package:sanmill/game_shell/game_session_scope.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_rules_port.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

import '../helpers/mocks/mock_database.dart';
import '../helpers/test_native_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initRustLibForTests);
  tearDownAll(disposeRustLibForTests);

  setUp(() {
    final MockDB db = MockDB();
    db.generalSettings = const GeneralSettings();
    DB.instance = db;
    AnalysisMode.disable();
    AnalysisMode.setShowEngineLines(true);
    AnalysisMode.setEngineLineCount(AnalysisMode.defaultEngineLineCount);
  });

  tearDown(() {
    AnalysisMode.disable();
    AnalysisMode.setShowEngineLines(true);
    AnalysisMode.setEngineLineCount(AnalysisMode.defaultEngineLineCount);
    DB.instance = null;
  });

  testWidgets('hidden engine lines keep configured PV count', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    addTearDown(session.dispose);

    AnalysisMode.setShowEngineLines(false);
    AnalysisMode.setEngineLineCount(AnalysisMode.maxEngineLineCount);

    await _pumpAnalysisButton(tester, session);
    await tester.tap(find.byKey(const Key('analysis_service_toggle')));
    await tester.pump();

    expect(session.requestedMultiPvValues, <int>[
      AnalysisMode.maxEngineLineCount,
    ]);
  });

  testWidgets('visible engine lines request the default PV count', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    addTearDown(session.dispose);

    await _pumpAnalysisButton(tester, session);
    await tester.tap(find.byKey(const Key('analysis_service_toggle')));
    await tester.pump();

    expect(session.requestedMultiPvValues, <int>[
      AnalysisMode.defaultEngineLineCount,
    ]);
  });

  testWidgets('visible engine lines request the selected PV count', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    addTearDown(session.dispose);

    AnalysisMode.setShowEngineLines(true);
    AnalysisMode.setEngineLineCount(AnalysisMode.maxEngineLineCount);

    await _pumpAnalysisButton(tester, session);
    await tester.tap(find.byKey(const Key('analysis_service_toggle')));
    await tester.pump();

    expect(session.requestedMultiPvValues, <int>[
      AnalysisMode.maxEngineLineCount,
    ]);
  });
}

Future<void> _pumpAnalysisButton(
  WidgetTester tester,
  NativeMillGameSession session,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightThemeData,
      localizationsDelegates: sanmillLocalizationsDelegates,
      supportedLocales: S.supportedLocales,
      locale: const Locale('en'),
      home: GameSessionScope(
        session: session,
        child: Builder(
          builder: (BuildContext context) {
            return TextButton(
              key: const Key('analysis_service_toggle'),
              onPressed: () => AnalysisService.toggle(context),
              child: const Text('Analyze'),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

class _RecordingAnalysisSession extends NativeMillGameSession {
  _RecordingAnalysisSession() : super.fromPort(NativeMillRulesPort());

  final List<int> requestedMultiPvValues = <int>[];

  @override
  Future<List<NativeMillPrincipalVariation>> searchPrincipalVariations({
    int depth = 1,
    int moveLimitMs = 0,
    required int multiPv,
    GeneralSettings? engineSettings,
  }) async {
    requestedMultiPvValues.add(multiPv);
    return const <NativeMillPrincipalVariation>[
      NativeMillPrincipalVariation(
        rank: 1,
        move: 'a7',
        score: 0,
        nodes: 1,
        depth: 1,
        line: <String>['a7'],
      ),
    ];
  }
}
