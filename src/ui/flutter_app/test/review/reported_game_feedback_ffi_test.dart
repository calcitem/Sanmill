// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sanmill/game_page/services/analysis/move_feedback.dart';
import 'package:sanmill/review/models/review_models.dart';
import 'package:sanmill/review/services/review_analysis_service.dart';
import 'package:sanmill/review/services/review_storage.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';
import '../helpers/test_native_library.dart';

const String _reportedPgn = '''
[Event "Sanmill-Game"]
[Site "Sanmill"]
[Date "2026.7.20"]
[Round "1"]
[White "Human"]
[Black "AI"]
[Result "0-1"]
[Variant "Nine Men's Morris"]
[PlyCount "47"]

1. d2 d6 2. f4 f2 3. b4 d3 4. f6 e4 5. g4 a4 6. c4 c5
7. d7 e5 8. d5 e3xd5 9. d5 c3xd2 10. b4-b2 d3-d2
11. g4-g1 e3-d3 12. f4-g4 d3-e3xg4 13. f6-f4 e3-d3
14. d7-g7 e4-e3xf4 15. g7-g4 e3-e4 16. g4-g7 e4-e3xd5
17. g7-g4 e3-e4 18. g4-f4 d3-e3xc4 19. f4-f6 c5-c4
20. f6-f4 d2-d3xg1 0-1
''';

const String _unfinishedBoardPgn = '''
[Event "Sanmill-Game"]
[Site "Sanmill"]
[Date "2026.8.3"]
[Round "0"]
[White "AI"]
[Black "Human"]
[Result "1-0"]
[Variant "Custom"]
[PlyCount "37"]

1. d5 d6
2. d3 c5
3. f4 e4
4. b4 a4
5. d7 d2
6. d1 g7
7. g4 a1
8. a7 e3
9. e5 f2
10. b4-b2 a4-b4
11. a7-a4 c5-c4
12. d5-c5 d6-d5
13. d7-d6 b4-b6
14. b2-b4 d2-b2
15. d1-d2 a1-d1
16. a4-a1 g7-d7
17. g4-g7 d7-a7
18. g7-d7 a7-a4
19. d7-a7 1-0
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initRustLibForTests);
  tearDownAll(disposeRustLibForTests);
  setUp(() => DB.instance = MockDB());

  test(
    'reported decisive AI win keeps automatic feedback sparse',
    () async {
      final PrivateGameRecord record = PrivateGameRecord.create(
        sourcePgn: _reportedPgn,
        initialFen: null,
        result: '0-1',
        rules: const RuleSettings(),
        completedAt: DateTime.utc(2026, 7, 20),
        white: 'Human',
        black: 'AI',
        humanSides: const <ReviewSide>{ReviewSide.white},
        finalBoardLayout: null,
        moveCount: 40,
      );
      final ReviewAnalysisService service = ReviewAnalysisService.forTesting(
        ReviewStorage.forTesting(_MemoryBox()),
      );
      addTearDown(service.cancel);

      final ReviewReport report = await service.analyze(
        record,
        ignoreCache: true,
      );

      expect(report.status, ReviewStatus.complete);
      expect(report.turns, hasLength(40));
      expect(
        report.actions.expand(
          (ReviewActionEvaluation action) => action.feedbackReasons,
        ),
        isNot(contains(MoveFeedbackReason.perfectDatabase)),
        reason:
            'Heuristic fallback rows are not exact perfect-database results.',
      );

      final List<int> annotatedTurns = report.turns
          .map(
            (ReviewTurnBoundary turn) =>
                report.effectiveQualityNagForTurn(turn.groupIndex),
          )
          .whereType<int>()
          .toList(growable: false);
      final List<ReviewActionEvaluation> annotatedActions = report.actions
          .where((ReviewActionEvaluation action) => action.automaticNag != null)
          .toList(growable: false);
      final String annotationSummary = annotatedActions
          .map(
            (ReviewActionEvaluation action) =>
                '${action.groupIndex}:${action.side.name}:${action.move} '
                '${action.bestScore}/${action.playedScore} '
                'd${action.candidates.first.depth} '
                'NAG${action.automaticNag}',
          )
          .join(', ');
      expect(
        annotatedTurns.length * 10,
        lessThanOrEqualTo(report.turns.length * 2),
        reason:
            'At least 80% of this ordinary game should remain unannotated; '
            'annotations=$annotationSummary',
      );
      expect(
        annotatedActions.where(
          (ReviewActionEvaluation action) =>
              action.side == ReviewSide.black &&
              action.automaticNag == MoveFeedbackSymbol.blunder.nag,
        ),
        isEmpty,
        reason:
            'The winning side must not accumulate spurious blunders from '
            'mis-scaled fallback scores; annotations=$annotationSummary',
      );
      final ReviewActionEvaluation delayedWin = report.actions.singleWhere(
        (ReviewActionEvaluation action) =>
            action.groupIndex == 35 && action.move == 'xc4',
      );
      expect(
        delayedWin.automaticNag,
        anyOf(isNull, MoveFeedbackSymbol.dubious.nag),
        reason:
            'A time-bounded search may withhold the mark, but preserving a '
            'determined win must never be graded as a blunder.',
      );
      if (delayedWin.automaticNag != null) {
        expect(
          delayedWin.feedbackReasons,
          containsAll(<MoveFeedbackReason>[
            MoveFeedbackReason.preservesResult,
            MoveFeedbackReason.requiresPreciseFollowUp,
          ]),
        );
      }
      for (final ReviewActionEvaluation action in annotatedActions) {
        expect(
          action.feedbackReasons,
          isNotEmpty,
          reason: 'Automatic annotation for ${action.move} needs a reason.',
        );
      }
    },
    skip: nativeLibrarySkipReason() != null,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'reported 1-0 remains an ongoing board and gets a bounded outlook',
    () async {
      final PrivateGameRecord record = PrivateGameRecord.create(
        sourcePgn: _unfinishedBoardPgn,
        initialFen: null,
        result: '1-0',
        rules: const RuleSettings(),
        completedAt: DateTime.utc(2026, 8, 3),
        white: 'AI',
        black: 'Human',
        humanSides: const <ReviewSide>{ReviewSide.black},
        finalBoardLayout: null,
        moveCount: 37,
      );
      final ReviewAnalysisService service = ReviewAnalysisService.forTesting(
        ReviewStorage.forTesting(_MemoryBox()),
      );
      addTearDown(service.cancel);

      final ReviewPositionAssessment assessment = (await service
          .assessFinalPosition(record))!;

      expect(assessment.boardOutcome, ReviewBoardOutcome.ongoing);
      expect(assessment.sideToMove, ReviewSide.black);
      expect(assessment.source, ReviewPositionAssessmentSource.engine);
      expect(assessment.verdict, ReviewPositionVerdict.whiteFavored);
      expect(assessment.heuristicWhiteScore, greaterThan(3));
      expect(
        assessment.humanDatabase.state,
        ReviewHumanDatabaseState.notConfigured,
      );
    },
    skip: nativeLibrarySkipReason() != null,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

class _MemoryBox extends Fake implements Box<dynamic> {
  final Map<dynamic, dynamic> _values = <dynamic, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _values[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    _values[key] = value;
  }
}
