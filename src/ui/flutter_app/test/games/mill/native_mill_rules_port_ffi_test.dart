// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart' as mill;
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_action_codec.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/mill_session_recorder_bridge.dart';
import 'package:sanmill/games/mill/mill_tap_action_selector.dart';
import 'package:sanmill/games/mill/native_mill_ai_turn_controller.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_rules_port.dart';
import 'package:sanmill/games/mill/native_mill_snapshot_board_view.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/src/rust/api/simple.dart' as tgf;
import 'package:sanmill/src/rust/frb_generated.dart';

final File _nativeLibrary = File('../../../target/debug/rust_lib_sanmill.dll');
final String? _nativeLibrarySkipReason = _nativeLibrary.existsSync()
    ? null
    : 'Run `cargo build -p rust_lib_sanmill` before this FFI smoke test.';
bool _rustLibInitialized = false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (_nativeLibrarySkipReason != null) {
      return;
    }
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(_nativeLibrary.absolute.path),
    );
    _rustLibInitialized = true;
  });

  tearDownAll(() {
    if (_rustLibInitialized) {
      RustLib.dispose();
    }
  });

  group('NativeMillRulesPort FFI smoke', () {
    test(
      'initial state exposes 24 legal Mill placements',
      () {
        final NativeMillRulesPort port = NativeMillRulesPort();
        addTearDown(port.dispose);

        expect(port.snapshot.gameId, GameId.mill);
        expect(port.snapshot.activeSeat, PlayerSeat.first);
        expect(port.snapshot.phase, 'placing');
        expect(port.snapshot.outcome.isTerminal, isFalse);
        expect(port.legalActions, hasLength(24));
        expect(
          port.legalActions.every(
            (GameAction a) => a.type == MillActionTypes.place,
          ),
          isTrue,
        );
      },
      skip: _nativeLibrarySkipReason,
    );

    test(
      'apply, undo, and redo keep snapshots synchronized',
      () {
        final NativeMillRulesPort port = NativeMillRulesPort();
        addTearDown(port.dispose);

        final GameAction firstPlace = port.legalActions.first;
        final GameStateSnapshot afterApply = port.apply(firstPlace);

        expect(port.undoDepth, 1);
        expect(port.redoDepth, 0);
        expect(afterApply.lastAction, firstPlace);
        expect(afterApply.activeSeat, PlayerSeat.second);
        expect(port.snapshot, afterApply);
        final NativeMillSnapshotBoardView boardAfterApply =
            NativeMillSnapshotBoardView.fromSnapshot(afterApply)!;
        expect(
          boardAfterApply.pieceAtNode(firstPlace.payload['toNode']! as int),
          PlayerSeat.first,
        );

        final GameStateSnapshot afterUndo = port.undo();
        expect(port.undoDepth, 0);
        expect(port.redoDepth, 1);
        expect(afterUndo.activeSeat, PlayerSeat.first);
        expect(afterUndo.lastAction, isNull);
        expect(port.snapshot, afterUndo);
        expect(
          NativeMillSnapshotBoardView.fromSnapshot(afterUndo)!.occupiedNodes(),
          isEmpty,
        );

        final GameStateSnapshot afterRedo = port.redo();
        expect(port.undoDepth, 1);
        expect(port.redoDepth, 0);
        expect(afterRedo.activeSeat, PlayerSeat.second);
        expect(port.snapshot, afterRedo);
      },
      skip: _nativeLibrarySkipReason,
    );

    test(
      'NativeMillGameSession applies through the real rules port',
      () async {
        final NativeMillGameSession session = NativeMillGameSession();
        addTearDown(session.dispose);

        expect(session.legalActions, hasLength(24));
        final GameAction firstPlace = session.legalActions.first;

        await session.apply(firstPlace);
        expect(session.state.value.lastAction, firstPlace);
        expect(session.state.value.activeSeat, PlayerSeat.second);

        await session.undo();
        expect(session.state.value.activeSeat, PlayerSeat.first);

        await session.redo();
        expect(session.state.value.activeSeat, PlayerSeat.second);
      },
      skip: _nativeLibrarySkipReason,
    );

    test(
      'setup APIs clear, place, set side, and finish natively',
      () {
        final NativeMillGameSession session = NativeMillGameSession();
        addTearDown(session.dispose);

        session.setupClear();
        expect(
          NativeMillSnapshotBoardView.fromSnapshot(
            session.state.value,
          )!.occupiedNodes(),
          isEmpty,
        );

        session.setupSetPiece(0, 1);
        session.setupSetPiece(6, 2);
        session.setupSetSide(1);

        final NativeMillSnapshotBoardView editedBoard =
            NativeMillSnapshotBoardView.fromSnapshot(session.state.value)!;
        expect(editedBoard.pieceAtNode(0), PlayerSeat.first);
        expect(editedBoard.pieceAtNode(6), PlayerSeat.second);
        expect(session.state.value.activeSeat, PlayerSeat.second);

        session.setupFinish();
        expect(session.state.value.phase, 'placing');
        expect(session.state.value.activeSeat, PlayerSeat.second);
        expect(session.undoDepth, 0);
        expect(session.redoDepth, 0);
        expect(session.legalActions, isNotEmpty);
      },
      skip: _nativeLibrarySkipReason,
    );

    test(
      'search events run from the session kernel state',
      () async {
        final NativeMillGameSession session = NativeMillGameSession();
        addTearDown(session.dispose);

        // Advance away from the initial position so the search proves it is
        // tied to this session's kernel handle, not the global simple API.
        final GameAction firstPlace = session.legalActions.first;
        await session.apply(firstPlace);

        final List<String> kinds = <String>[];
        GameAction? bestAction;
        await for (final tgf.EngineEvent event in session.millSearchEvents(
          depth: 1,
        )) {
          kinds.add(event.kind);
          if (event.kind == 'bestMove' && event.toNode >= 0) {
            bestAction = session.legalActions.firstWhere(
              (GameAction action) => action.payload['toNode'] == event.toNode,
            );
          }
        }

        expect(
          kinds,
          containsAllInOrder(<String>['ready', 'info', 'bestMove']),
        );
        expect(bestAction, isNotNull);
        expect(bestAction!.type, MillActionTypes.place);
      },
      skip: _nativeLibrarySkipReason,
    );

    test(
      'searchAndApplyBestAction applies the searched move',
      () async {
        final NativeMillGameSession session = NativeMillGameSession();
        addTearDown(session.dispose);

        expect(session.state.value.activeSeat, PlayerSeat.first);
        final GameAction? action = await session.searchAndApplyBestAction();

        expect(action, isNotNull);
        expect(action!.type, MillActionTypes.place);
        expect(session.state.value.lastAction, same(action));
        expect(session.state.value.activeSeat, PlayerSeat.second);
        expect(
          NativeMillSnapshotBoardView.fromSnapshot(
            session.state.value,
          )!.pieceAtNode(action.payload['toNode']! as int),
          PlayerSeat.first,
        );
      },
      skip: _nativeLibrarySkipReason,
    );

    test(
      'NativeMillAiTurnController plays only on the configured AI seat',
      () async {
        final NativeMillGameSession session = NativeMillGameSession();
        addTearDown(session.dispose);

        const NativeMillAiTurnController blackAi = NativeMillAiTurnController();
        expect(blackAi.aiSeat, PlayerSeat.second);
        expect(blackAi.isAiTurn(session), isFalse);
        expect(await blackAi.playIfAiTurn(session), isNull);
        expect(session.state.value.activeSeat, PlayerSeat.first);

        final GameAction firstPlace = session.legalActions.first;
        await session.apply(firstPlace);
        expect(session.state.value.activeSeat, PlayerSeat.second);
        expect(blackAi.isAiTurn(session), isTrue);

        final GameAction? blackMove = await blackAi.playIfAiTurn(session);
        expect(blackMove, isNotNull);
        expect(blackMove!.type, MillActionTypes.place);
        expect(session.state.value.activeSeat, PlayerSeat.first);

        final NativeMillGameSession firstAiSession = NativeMillGameSession();
        addTearDown(firstAiSession.dispose);
        const NativeMillAiTurnController whiteAi = NativeMillAiTurnController(
          generalSettings: GeneralSettings(aiMovesFirst: true),
        );
        expect(whiteAi.isAiTurn(firstAiSession), isTrue);
        final GameAction? whiteMove = await whiteAi.playIfAiTurn(
          firstAiSession,
        );
        expect(whiteMove, isNotNull);
        expect(firstAiSession.state.value.activeSeat, PlayerSeat.second);
      },
      skip: _nativeLibrarySkipReason,
    );

    test(
      'mill formation in placing phase exposes remove actions to human player',
      () async {
        // Replicates the exact bug scenario:
        //   1. d2 d6   (White node 13, Black node 9)
        //   2. f4 b4   (White node 11, Black node 15)
        //   3. f2 g4   (White node 12, Black node 3)
        //   4. f6      (White node 10) → forms mill [10,11,12]
        //
        // After White forms the mill, session.legalActions must contain
        // remove actions for all Black pieces, and MillTapActionSelector
        // must find "xd6" (node 9) when the human taps d6.
        final NativeMillGameSession session = NativeMillGameSession();
        addTearDown(session.dispose);

        final List<String> placeOrder = <String>[
          'd2',
          'd6',
          'f4',
          'b4',
          'f2',
          'g4',
          'f6',
        ];

        for (final String moveStr in placeOrder) {
          final GameAction? action = session.legalActions
              .cast<GameAction?>()
              .firstWhere(
                (GameAction? a) =>
                    a != null &&
                    a.type == MillActionTypes.place &&
                    MillActionCodec.moveStringFrom(a)?.toLowerCase() == moveStr,
                orElse: () => null,
              );
          expect(
            action,
            isNotNull,
            reason: 'Could not find place action for $moveStr',
          );
          await session.apply(action!);
        }

        // After White places f6 (forming mill f2-f4-f6), it is still White's
        // turn because White must remove one of Black's pieces.
        expect(
          session.state.value.activeSeat,
          PlayerSeat.first,
          reason: 'White keeps turn after forming a mill',
        );

        final List<GameAction> legal = session.legalActions;
        expect(
          legal,
          isNotEmpty,
          reason: 'Legal actions must not be empty after forming a mill',
        );

        // All actions should be Remove actions.
        expect(
          legal.every((GameAction a) => a.type == MillActionTypes.remove),
          isTrue,
          reason: 'All legal actions must be Remove after forming a mill',
        );

        // Specifically, removing d6 (Black's piece at node 9) must be legal.
        final GameAction? removeD6 = legal.cast<GameAction?>().firstWhere(
          (GameAction? a) =>
              a != null &&
              MillActionCodec.moveStringFrom(a)?.toLowerCase() == 'xd6',
          orElse: () => null,
        );
        expect(
          removeD6,
          isNotNull,
          reason: 'xd6 must be a legal remove target after White forms a mill',
        );

        // Simulate what the tap handler does: MillTapActionSelector.select
        // should find the remove action for d6.
        final MillTapActionSelection selection = MillTapActionSelector.select(
          legalActions: legal,
          tappedLabel: 'd6',
        );
        expect(
          selection.action,
          isNotNull,
          reason: 'Tapping d6 must resolve to a Remove action',
        );
        expect(selection.action!.type, MillActionTypes.remove);
        expect(MillActionCodec.moveStringFrom(selection.action!), 'xd6');
      },
      skip: _nativeLibrarySkipReason,
    );

    test(
      'recorder bridge follows real session apply undo redo events',
      () async {
        final NativeMillGameSession session = NativeMillGameSession();
        addTearDown(session.dispose);
        final mill.GameRecorder recorder = mill.GameRecorder();
        final MillSessionRecorderBridge bridge = MillSessionRecorderBridge(
          session: session,
          recorder: recorder,
        );
        addTearDown(bridge.dispose);

        final GameAction firstPlace = session.legalActions.first;
        await session.apply(firstPlace);
        await Future<void>.delayed(Duration.zero);
        expect(recorder.currentPath.map((mill.ExtMove m) => m.move), <String>[
          firstPlace.payload['move']! as String,
        ]);
        expect(recorder.currentPath.single.side, mill.PieceColor.white);

        final GameAction? secondPlace = await session
            .searchAndApplyBestAction();
        await Future<void>.delayed(Duration.zero);
        expect(secondPlace, isNotNull);
        final GameAction second = secondPlace!;
        expect(recorder.currentPath.map((mill.ExtMove m) => m.move), <String>[
          firstPlace.payload['move']! as String,
          second.payload['move']! as String,
        ]);
        expect(recorder.currentPath.last.side, mill.PieceColor.black);

        await session.undo();
        await Future<void>.delayed(Duration.zero);
        expect(recorder.currentPath.map((mill.ExtMove m) => m.move), <String>[
          firstPlace.payload['move']! as String,
        ]);

        await session.redo();
        await Future<void>.delayed(Duration.zero);
        expect(recorder.currentPath.map((mill.ExtMove m) => m.move), <String>[
          firstPlace.payload['move']! as String,
          second.payload['move']! as String,
        ]);
      },
      skip: _nativeLibrarySkipReason,
    );
  });
}
