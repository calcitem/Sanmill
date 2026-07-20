// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/analysis/move_feedback.dart';
import 'package:sanmill/game_page/services/analysis/move_feedback_analysis_controller.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/native_mill_ai_turn_controller.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';

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

  group('Native Mill AI vs AI self-play FFI', () {
    test(
      'matches master parity and keeps analyzed feedback sparse',
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
          distribution[MoveFeedbackSymbol.brilliant],
          0,
          reason:
              'The ordinary 200 ms analysis path has no supplemental '
              'brilliant-move verification; distribution=$distribution',
        );
        expect(
          unannotated * 10,
          greaterThanOrEqualTo(feedback.length * 7),
          reason:
              'Ordinary AI self-play should be at least 70% unannotated; '
              'distribution=$distribution',
        );
      },
      skip: nativeLibrarySkipReason() != null,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
