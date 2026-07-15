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
    AnalysisService.invalidateBestMoveHintCache();
  });

  tearDown(() {
    AnalysisMode.disable();
    AnalysisMode.setShowEngineLines(true);
    AnalysisMode.setEngineLineCount(AnalysisMode.defaultEngineLineCount);
    AnalysisMode.setEngineSearchTimeMs(AnalysisMode.defaultEngineSearchTimeMs);
    AnalysisService.debugCreateTemporarySession = null;
    AnalysisService.invalidateBestMoveHintCache();
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

  testWidgets('best move hint deepens at full strength until stopped', (
    WidgetTester tester,
  ) async {
    const List<NativeMillPrincipalVariation> shallow =
        <NativeMillPrincipalVariation>[
          NativeMillPrincipalVariation(
            rank: 1,
            move: 'a7',
            score: 0,
            nodes: 8,
            depth: 1,
            line: <String>['a7'],
          ),
        ];
    const List<NativeMillPrincipalVariation> deeper =
        <NativeMillPrincipalVariation>[
          NativeMillPrincipalVariation(
            rank: 1,
            move: 'd6',
            score: 12,
            nodes: 4096,
            depth: 4,
            line: <String>['d6', 'f4'],
          ),
        ];
    final _RecordingAnalysisSession session = _RecordingAnalysisSession(
      completeSearchManually: true,
      variations: deeper,
      progressUpdates: const <List<NativeMillPrincipalVariation>>[
        shallow,
        deeper,
      ],
    );
    addTearDown(session.dispose);

    DB().generalSettings = const GeneralSettings(
      engineThreads: 8,
      searchAlgorithm: SearchAlgorithm.random,
      aiIsLazy: true,
      skillLevel: 3,
      shufflingEnabled: false,
    );

    await _pumpAnalysisButton(tester, session);
    final Future<bool> hintSearch = AnalysisService.showBestMoveHint(
      tester.element(find.byKey(const Key('analysis_service_toggle'))),
    );
    await tester.pump();

    expect(session.requestedMultiPvValues, <int>[1]);
    expect(session.requestedDepthValues, <int>[32]);
    expect(session.requestedMoveLimitValues, <int>[10 * 60 * 1000]);
    expect(session.requestedSearchAlgorithmValues, <SearchAlgorithm?>[
      SearchAlgorithm.pvs,
    ]);
    expect(session.requestedAiIsLazyValues, <bool>[false]);
    expect(session.requestedSkillLevelValues, <int>[30]);
    expect(session.requestedUseLazySmpValues, <bool>[true]);
    expect(session.requestedShufflingValues, <bool>[true]);
    expect(AnalysisService.isBestMoveHintSearching, isTrue);
    expect(AnalysisMode.isHint, isTrue);
    expect(AnalysisMode.isAnalyzing, isTrue);
    expect(AnalysisMode.analysisResults.single.move, 'd6');
    expect(AnalysisMode.analysisResults.single.depth, 4);
    expect(AnalysisMode.analysisResults.single.line, <String>['d6', 'f4']);

    bool stopCompleted = false;
    final Future<void> stop = AnalysisService.stopBestMoveHintAndWait().then((
      _,
    ) {
      stopCompleted = true;
    });
    await tester.pump();
    expect(AnalysisService.isBestMoveHintSearching, isFalse);
    expect(AnalysisMode.isHint, isFalse);
    expect(AnalysisMode.isAnalyzing, isFalse);
    expect(stopCompleted, isFalse);

    session.completePendingSearch();
    await stop;
    expect(stopCompleted, isTrue);
    expect(await hintSearch, isFalse);
  });

  testWidgets('clearing a hint overlay cancels stale search updates', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession(
      completeSearchManually: true,
    );
    addTearDown(session.dispose);

    await _pumpAnalysisButton(tester, session);
    final Future<bool> hintSearch = AnalysisService.showBestMoveHint(
      tester.element(find.byKey(const Key('analysis_service_toggle'))),
    );
    await tester.pump();

    expect(AnalysisService.isBestMoveHintSearching, isTrue);
    expect(AnalysisMode.analysisResults.single.move, 'a7');

    AnalysisMode.disable();
    expect(AnalysisService.isBestMoveHintSearching, isFalse);
    expect(AnalysisMode.isHint, isFalse);

    session.completePendingSearch();
    expect(await hintSearch, isFalse);
    expect(AnalysisMode.isEnabled, isFalse);
    expect(AnalysisMode.analysisResults, isEmpty);
  });

  testWidgets('restarted hint keeps cached depth until the move changes', (
    WidgetTester tester,
  ) async {
    final _ControlledAnalysisSession session = _ControlledAnalysisSession();
    addTearDown(session.dispose);

    await _pumpAnalysisButton(tester, session);
    final BuildContext context = tester.element(
      find.byKey(const Key('analysis_service_toggle')),
    );

    final Future<bool> firstHint = AnalysisService.showBestMoveHint(context);
    await tester.pump();
    session.emit(0, const <NativeMillPrincipalVariation>[
      NativeMillPrincipalVariation(
        rank: 1,
        move: 'd6',
        score: 12,
        nodes: 4096,
        depth: 8,
        line: <String>['d6', 'f4', 'a1'],
      ),
    ]);
    expect(AnalysisMode.analysisResults.single.move, 'd6');
    expect(AnalysisMode.analysisResults.single.depth, 8);

    final Future<void> firstStop = AnalysisService.stopBestMoveHintAndWait();
    session.complete(0);
    await firstStop;
    expect(await firstHint, isFalse);

    final Future<bool> restartedHint = AnalysisService.showBestMoveHint(
      context,
    );
    await tester.pump();

    expect(AnalysisMode.isHint, isTrue);
    expect(AnalysisMode.isAnalyzing, isTrue);
    expect(AnalysisMode.analysisResults.single.move, 'd6');
    expect(AnalysisMode.analysisResults.single.depth, 8);
    expect(AnalysisMode.analysisResults.single.line, <String>[
      'd6',
      'f4',
      'a1',
    ]);

    session.emit(1, const <NativeMillPrincipalVariation>[
      NativeMillPrincipalVariation(
        rank: 1,
        move: 'd6',
        score: 3,
        nodes: 16,
        depth: 2,
        line: <String>['d6'],
      ),
    ]);
    expect(AnalysisMode.analysisResults.single.move, 'd6');
    expect(AnalysisMode.analysisResults.single.depth, 8);

    session.emit(1, const <NativeMillPrincipalVariation>[
      NativeMillPrincipalVariation(
        rank: 1,
        move: 'a7',
        score: 5,
        nodes: 32,
        depth: 3,
        line: <String>['a7', 'd6'],
      ),
    ]);
    expect(AnalysisMode.analysisResults.single.move, 'a7');
    expect(AnalysisMode.analysisResults.single.depth, 3);
    expect(AnalysisMode.analysisResults.single.line, <String>['a7', 'd6']);

    final Future<void> secondStop = AnalysisService.stopBestMoveHintAndWait();
    session.complete(1);
    await secondStop;
    expect(await restartedHint, isFalse);
  });

  testWidgets('hint cache is not reused for a changed position', (
    WidgetTester tester,
  ) async {
    final _ControlledAnalysisSession session = _ControlledAnalysisSession();
    addTearDown(session.dispose);

    await _pumpAnalysisButton(tester, session);
    final BuildContext context = tester.element(
      find.byKey(const Key('analysis_service_toggle')),
    );

    final Future<bool> firstHint = AnalysisService.showBestMoveHint(context);
    await tester.pump();
    session.emit(0, const <NativeMillPrincipalVariation>[
      NativeMillPrincipalVariation(
        rank: 1,
        move: 'd6',
        score: 12,
        nodes: 4096,
        depth: 8,
        line: <String>['d6', 'f4'],
      ),
    ]);
    final Future<void> firstStop = AnalysisService.stopBestMoveHintAndWait();
    session.complete(0);
    await firstStop;
    expect(await firstHint, isFalse);

    session.fen = '8/8/8 w p p 0 0 0 0 1';
    final Future<bool> changedPositionHint = AnalysisService.showBestMoveHint(
      context,
    );
    await tester.pump();

    expect(AnalysisMode.isHint, isTrue);
    expect(AnalysisMode.analysisResults, isEmpty);

    final Future<void> secondStop = AnalysisService.stopBestMoveHintAndWait();
    session.complete(1);
    await secondStop;
    expect(await changedPositionHint, isFalse);
  });

  testWidgets(
    'a stopped hint can still be awaited while native search drains',
    (WidgetTester tester) async {
      final _RecordingAnalysisSession session = _RecordingAnalysisSession(
        completeSearchManually: true,
      );
      addTearDown(session.dispose);

      await _pumpAnalysisButton(tester, session);
      final Future<bool> hintSearch = AnalysisService.showBestMoveHint(
        tester.element(find.byKey(const Key('analysis_service_toggle'))),
      );
      await tester.pump();

      AnalysisService.stopBestMoveHint();
      expect(AnalysisService.isBestMoveHintSearching, isFalse);
      expect(AnalysisMode.isHint, isFalse);

      bool drained = false;
      final Future<void> waitForDrain =
          AnalysisService.stopBestMoveHintAndWait().then((_) => drained = true);
      await tester.pump();
      expect(drained, isFalse);

      session.completePendingSearch();
      await waitForDrain;
      expect(drained, isTrue);
      expect(await hintSearch, isFalse);
    },
  );

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
    expect(AnalysisMode.isEngineAnalysisDeep, isTrue);

    await AnalysisService.goDeeper(
      tester.element(find.byKey(const Key('analysis_service_toggle'))),
    );
    await tester.pump();

    expect(session.requestedMoveLimitValues, <int>[
      AnalysisMode.maxEngineSearchTimeMs,
    ]);
  });

  testWidgets('go deeper keeps deeper existing engine lines', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession(
      variations: const <NativeMillPrincipalVariation>[
        NativeMillPrincipalVariation(
          rank: 1,
          move: 'a7',
          score: 0,
          nodes: 64,
          depth: 2,
          line: <String>['a7', 'd6'],
        ),
      ],
    );
    addTearDown(session.dispose);

    AnalysisMode.enable(const <MoveAnalysisResult>[
      MoveAnalysisResult(
        move: 'd6',
        outcome: AnalysisOutcome.advantage,
        rank: 1,
        depth: 8,
        nodes: 4096,
        line: <String>['d6', 'f4', 'a1'],
      ),
    ], source: AnalysisSource.engine);

    await _pumpAnalysisButton(tester, session);
    await AnalysisService.goDeeper(
      tester.element(find.byKey(const Key('analysis_service_toggle'))),
    );
    await tester.pump();

    expect(AnalysisMode.analysisLineResults.single.move, 'd6');
    expect(AnalysisMode.analysisLineResults.single.depth, 8);
    expect(AnalysisMode.analysisLineResults.single.line, <String>[
      'd6',
      'f4',
      'a1',
    ]);
  });

  testWidgets('go deeper replaces engine lines after reaching deeper depth', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession(
      variations: const <NativeMillPrincipalVariation>[
        NativeMillPrincipalVariation(
          rank: 1,
          move: 'a7',
          score: 0,
          nodes: 8192,
          depth: 12,
          line: <String>['a7', 'd6', 'f4'],
        ),
      ],
    );
    addTearDown(session.dispose);

    AnalysisMode.enable(const <MoveAnalysisResult>[
      MoveAnalysisResult(
        move: 'd6',
        outcome: AnalysisOutcome.advantage,
        rank: 1,
        depth: 8,
        nodes: 4096,
        line: <String>['d6', 'f4', 'a1'],
      ),
    ], source: AnalysisSource.engine);

    await _pumpAnalysisButton(tester, session);
    await AnalysisService.goDeeper(
      tester.element(find.byKey(const Key('analysis_service_toggle'))),
    );
    await tester.pump();

    expect(AnalysisMode.analysisLineResults.single.move, 'a7');
    expect(AnalysisMode.analysisLineResults.single.depth, 12);
    expect(AnalysisMode.analysisLineResults.single.line, <String>[
      'a7',
      'd6',
      'f4',
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
    expect(AnalysisMode.analysisLineResults.single.move, 'f4');
    expect(AnalysisMode.analysisLineResults.single.depth, 6);
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

  testWidgets('position refresh clears threat mode before new engine result', (
    WidgetTester tester,
  ) async {
    final _RecordingAnalysisSession session = _RecordingAnalysisSession(
      completeSearchManually: true,
      emitProgressUpdate: false,
    );
    addTearDown(session.dispose);

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

    final Future<void> refresh = AnalysisService.refreshForCurrentPosition(
      tester.element(find.byKey(const Key('analysis_service_toggle'))),
    );
    await tester.pump();

    expect(AnalysisMode.isThreatMode, isFalse);
    expect(AnalysisMode.isAnalyzing, isTrue);
    expect(AnalysisMode.isFullAnalysis, isFalse);
    expect(session.requestedMoveLimitValues, <int>[
      AnalysisMode.engineSearchTimeMs,
    ]);

    session.completePendingSearch();
    await refresh;
    await tester.pump();

    expect(AnalysisMode.isThreatMode, isFalse);
    expect(AnalysisMode.source, AnalysisSource.engine);
    expect(AnalysisMode.analysisLineResults.single.move, 'a7');
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
  _RecordingAnalysisSession({
    this.completeSearchManually = false,
    this.emitProgressUpdate = true,
    this.variations = _defaultVariations,
    this.progressUpdates,
  }) : super.fromPort(NativeMillRulesPort());

  static const List<NativeMillPrincipalVariation> _defaultVariations =
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
  final bool emitProgressUpdate;
  final List<NativeMillPrincipalVariation> variations;
  final List<List<NativeMillPrincipalVariation>>? progressUpdates;
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
    pending.complete(variations);
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
    if (emitProgressUpdate) {
      final List<List<NativeMillPrincipalVariation>> updates =
          progressUpdates ?? <List<NativeMillPrincipalVariation>>[variations];
      for (final List<NativeMillPrincipalVariation> update in updates) {
        onUpdate?.call(update);
      }
    }
    if (completeSearchManually) {
      final Completer<List<NativeMillPrincipalVariation>> completer =
          Completer<List<NativeMillPrincipalVariation>>();
      _pendingSearch = completer;
      return completer.future;
    }
    return variations;
  }
}

class _ControlledAnalysisSession extends NativeMillGameSession {
  _ControlledAnalysisSession() : super.fromPort(NativeMillRulesPort());

  String fen = '********/********/******** w p p 0 9 9 0 0 0';
  final List<_ControlledAnalysisSearch> searches =
      <_ControlledAnalysisSearch>[];

  void emit(int searchIndex, List<NativeMillPrincipalVariation> variations) {
    searches[searchIndex].onUpdate?.call(variations);
  }

  void complete(
    int searchIndex, {
    List<NativeMillPrincipalVariation> variations =
        const <NativeMillPrincipalVariation>[],
  }) {
    final Completer<List<NativeMillPrincipalVariation>> completer =
        searches[searchIndex].completer;
    assert(!completer.isCompleted, 'Controlled search already completed.');
    completer.complete(variations);
  }

  @override
  String getFen() => fen;

  @override
  Future<List<NativeMillPrincipalVariation>> searchPrincipalVariations({
    int depth = 1,
    int moveLimitMs = 0,
    required int multiPv,
    GeneralSettings? engineSettings,
    void Function(List<NativeMillPrincipalVariation> variations)? onUpdate,
  }) {
    final _ControlledAnalysisSearch search = _ControlledAnalysisSearch(
      onUpdate,
    );
    searches.add(search);
    return search.completer.future;
  }
}

class _ControlledAnalysisSearch {
  _ControlledAnalysisSearch(this.onUpdate);

  final void Function(List<NativeMillPrincipalVariation> variations)? onUpdate;
  final Completer<List<NativeMillPrincipalVariation>> completer =
      Completer<List<NativeMillPrincipalVariation>>();
}
