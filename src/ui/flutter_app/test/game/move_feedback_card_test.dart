// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/analysis/move_feedback.dart';
import 'package:sanmill/game_page/services/analysis/move_feedback_analysis_controller.dart';
import 'package:sanmill/game_page/widgets/play_area.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

void main() {
  testWidgets('move feedback exposes a summary and every grading reason', (
    WidgetTester tester,
  ) async {
    const MoveFeedbackResult result = MoveFeedbackResult(
      symbol: MoveFeedbackSymbol.blunder,
      reasons: <MoveFeedbackReason>[
        MoveFeedbackReason.losesWinningResult,
        MoveFeedbackReason.decisiveMaterialLoss,
        MoveFeedbackReason.terminalRuleLoss,
      ],
      bestScore: 80,
      playedScore: 40,
      depth: 18,
      source: MoveFeedbackSource.engine,
      confidence: MoveFeedbackConfidence.high,
      bestMove: 'd6',
      principalVariation: <String>['d6', 'f4'],
    );
    const MoveFeedbackAnalysisState state = MoveFeedbackAnalysisState(
      status: MoveFeedbackAnalysisStatus.ready,
      result: result,
    );

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: Center(
            child: AnalysisMoveFeedbackCard(
              state: state,
              pvExpanded: false,
              onTogglePv: _doNothing,
              onApplyAnnotation: null,
              onAddBestLine: null,
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('play_area_move_feedback_reasons')),
          )
          .data,
      '原因：错失胜势 · 造成决定性子力损失',
    );

    await tester.tap(
      find.byKey(const Key('play_area_move_feedback_show_reasons')),
    );
    await tester.pumpAndSettle();

    expect(find.text('这步棋为何得到此反馈'), findsOneWidget);
    expect(find.text('?? 严重错误'), findsOneWidget);
    expect(
      find.byKey(
        const Key('play_area_move_feedback_reason_losesWinningResult'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key('play_area_move_feedback_reason_decisiveMaterialLoss'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_move_feedback_reason_terminalRuleLoss')),
      findsOneWidget,
    );
  });
}

void _doNothing() {}
