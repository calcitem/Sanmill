// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sanmill/game_page/services/analysis/move_feedback.dart';
import 'package:sanmill/game_page/services/analysis/move_feedback_analysis_controller.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/native_mill_ai_turn_controller.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/review/models/review_models.dart';
import 'package:sanmill/review/services/review_analysis_service.dart';
import 'package:sanmill/review/services/review_storage.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../../helpers/mocks/mock_database.dart';
import '../../helpers/test_native_library.dart';

const GeneralSettings _deterministicAiSettings = GeneralSettings(
  moveTime: 0,
  shufflingEnabled: false,
);

const RuleSettings _boundedSelfPlayRules = RuleSettings(
  nMoveRule: 20,
  endgameNMoveRule: 20,
);

const List<String> _masterSkill1FullGame = <String>[
  'd6',
  'f4',
  'd2',
  'b4',
  'e4',
  'd5',
  'c4',
  'd3',
  'g4',
  'd7',
  'a4',
  'd1',
  'e5',
  'e3',
  'c3',
  'c5',
  'f6',
  'b6',
  'a4-a7',
  'b4-a4',
  'c4-b4',
  'c5-c4',
  'g4-g1',
  'd7-g7',
  'g1-g4',
  'g7-d7',
  'g4-g1',
  'd7-g7',
  'g1-g4',
  'g7-d7',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initRustLibForTests);
  tearDownAll(disposeRustLibForTests);
  setUp(() => DB.instance = MockDB());

  group('Native Mill AI vs AI self-play FFI', () {
    test(
      'matches master parity and keeps analysis and review feedback sparse',
      () async {
        final NativeMillGameSession session = NativeMillGameSession(
          rules: _boundedSelfPlayRules,
          generalSettings: _deterministicAiSettings,
        );
        addTearDown(session.dispose);

        final List<String> moves = <String>[];
        final GameRecorder recorder = GameRecorder(
          recordedRuleSettings: _boundedSelfPlayRules,
        );
        final List<PgnNode<ExtMove>> recordedNodes = <PgnNode<ExtMove>>[];
        final StreamSubscription<GameSessionEvent> subscription = session.events
            .listen((GameSessionEvent event) {
              if (event.type == MillEventTypes.moveApplied) {
                final Object? move = event.payload['move'];
                final Object? mover = event.payload['mover'];
                assert(move is String, 'moveApplied event must carry a move.');
                assert(
                  mover == PlayerSeat.first.name ||
                      mover == PlayerSeat.second.name,
                  'moveApplied event must identify the mover.',
                );
                final String moveString = move! as String;
                moves.add(moveString);
                recorder.appendMove(
                  ExtMove(
                    moveString,
                    side: mover == PlayerSeat.first.name
                        ? PieceColor.white
                        : PieceColor.black,
                  ),
                );
                recordedNodes.add(recorder.activeNode!);
              }
            });
        addTearDown(subscription.cancel);

        const NativeMillAiTurnController ai = NativeMillAiTurnController(
          generalSettings: _deterministicAiSettings,
          bothSidesAi: true,
        );

        for (int ply = 0; ply < 400 && !session.outcome.isTerminal; ply++) {
          final GameAction? applied = await ai.playIfAiTurn(session);
          await Future<void>.delayed(Duration.zero);
          expect(
            applied,
            isNotNull,
            reason:
                'AI self-play stalled before a terminal outcome at ply $ply.',
          );
        }

        expect(
          session.outcome.isTerminal,
          isTrue,
          reason: 'AI self-play must finish under the bounded N-move rule.',
        );
        expect(moves, _masterSkill1FullGame);

        final List<PgnNode<ExtMove>> completeTurnNodes = <PgnNode<ExtMove>>[
          for (int index = 0; index < recordedNodes.length; index++)
            if (index == recordedNodes.length - 1 ||
                recordedNodes[index + 1].data!.side !=
                    recordedNodes[index].data!.side)
              recordedNodes[index],
        ];
        final MoveFeedbackAnalysisController feedbackController =
            MoveFeedbackAnalysisController();
        addTearDown(feedbackController.dispose);
        final List<MoveFeedbackResult> feedback = <MoveFeedbackResult>[];
        for (final PgnNode<ExtMove> node in completeTurnNodes) {
          await feedbackController.analyze(
            recorder: recorder,
            selectedNode: node,
            rules: _boundedSelfPlayRules,
            generalSettings: _deterministicAiSettings,
          );
          expect(
            feedbackController.state.status,
            MoveFeedbackAnalysisStatus.ready,
            reason:
                'Feedback analysis failed for ${node.data!.move}: '
                '${feedbackController.state.error}',
          );
          feedback.add(feedbackController.state.result!);
        }

        final int unannotated = feedback
            .where(
              (MoveFeedbackResult result) =>
                  result.symbol == MoveFeedbackSymbol.none,
            )
            .length;
        final Map<MoveFeedbackSymbol, int> distribution =
            <MoveFeedbackSymbol, int>{
              for (final MoveFeedbackSymbol symbol in MoveFeedbackSymbol.values)
                symbol: feedback
                    .where(
                      (MoveFeedbackResult result) => result.symbol == symbol,
                    )
                    .length,
            };
        expect(feedback.length, greaterThanOrEqualTo(20));
        expect(
          distribution[MoveFeedbackSymbol.brilliant]! +
              distribution[MoveFeedbackSymbol.good]! +
              distribution[MoveFeedbackSymbol.interesting]!,
          0,
          reason:
              'Phase 1 automatic feedback never invents positive glyphs; '
              'distribution=$distribution',
        );
        expect(
          unannotated * 10,
          greaterThanOrEqualTo(feedback.length * 8),
          reason:
              'Ordinary AI self-play should be at least 80% unannotated; '
              'distribution=$distribution',
        );

        final PrivateGameRecord record = PrivateGameRecord.create(
          sourcePgn: recorder.moveHistoryTextWithoutVariations,
          initialFen: null,
          result: '*',
          rules: _boundedSelfPlayRules,
          completedAt: DateTime.utc(2026, 7, 20),
          white: 'AI 1',
          black: 'AI 2',
          humanSides: const <ReviewSide>{},
          finalBoardLayout: session.getFen().split(RegExp(r'\s+')).first,
          moveCount: completeTurnNodes.length,
        );
        final ReviewAnalysisService reviewService =
            ReviewAnalysisService.forTesting(
              ReviewStorage.forTesting(_MemoryBox()),
            );
        addTearDown(reviewService.cancel);
        final ReviewReport review = await reviewService.analyze(
          record,
          ignoreCache: true,
        );
        final List<int> reviewNags = review.turns
            .map(
              (ReviewTurnBoundary turn) =>
                  review.effectiveQualityNagForTurn(turn.groupIndex),
            )
            .whereType<int>()
            .toList(growable: false);
        final Map<int, int> reviewDistribution = <int, int>{
          for (final int nag in <int>[1, 2, 3, 4, 5, 6])
            nag: reviewNags.where((int value) => value == nag).length,
        };
        expect(review.engineVersion, startsWith('$reviewEngineVersion:'));
        expect(
          reviewDistribution[1]! +
              reviewDistribution[3]! +
              reviewDistribution[5]!,
          0,
          reason:
              'Phase 1 automatic review never invents positive NAGs; '
              'distribution=$reviewDistribution',
        );
        expect(
          reviewNags.length * 10,
          lessThanOrEqualTo(review.turns.length * 2),
          reason:
              'Ordinary AI self-play review should be at least 80% '
              'unannotated; distribution=$reviewDistribution',
        );
        expect(
          review.actions.expand(
            (ReviewActionEvaluation action) => action.feedbackReasons,
          ),
          isNot(contains(MoveFeedbackReason.perfectDatabase)),
          reason:
              'A shallow fallback analysis must not masquerade as exact '
              'perfect-database evidence.',
        );
        for (final ReviewActionEvaluation action in review.actions.where(
          (ReviewActionEvaluation value) => value.automaticNag != null,
        )) {
          expect(
            action.feedbackReasons,
            isNotEmpty,
            reason:
                'Every automatic review annotation must explain '
                '${action.move}.',
          );
        }
      },
      skip: nativeLibrarySkipReason() != null,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
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
