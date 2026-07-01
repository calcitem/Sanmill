// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

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
    AnalysisMode.setEngineSearchTimeMs(AnalysisMode.defaultEngineSearchTimeMs);
  });

  tearDown(() {
    AnalysisMode.disable();
    AnalysisMode.setShowEngineLines(true);
    AnalysisMode.setEngineLineCount(AnalysisMode.defaultEngineLineCount);
    AnalysisMode.setEngineSearchTimeMs(AnalysisMode.defaultEngineSearchTimeMs);
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
    expect(session.requestedDepthValues, <int>[64]);
    expect(session.requestedMoveLimitValues, <int>[6000]);
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
    expect(session.requestedDepthValues, <int>[64]);
    expect(session.requestedMoveLimitValues, <int>[6000]);
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
    expect(session.requestedDepthValues, <int>[64]);
    expect(session.requestedMoveLimitValues, <int>[6000]);
  });

  testWidgets('normal analysis uses the selected search time', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    addTearDown(session.dispose);

    AnalysisMode.setEngineSearchTimeMs(20000);

    await _pumpAnalysisButton(tester, session);
    await tester.tap(find.byKey(const Key('analysis_service_toggle')));
    await tester.pump();

    expect(session.requestedMultiPvValues, <int>[
      AnalysisMode.defaultEngineLineCount,
    ]);
    expect(session.requestedDepthValues, <int>[64]);
    expect(session.requestedMoveLimitValues, <int>[20000]);
  });

  testWidgets('go deeper requests long analysis time', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    addTearDown(session.dispose);

    await _pumpAnalysisButton(tester, session);
    await AnalysisService.goDeeper(
      tester.element(find.byKey(const Key('analysis_service_toggle'))),
    );
    await tester.pump();

    expect(session.requestedMultiPvValues, <int>[
      AnalysisMode.defaultEngineLineCount,
    ]);
    expect(session.requestedDepthValues, <int>[64]);
    expect(session.requestedMoveLimitValues, <int>[
      AnalysisMode.maxEngineSearchTimeMs,
    ]);
  });

  testWidgets('progressive engine updates keep analysis running', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession(
      completeSearchManually: true,
    );
    addTearDown(session.dispose);

    await _pumpAnalysisButton(tester, session);
    await tester.tap(find.byKey(const Key('analysis_service_toggle')));
    await tester.pump();

    expect(AnalysisMode.isFullAnalysis, isTrue);
    expect(AnalysisMode.isAnalyzing, isTrue);
    expect(AnalysisMode.analysisLineResults.single.depth, 1);

    session.completePendingSearch();
    await tester.pumpAndSettle();

    expect(AnalysisMode.isFullAnalysis, isTrue);
    expect(AnalysisMode.isAnalyzing, isFalse);
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
  _RecordingAnalysisSession({this.completeSearchManually = false})
    : super.fromPort(NativeMillRulesPort());

  static const List<NativeMillPrincipalVariation> _variations =
      <NativeMillPrincipalVariation>[
        NativeMillPrincipalVariation(
          rank: 1,
          move: 'a7',
          score: 0,
          nodes: 1,
          depth: 1,
          line: <String>['a7'],
        ),
      ];

  final bool completeSearchManually;
  final List<int> requestedMultiPvValues = <int>[];
  final List<int> requestedDepthValues = <int>[];
  final List<int> requestedMoveLimitValues = <int>[];
  late final Completer<List<NativeMillPrincipalVariation>> _pendingSearch;

  void completePendingSearch() {
    final Completer<List<NativeMillPrincipalVariation>> pending =
        _pendingSearch;
    assert(!pending.isCompleted, 'Pending analysis search already completed.');
    pending.complete(_variations);
  }

  @override
  Future<List<NativeMillPrincipalVariation>> searchPrincipalVariations({
    int depth = 1,
    int moveLimitMs = 0,
    required int multiPv,
    GeneralSettings? engineSettings,
    void Function(List<NativeMillPrincipalVariation> variations)? onUpdate,
  }) async {
    requestedMultiPvValues.add(multiPv);
    requestedDepthValues.add(depth);
    requestedMoveLimitValues.add(moveLimitMs);
    onUpdate?.call(_variations);
    if (completeSearchManually) {
      final Completer<List<NativeMillPrincipalVariation>> completer =
          Completer<List<NativeMillPrincipalVariation>>();
      _pendingSearch = completer;
      return completer.future;
    }
    return _variations;
  }
}
