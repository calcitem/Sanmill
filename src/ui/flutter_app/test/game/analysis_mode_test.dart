// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// analysis_mode_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/analysis_mode.dart';

void main() {
  tearDown(AnalysisMode.disable);

  test('tracks full analysis and hint overlay modes separately', () {
    AnalysisMode.enable(const <MoveAnalysisResult>[
      MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.win),
    ]);

    expect(AnalysisMode.isEnabled, isTrue);
    expect(AnalysisMode.isFullAnalysis, isTrue);
    expect(AnalysisMode.isHint, isFalse);

    AnalysisMode.enable(const <MoveAnalysisResult>[
      MoveAnalysisResult(move: 'a1-a4', outcome: AnalysisOutcome.advantage),
    ], mode: AnalysisOverlayMode.hint);

    expect(AnalysisMode.isEnabled, isTrue);
    expect(AnalysisMode.isFullAnalysis, isFalse);
    expect(AnalysisMode.isHint, isTrue);
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
    expect(AnalysisMode.analysisResults, isEmpty);
  });
}
