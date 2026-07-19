// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_action_codec.dart';
import 'package:sanmill/games/mill/widgets/mill_session_board.dart';
import 'package:sanmill/review/models/review_models.dart';
import 'package:sanmill/review/widgets/review_correction_page.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/locale_helper.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_native_library.dart';

final String? _nativeLibrarySkipReason = nativeLibrarySkipReason();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (_nativeLibrarySkipReason == null) {
      await initRustLibForTests();
    }
  });
  tearDownAll(disposeRustLibForTests);
  setUp(() => DB.instance = MockDB());

  testWidgets(
    'accepts a complete mill and removal turn from the board',
    (WidgetTester tester) async {
      final PrivateGameRecord record = _record(
        '1. a7 d7 2. a4 d6 3. a1xd7 f4 *',
      );
      final ReviewReport report = _report(
        record,
        actions: <ReviewActionEvaluation>[
          _mistake(
            atomicIndex: 5,
            groupIndex: 4,
            move: 'xd7',
            candidates: const <ReviewCandidate>[
              ReviewCandidate(
                rank: 1,
                move: 'xd6',
                score: 20,
                depth: 24,
                line: <String>['xd6'],
              ),
              ReviewCandidate(
                rank: 2,
                move: 'xd7',
                score: 8,
                depth: 24,
                line: <String>['xd7'],
              ),
            ],
          ),
        ],
        turns: const <ReviewTurnBoundary>[
          ReviewTurnBoundary(
            groupIndex: 4,
            startAtomicIndex: 4,
            endAtomicIndex: 5,
            san: 'a1xd7',
            anchorMove: 'a1',
            side: ReviewSide.white,
            sourceNags: <int>[],
            boardLayout: '********/********/********',
          ),
        ],
      );

      await _pumpCorrection(tester, record, report);

      MillSessionBoard board = tester.widget(find.byType(MillSessionBoard));
      expect(_legalMoves(board), contains('a1'));
      expect(_nodeSemantics(tester, 'a1').label, contains('Empty point'));
      expect(
        _legalMoves(board).where((String move) => move.startsWith('x')),
        isEmpty,
      );

      await _activateNode(tester, 'a1');

      expect(find.byKey(const Key('review_correction_accepted')), findsNothing);
      expect(_legalMoves(board), containsAll(<String>['xd7', 'xd6']));
      expect(_nodeSemantics(tester, 'a1').label, contains('White piece'));

      await _activateNode(tester, 'd6');

      expect(
        find.byKey(const Key('review_correction_accepted')),
        findsOneWidget,
      );
      expect(find.text('Good move!'), findsOneWidget);
      expect(find.byKey(const Key('review_correction_next')), findsOneWidget);
      board = tester.widget(find.byType(MillSessionBoard));
      expect(board.session.state.value.activeSeat, PlayerSeat.second);
      expect(board.highlightActions, <String>['a1', 'xd6']);
      expect(_nodeSemantics(tester, 'd6').label, contains('Empty point'));
      expect(
        _nodeSemantics(tester, 'd6').hasAction(SemanticsAction.tap),
        isFalse,
      );
    },
    skip: _nativeLibrarySkipReason != null,
  );

  testWidgets(
    'accepts a good alternative instead of only the top move',
    (WidgetTester tester) async {
      final PrivateGameRecord record = _record('1. a7 d7 *');
      final ReviewReport report = _singlePlacementReport(record);
      await _pumpCorrection(tester, record, report);

      await _activateNode(tester, 'b6');

      expect(
        find.byKey(const Key('review_correction_accepted')),
        findsOneWidget,
      );
      expect(find.text('Good move!'), findsOneWidget);
    },
    skip: _nativeLibrarySkipReason != null,
  );

  testWidgets(
    'supports rejection, retry, and answer without claiming success',
    (WidgetTester tester) async {
      final PrivateGameRecord record = _record('1. a7 d7 *');
      final ReviewReport report = _singlePlacementReport(record);
      await _pumpCorrection(tester, record, report);

      await _activateNode(tester, 'a7');

      expect(
        find.byKey(const Key('review_correction_rejected')),
        findsOneWidget,
      );
      expect(find.text('You can do better. Try another move.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('review_correction_retry')));
      await tester.pump();

      MillSessionBoard board = tester.widget(find.byType(MillSessionBoard));
      expect(_legalMoves(board), contains('a7'));
      expect(find.byKey(const Key('review_correction_rejected')), findsNothing);

      await tester.tap(find.byKey(const Key('review_correction_show_answer')));
      await tester.pump();

      board = tester.widget(find.byType(MillSessionBoard));
      expect(find.text('Best move: d6'), findsOneWidget);
      expect(find.text('Good move!'), findsNothing);
      expect(_legalMoves(board), isNot(contains('d6')));
      expect(board.highlightActions, <String>['d6']);
      expect(find.byKey(const Key('review_correction_next')), findsOneWidget);
    },
    skip: _nativeLibrarySkipReason != null,
  );

  testWidgets(
    'accepts a movement turn from a replayed midgame position',
    (WidgetTester tester) async {
      final PrivateGameRecord record = _record(
        '1. d6 d2 2. f4 b4 3. f6 f2 4. b6xf2 f2 '
        '5. b2 c5 6. c4 e5 7. d5 d7 8. g4 e4 9. e3 g1 '
        '10. e3-d3 e4-e3 11. c4-c3 c5-c4 12. f4-e4 f2-f4 '
        '13. d5-c5 e5-d5 14. e4-e5 e3-e4 *',
      );
      final ReviewReport report = _report(
        record,
        actions: <ReviewActionEvaluation>[
          _mistake(
            atomicIndex: 28,
            groupIndex: 27,
            move: 'e3-e4',
            side: ReviewSide.black,
            candidates: const <ReviewCandidate>[
              ReviewCandidate(
                rank: 1,
                move: 'g1-d1',
                score: 20,
                depth: 24,
                line: <String>['g1-d1'],
              ),
              ReviewCandidate(
                rank: 2,
                move: 'e3-e4',
                score: 8,
                depth: 24,
                line: <String>['e3-e4'],
              ),
            ],
          ),
        ],
        turns: const <ReviewTurnBoundary>[
          ReviewTurnBoundary(
            groupIndex: 27,
            startAtomicIndex: 28,
            endAtomicIndex: 28,
            san: 'e3-e4',
            anchorMove: 'e3-e4',
            side: ReviewSide.black,
            sourceNags: <int>[],
            boardLayout: '********/********/********',
          ),
        ],
      );
      await _pumpCorrection(tester, record, report);

      MillSessionBoard board = tester.widget(find.byType(MillSessionBoard));
      expect(_legalMoves(board), contains('g1-d1'));

      await _activateNode(tester, 'g1');
      expect(_nodeSemantics(tester, 'g1').label, contains('Black piece'));
      expect(_nodeSemantics(tester, 'g1').label, contains('Selected'));
      await _activateNode(tester, 'd1');

      board = tester.widget(find.byType(MillSessionBoard));
      expect(
        find.byKey(const Key('review_correction_accepted')),
        findsOneWidget,
      );
      expect(board.highlightActions, <String>['g1-d1']);
    },
    skip: _nativeLibrarySkipReason != null,
  );

  testWidgets(
    'skip advances progress and finishes without a timer',
    (WidgetTester tester) async {
      final PrivateGameRecord record = _record('1. a7 d7 2. a4 *');
      final ReviewReport report = _report(
        record,
        actions: <ReviewActionEvaluation>[
          _placementMistake(atomicIndex: 0, groupIndex: 0, move: 'a7'),
          _placementMistake(atomicIndex: 2, groupIndex: 2, move: 'a4'),
        ],
        turns: const <ReviewTurnBoundary>[
          ReviewTurnBoundary(
            groupIndex: 0,
            startAtomicIndex: 0,
            endAtomicIndex: 0,
            san: 'a7',
            anchorMove: 'a7',
            side: ReviewSide.white,
            sourceNags: <int>[],
            boardLayout: '********/********/********',
          ),
          ReviewTurnBoundary(
            groupIndex: 2,
            startAtomicIndex: 2,
            endAtomicIndex: 2,
            san: 'a4',
            anchorMove: 'a4',
            side: ReviewSide.white,
            sourceNags: <int>[],
            boardLayout: '********/********/********',
          ),
        ],
      );
      await _pumpCorrection(tester, record, report);

      expect(find.text('1/2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('review_correction_skip')));
      await tester.pump();
      expect(find.text('2/2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('review_correction_skip')));
      await tester.pump();
      expect(
        find.byKey(const Key('review_correction_complete')),
        findsOneWidget,
      );
      expect(find.text('Mistake review complete'), findsOneWidget);
    },
    skip: _nativeLibrarySkipReason != null,
  );

  testWidgets(
    'uses a board-and-panel layout on wide screens',
    (WidgetTester tester) async {
      final PrivateGameRecord record = _record('1. a7 d7 *');
      final ReviewReport report = _singlePlacementReport(record);
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        makeTestableWidget(
          ReviewCorrectionPage(record: record, report: report),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('review_correction_wide_layout')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('review_correction_phone_layout')),
        findsNothing,
      );
      expect(
        tester.getSize(find.byKey(const Key('review_correction_board'))).height,
        greaterThan(460),
      );
    },
    skip: _nativeLibrarySkipReason != null,
  );
}

Future<void> _pumpCorrection(
  WidgetTester tester,
  PrivateGameRecord record,
  ReviewReport report,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    makeTestableWidget(ReviewCorrectionPage(record: record, report: report)),
  );
  await tester.pump();
}

Set<String> _legalMoves(MillSessionBoard board) => board.session.legalActions
    .map(MillActionCodec.moveStringFrom)
    .whereType<String>()
    .toSet();

Future<void> _activateNode(WidgetTester tester, String notation) async {
  final Semantics semantics = tester.widget<Semantics>(
    find.byKey(Key('mill_session_board_node_$notation')),
  );
  semantics.properties.onTap!();
  await tester.pumpAndSettle();
}

SemanticsData _nodeSemantics(WidgetTester tester, String notation) => tester
    .getSemantics(find.byKey(Key('mill_session_board_node_$notation')))
    .getSemanticsData();

PrivateGameRecord _record(String sourcePgn) {
  final DateTime now = DateTime.utc(2026, 7, 19);
  return PrivateGameRecord.create(
    sourcePgn: sourcePgn,
    initialFen: null,
    result: '*',
    rules: const NineMensMorrisRuleSettings(),
    completedAt: now,
    white: 'Human',
    black: 'Computer',
    humanSides: const <ReviewSide>{ReviewSide.white},
    finalBoardLayout: null,
    moveCount: 0,
  );
}

ReviewReport _singlePlacementReport(PrivateGameRecord record) => _report(
  record,
  actions: <ReviewActionEvaluation>[
    _placementMistake(atomicIndex: 0, groupIndex: 0, move: 'a7'),
  ],
  turns: const <ReviewTurnBoundary>[
    ReviewTurnBoundary(
      groupIndex: 0,
      startAtomicIndex: 0,
      endAtomicIndex: 0,
      san: 'a7',
      anchorMove: 'a7',
      side: ReviewSide.white,
      sourceNags: <int>[],
      boardLayout: '********/********/********',
    ),
  ],
);

ReviewActionEvaluation _placementMistake({
  required int atomicIndex,
  required int groupIndex,
  required String move,
}) => _mistake(
  atomicIndex: atomicIndex,
  groupIndex: groupIndex,
  move: move,
  candidates: <ReviewCandidate>[
    const ReviewCandidate(
      rank: 1,
      move: 'd6',
      score: 20,
      depth: 24,
      line: <String>['d6'],
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
      score: 8,
      depth: 24,
      line: <String>[move],
    ),
  ],
);

ReviewActionEvaluation _mistake({
  required int atomicIndex,
  required int groupIndex,
  required String move,
  required List<ReviewCandidate> candidates,
  ReviewSide side = ReviewSide.white,
}) => ReviewActionEvaluation(
  atomicIndex: atomicIndex,
  groupIndex: groupIndex,
  move: move,
  side: side,
  isHumanMove: true,
  legalRootActionCount: candidates.length,
  bestScore: candidates.first.score,
  playedScore: 8,
  loss: 12,
  grade: ReviewGrade.mistake,
  profile: ReviewProfile.quick,
  candidates: candidates,
);

ReviewReport _report(
  PrivateGameRecord record, {
  required List<ReviewActionEvaluation> actions,
  required List<ReviewTurnBoundary> turns,
}) {
  final DateTime now = DateTime.utc(2026, 7, 19);
  return ReviewReport(
    recordId: record.id,
    pgnHash: pgnFingerprint(record.sourcePgn),
    rulesHash: record.rulesFingerprint,
    engineVersion: reviewEngineVersion,
    profile: ReviewProfile.quick,
    status: ReviewStatus.complete,
    actions: actions,
    turns: turns,
    variationCount: 0,
    userNagOverrides: const <int, int?>{},
    includeAnnotationsOnExport: false,
    createdAt: now,
    updatedAt: now,
    lastAccessedAt: now,
  );
}
