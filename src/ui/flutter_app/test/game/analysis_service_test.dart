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
    AnalysisService.debugCreateTemporarySession = null;
  });

  tearDown(() {
    AnalysisMode.disable();
    AnalysisMode.setShowEngineLines(true);
    AnalysisMode.setEngineLineCount(AnalysisMode.defaultEngineLineCount);
    AnalysisMode.setEngineSearchTimeMs(AnalysisMode.defaultEngineSearchTimeMs);
    AnalysisService.debugCreateTemporarySession = null;
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

  testWidgets('single engine line uses configured analysis threads', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    addTearDown(session.dispose);

    DB().generalSettings = const GeneralSettings(
      engineThreads: 8,
      shufflingEnabled: false,
    );
    AnalysisMode.setEngineLineCount(1);

    await _pumpAnalysisButton(tester, session);
    await tester.tap(find.byKey(const Key('analysis_service_toggle')));
    await tester.pump();

    expect(session.requestedMultiPvValues, <int>[1]);
    expect(session.requestedUseLazySmpValues, <bool>[true]);
    expect(session.requestedEngineThreadsValues, <int>[8]);
    expect(session.requestedShufflingValues, <bool>[true]);
    expect(session.requestedSearchAlgorithmValues, <SearchAlgorithm?>[
      SearchAlgorithm.pvs,
    ]);
    expect(session.requestedAiIsLazyValues, <bool>[false]);
    expect(session.requestedSkillLevelValues, <int>[30]);
  });

  testWidgets('multiple engine lines keep analysis single-threaded', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    addTearDown(session.dispose);

    DB().generalSettings = const GeneralSettings(
      engineThreads: 8,
      shufflingEnabled: false,
    );
    AnalysisMode.setEngineLineCount(2);

    await _pumpAnalysisButton(tester, session);
    await tester.tap(find.byKey(const Key('analysis_service_toggle')));
    await tester.pump();

    expect(session.requestedMultiPvValues, <int>[2]);
    expect(session.requestedUseLazySmpValues, <bool>[false]);
    expect(session.requestedEngineThreadsValues, <int>[8]);
    expect(session.requestedShufflingValues, <bool>[false]);
  });

  testWidgets('analysis ignores weak play search settings', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    addTearDown(session.dispose);

    DB().generalSettings = const GeneralSettings(
      searchAlgorithm: SearchAlgorithm.random,
      aiIsLazy: true,
      skillLevel: 3,
      shufflingEnabled: true,
    );
    AnalysisMode.setEngineLineCount(2);

    await _pumpAnalysisButton(tester, session);
    await tester.tap(find.byKey(const Key('analysis_service_toggle')));
    await tester.pump();

    expect(session.requestedSearchAlgorithmValues, <SearchAlgorithm?>[
      SearchAlgorithm.pvs,
    ]);
    expect(session.requestedAiIsLazyValues, <bool>[false]);
    expect(session.requestedSkillLevelValues, <int>[30]);
    expect(session.requestedShufflingValues, <bool>[false]);
    expect(session.requestedUseLazySmpValues, <bool>[false]);
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

  testWidgets('go deeper preserves perfect database analysis source', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    addTearDown(session.dispose);

    const List<MoveAnalysisResult> databaseResults = <MoveAnalysisResult>[
      MoveAnalysisResult(move: 'd6', outcome: AnalysisOutcome.win),
      MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.draw),
    ];
    AnalysisMode.enable(
      databaseResults,
      lineResults: const <MoveAnalysisResult>[
        MoveAnalysisResult(
          move: 'f4',
          outcome: AnalysisOutcome.advantage,
          rank: 1,
          depth: 6,
          line: <String>['f4', 'a1'],
        ),
      ],
      trapMoves: const <String>['a1'],
      source: AnalysisSource.perfectDatabaseAndEngine,
    );

    await _pumpAnalysisButton(tester, session);
    await AnalysisService.goDeeper(
      tester.element(find.byKey(const Key('analysis_service_toggle'))),
    );
    await tester.pump();

    expect(AnalysisMode.source, AnalysisSource.perfectDatabaseAndEngine);
    expect(AnalysisMode.analysisResults, databaseResults);
    expect(AnalysisMode.trapMoves, <String>['a1']);
    expect(AnalysisMode.analysisLineResults.single.move, 'a7');
    expect(AnalysisMode.analysisLineResults.single.depth, 1);
    expect(session.requestedMoveLimitValues, <int>[
      AnalysisMode.maxEngineSearchTimeMs,
    ]);
  });

  testWidgets('go deeper keeps threat-mode analysis', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    final List<_RecordingAnalysisSession> temporarySessions =
        <_RecordingAnalysisSession>[];
    addTearDown(session.dispose);
    AnalysisService
        .debugCreateTemporarySession = (GeneralSettings engineSettings) {
      final _RecordingAnalysisSession temporary = _RecordingAnalysisSession();
      temporarySessions.add(temporary);
      return temporary;
    };

    AnalysisMode.enable(
      const <MoveAnalysisResult>[
        MoveAnalysisResult(
          move: 'f4',
          outcome: AnalysisOutcome.advantage,
          depth: 6,
          line: <String>['f4', 'a1'],
        ),
      ],
      source: AnalysisSource.engine,
      isThreatMode: true,
    );

    await _pumpAnalysisButton(tester, session);
    await AnalysisService.goDeeper(
      tester.element(find.byKey(const Key('analysis_service_toggle'))),
    );
    await tester.pump();

    expect(AnalysisMode.isThreatMode, isTrue);
    expect(AnalysisMode.source, AnalysisSource.engine);
    expect(AnalysisMode.analysisLineResults.single.move, 'a7');
    expect(temporarySessions, hasLength(1));
    expect(temporarySessions.single.requestedMoveLimitValues, <int>[
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
    expect(AnalysisMode.analysisLineResults.single.nodesPerSecond, 4000);

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
          nodesPerSecond: 4000,
          line: <String>['a7'],
        ),
      ];

  final bool completeSearchManually;
  final List<int> requestedMultiPvValues = <int>[];
  final List<int> requestedDepthValues = <int>[];
  final List<int> requestedMoveLimitValues = <int>[];
  final List<bool> requestedUseLazySmpValues = <bool>[];
  final List<int> requestedEngineThreadsValues = <int>[];
  final List<bool> requestedShufflingValues = <bool>[];
  final List<SearchAlgorithm?> requestedSearchAlgorithmValues =
      <SearchAlgorithm?>[];
  final List<bool> requestedAiIsLazyValues = <bool>[];
  final List<int> requestedSkillLevelValues = <int>[];
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
    requestedUseLazySmpValues.add(engineSettings?.useLazySmp ?? false);
    requestedEngineThreadsValues.add(engineSettings?.engineThreads ?? -1);
    requestedShufflingValues.add(engineSettings?.shufflingEnabled ?? false);
    requestedSearchAlgorithmValues.add(engineSettings?.searchAlgorithm);
    requestedAiIsLazyValues.add(engineSettings?.aiIsLazy ?? false);
    requestedSkillLevelValues.add(engineSettings?.skillLevel ?? -1);
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
