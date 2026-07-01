// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// analysis_mode_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/analysis_mode.dart';

void main() {
  tearDown(() {
    AnalysisMode.disable();
    AnalysisMode.setSmallBoard(false);
    AnalysisMode.setEngineLineCount(AnalysisMode.defaultEngineLineCount);
    AnalysisMode.setEngineSearchTimeMs(AnalysisMode.defaultEngineSearchTimeMs);
  });

  test('tracks full analysis and hint overlay modes separately', () {
    AnalysisMode.enable(const <MoveAnalysisResult>[
      MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.win),
    ]);

    expect(AnalysisMode.isEnabled, isTrue);
    expect(AnalysisMode.isFullAnalysis, isTrue);
    expect(AnalysisMode.isHint, isFalse);
    expect(AnalysisMode.source, AnalysisSource.perfectDatabase);

    AnalysisMode.enable(
      const <MoveAnalysisResult>[
        MoveAnalysisResult(move: 'a1-a4', outcome: AnalysisOutcome.advantage),
      ],
      mode: AnalysisOverlayMode.hint,
      source: AnalysisSource.engine,
    );

    expect(AnalysisMode.isEnabled, isTrue);
    expect(AnalysisMode.isFullAnalysis, isFalse);
    expect(AnalysisMode.isHint, isTrue);
    expect(AnalysisMode.source, AnalysisSource.engine);
    expect(AnalysisMode.analysisResults.single.move, 'a1-a4');
  });

  test('disable clears overlay mode and results', () {
    AnalysisMode.enable(const <MoveAnalysisResult>[
      MoveAnalysisResult(move: 'xa1', outcome: AnalysisOutcome.draw),
    ], mode: AnalysisOverlayMode.hint);

    AnalysisMode.disable();

    expect(AnalysisMode.isEnabled, isFalse);
    expect(AnalysisMode.isFullAnalysis, isFalse);
    expect(AnalysisMode.isHint, isFalse);
    expect(AnalysisMode.source, isNull);
    expect(AnalysisMode.analysisResults, isEmpty);
    expect(AnalysisMode.analysisLineResults, isEmpty);
  });

  test('stores display lines separately from full overlay results', () {
    const List<MoveAnalysisResult> fullResults = <MoveAnalysisResult>[
      MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.loss),
      MoveAnalysisResult(move: 'd6', outcome: AnalysisOutcome.win),
      MoveAnalysisResult(move: 'f4', outcome: AnalysisOutcome.draw),
    ];
    const List<MoveAnalysisResult> lineResults = <MoveAnalysisResult>[
      MoveAnalysisResult(move: 'd6', outcome: AnalysisOutcome.win),
      MoveAnalysisResult(move: 'f4', outcome: AnalysisOutcome.draw),
    ];

    AnalysisMode.enable(fullResults, lineResults: lineResults);

    expect(
      AnalysisMode.analysisResults.map(
        (MoveAnalysisResult result) => result.move,
      ),
      <String>['a1', 'd6', 'f4'],
    );
    expect(
      AnalysisMode.analysisLineResults.map(
        (MoveAnalysisResult result) => result.move,
      ),
      <String>['d6', 'f4'],
    );
  });

  test('tracks perfect database overlay with engine line results', () {
    const List<MoveAnalysisResult> databaseResults = <MoveAnalysisResult>[
      MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.loss),
      MoveAnalysisResult(move: 'd6', outcome: AnalysisOutcome.win),
    ];
    const List<MoveAnalysisResult> engineLines = <MoveAnalysisResult>[
      MoveAnalysisResult(
        move: 'f4',
        outcome: AnalysisOutcome.advantage,
        rank: 1,
        depth: 7,
        nodes: 1024,
        line: <String>['f4', 'a1'],
      ),
    ];

    AnalysisMode.enable(
      databaseResults,
      lineResults: engineLines,
      source: AnalysisSource.perfectDatabaseAndEngine,
    );

    expect(AnalysisMode.source, AnalysisSource.perfectDatabaseAndEngine);
    expect(AnalysisMode.hasEngineLinesSource, isTrue);
    expect(AnalysisMode.analysisResults, databaseResults);
    expect(AnalysisMode.analysisLineResults, engineLines);
    expect(AnalysisMode.normalEngineAnalysisResults, engineLines);
  });

  test('tracks threat mode independently from analysis results', () {
    AnalysisMode.enable(const <MoveAnalysisResult>[
      MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.win),
    ], source: AnalysisSource.engine);

    expect(AnalysisMode.normalEngineAnalysisResults.single.move, 'a1');

    AnalysisMode.enable(
      const <MoveAnalysisResult>[
        MoveAnalysisResult(move: 'd6', outcome: AnalysisOutcome.advantage),
      ],
      source: AnalysisSource.engine,
      isThreatMode: true,
    );

    expect(AnalysisMode.isThreatMode, isTrue);
    expect(AnalysisMode.source, AnalysisSource.engine);
    expect(AnalysisMode.analysisResults.single.move, 'd6');
    expect(AnalysisMode.normalEngineAnalysisResults.single.move, 'a1');

    AnalysisMode.disable();

    expect(AnalysisMode.isThreatMode, isFalse);
    expect(AnalysisMode.normalEngineAnalysisResults, isEmpty);
  });

  test('clears normal engine cache for non-engine analysis overlays', () {
    AnalysisMode.enable(const <MoveAnalysisResult>[
      MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.win),
    ], source: AnalysisSource.engine);

    expect(AnalysisMode.normalEngineAnalysisResults, isNotEmpty);

    AnalysisMode.enable(const <MoveAnalysisResult>[
      MoveAnalysisResult(move: 'd6', outcome: AnalysisOutcome.draw),
    ]);

    expect(AnalysisMode.normalEngineAnalysisResults, isEmpty);
  });

  test('tracks small board preference independently from overlay state', () {
    expect(AnalysisMode.smallBoard, isFalse);

    AnalysisMode.setSmallBoard(true);

    expect(AnalysisMode.smallBoard, isTrue);

    AnalysisMode.disable();

    expect(AnalysisMode.smallBoard, isTrue);
  });

  test('tracks engine line count as an analysis preference', () {
    expect(AnalysisMode.engineLineCount, AnalysisMode.defaultEngineLineCount);

    AnalysisMode.setEngineLineCount(1);
    expect(AnalysisMode.engineLineCount, 1);

    AnalysisMode.setEngineLineCount(-1);
    expect(AnalysisMode.engineLineCount, 0);

    AnalysisMode.setEngineLineCount(99);
    expect(AnalysisMode.engineLineCount, AnalysisMode.maxEngineLineCount);
  });

  test('tracks engine search time as an analysis preference', () {
    expect(
      AnalysisMode.engineSearchTimeMs,
      AnalysisMode.defaultEngineSearchTimeMs,
    );
    expect(AnalysisMode.engineSearchTimeOptionIndex, 2);

    AnalysisMode.setEngineSearchTimeMs(AnalysisMode.maxEngineSearchTimeMs);

    expect(AnalysisMode.engineSearchTimeMs, AnalysisMode.maxEngineSearchTimeMs);
    expect(
      AnalysisMode.engineSearchTimeOptionAt(
        AnalysisMode.engineSearchTimeOptionIndex,
      ),
      AnalysisMode.maxEngineSearchTimeMs,
    );
  });

  test('does not notify when analyzing state is unchanged', () {
    int notifications = 0;
    void listener() {
      notifications += 1;
    }

    AnalysisMode.stateNotifier.addListener(listener);
    addTearDown(() => AnalysisMode.stateNotifier.removeListener(listener));

    AnalysisMode.setAnalyzing(true);
    expect(AnalysisMode.isAnalyzing, isTrue);
    expect(notifications, 2);

    AnalysisMode.setAnalyzing(true);
    expect(notifications, 2);

    AnalysisMode.setAnalyzing(false);
    expect(AnalysisMode.isAnalyzing, isFalse);
    expect(notifications, 4);

    AnalysisMode.setAnalyzing(false);
    expect(notifications, 4);
  });
}
