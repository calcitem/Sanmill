// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/game_page.dart';
import 'package:sanmill/review/models/review_models.dart';
import 'package:sanmill/review/services/review_analysis_service.dart';
import 'package:sanmill/review/widgets/review_page.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/locale_helper.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DB.instance = MockDB());

  testWidgets('game result dialog exposes the primary review entry', (
    WidgetTester tester,
  ) async {
    final GameMode previousMode = GameController().gameInstance.gameMode;
    addTearDown(() => GameController().gameInstance.gameMode = previousMode);
    GameController().gameInstance.gameMode = GameMode.aiVsAi;

    await tester.pumpWidget(
      makeTestableWidget(GameResultAlertDialog(winner: PieceColor.white)),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('ai_vs_ai_game_result_dialog_review_button')),
      findsOneWidget,
    );
    expect(find.text('Review game'), findsOneWidget);
  });

  testWidgets(
    'uses board-first phone layout without a numeric accuracy score',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_reviewApp());
      await tester.pump();

      expect(find.byKey(const Key('review_phone_layout')), findsOneWidget);
      expect(find.byKey(const Key('review_wide_layout')), findsNothing);
      expect(find.byKey(const Key('review_structure_summary')), findsOneWidget);
      expect(find.byKey(const Key('review_board')), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);

      final SemanticsNode board = tester.getSemantics(
        find.byKey(const Key('review_board')),
      );
      expect(board.label, contains('?'));
      expect(board.label, contains('Mistake'));
    },
  );

  testWidgets(
    'uses side-by-side layout on tablet and exposes correction flow',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_reviewApp());
      await tester.pump();

      expect(find.byKey(const Key('review_wide_layout')), findsOneWidget);
      expect(find.byKey(const Key('review_phone_layout')), findsNothing);
      expect(find.byKey(const Key('review_correction')), findsOneWidget);
      expect(find.text('1/1'), findsOneWidget);
      expect(find.text('d6xf4'), findsOneWidget);

      final Finder goodChoice = find.byKey(
        const Key('review_correction_choice_b6'),
      );
      await tester.drag(
        find.byKey(const Key('review_analysis_panel')),
        const Offset(0, -180),
      );
      await tester.pump();
      await tester.tap(goodChoice);
      await tester.pump();
      expect(find.text('Accepted: best or good move.'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Show answer'), findsOneWidget);
    },
  );

  testWidgets('uses side-by-side layout in phone landscape', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(844, 390));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_reviewApp());
    await tester.pump();

    expect(find.byKey(const Key('review_wide_layout')), findsOneWidget);
    expect(find.byKey(const Key('review_phone_layout')), findsNothing);
    expect(find.byKey(const Key('review_board')), findsOneWidget);
    expect(find.byKey(const Key('review_analysis_panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancels an active analysis and exposes restart state', (
    WidgetTester tester,
  ) async {
    final _PendingReviewAnalysisService service =
        _PendingReviewAnalysisService();
    await tester.pumpWidget(
      makeTestableWidget(
        ReviewPage(record: _record(), analysisService: service),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('review_analysis_progress')), findsOneWidget);
    await tester.tap(find.byKey(const Key('review_cancel_analysis')));
    await tester.pump();

    expect(service.cancelCount, 1);
    expect(find.text('Analysis cancelled'), findsOneWidget);
    expect(find.text('Analyze again'), findsOneWidget);
  });
}

Widget _reviewApp() {
  final PrivateGameRecord record = _record();
  return makeTestableWidget(
    ReviewPage(
      record: record,
      initialReport: _report(record),
      autoAnalyze: false,
    ),
  );
}

PrivateGameRecord _record() {
  final DateTime now = DateTime.utc(2026, 7, 16);
  return PrivateGameRecord.create(
    sourcePgn: '1. a7 b6 *',
    initialFen: null,
    result: '*',
    rules: const TwelveMensMorrisRuleSettings(),
    completedAt: now,
    white: 'Human',
    black: 'AI',
    humanSides: const <ReviewSide>{ReviewSide.white},
    finalBoardLayout: 'O*******/********/@*******',
    moveCount: 2,
  );
}

ReviewReport _report(
  PrivateGameRecord record, {
  ReviewStatus status = ReviewStatus.complete,
}) {
  final DateTime now = DateTime.utc(2026, 7, 16);
  return ReviewReport(
    recordId: record.id,
    pgnHash: pgnFingerprint(record.sourcePgn),
    rulesHash: record.rulesFingerprint,
    engineVersion: reviewEngineVersion,
    profile: ReviewProfile.quick,
    status: status,
    actions: status == ReviewStatus.cancelled
        ? const <ReviewActionEvaluation>[]
        : <ReviewActionEvaluation>[
            _action(
              index: 0,
              move: 'a7',
              side: ReviewSide.white,
              human: true,
              grade: ReviewGrade.mistake,
            ),
            _action(
              index: 1,
              move: 'b6',
              side: ReviewSide.black,
              human: false,
              grade: ReviewGrade.good,
            ),
          ],
    turns: status == ReviewStatus.cancelled
        ? const <ReviewTurnBoundary>[]
        : const <ReviewTurnBoundary>[
            ReviewTurnBoundary(
              groupIndex: 0,
              startAtomicIndex: 0,
              endAtomicIndex: 0,
              san: 'a7',
              anchorMove: 'a7',
              side: ReviewSide.white,
              sourceNags: <int>[],
              boardLayout: 'O*******/********/********',
            ),
            ReviewTurnBoundary(
              groupIndex: 1,
              startAtomicIndex: 1,
              endAtomicIndex: 1,
              san: 'b6',
              anchorMove: 'b6',
              side: ReviewSide.black,
              sourceNags: <int>[],
              boardLayout: 'O*******/********/@*******',
            ),
          ],
    variationCount: 0,
    userNagOverrides: const <int, int?>{},
    includeAnnotationsOnExport: false,
    createdAt: now,
    updatedAt: now,
    lastAccessedAt: now,
  );
}

class _PendingReviewAnalysisService extends ReviewAnalysisService {
  final Completer<ReviewReport> _completer = Completer<ReviewReport>();
  PrivateGameRecord? _record;
  int cancelCount = 0;

  @override
  Future<ReviewReport> analyze(
    PrivateGameRecord record, {
    ReviewProfile profile = ReviewProfile.quick,
    void Function(int completed, int total)? onProgress,
    bool ignoreCache = false,
  }) {
    _record = record;
    return _completer.future;
  }

  @override
  void cancel() {
    cancelCount++;
    final PrivateGameRecord? record = _record;
    if (!_completer.isCompleted && record != null) {
      _completer.complete(_report(record, status: ReviewStatus.cancelled));
    }
  }
}

ReviewActionEvaluation _action({
  required int index,
  required String move,
  required ReviewSide side,
  required bool human,
  required ReviewGrade grade,
}) => ReviewActionEvaluation(
  atomicIndex: index,
  groupIndex: index,
  move: move,
  side: side,
  isHumanMove: human,
  legalRootActionCount: 3,
  bestScore: 20,
  playedScore: grade == ReviewGrade.mistake ? 10 : 18,
  loss: grade == ReviewGrade.mistake ? 10 : 2,
  grade: grade,
  profile: ReviewProfile.quick,
  candidates: <ReviewCandidate>[
    const ReviewCandidate(
      rank: 1,
      move: 'd6',
      score: 20,
      depth: 24,
      line: <String>['d6', 'xf4'],
    ),
    const ReviewCandidate(
      rank: 2,
      move: 'b6',
      score: 18,
      depth: 24,
      line: <String>['b6'],
    ),
    ReviewCandidate(
      rank: 3,
      move: move,
      score: 10,
      depth: 24,
      line: <String>[move],
    ),
  ],
);
