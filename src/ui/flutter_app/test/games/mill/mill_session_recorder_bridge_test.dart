// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart' as mill;
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/mill_session_recorder_bridge.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/src/rust/frb_generated.dart';

import '../../helpers/mocks/mock_database.dart';

final File _nativeLibrary = File('../../../target/debug/rust_lib_sanmill.dll');
final String? _nativeLibrarySkipReason = _nativeLibrary.existsSync()
    ? null
    : 'Run `cargo build -p rust_lib_sanmill` before this recorder bridge test.';
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

  setUp(() {
    DB.instance = MockDB();
  });

  tearDown(() {
    DB.instance = null;
  });

  tearDownAll(() {
    if (_rustLibInitialized) {
      RustLib.dispose();
    }
  });

  group('MillSessionRecorderBridge', () {
    test(
      'converts moveApplied payload into ExtMove with mover side',
      () {
        const GameSessionEvent event = GameSessionEvent(
          MillEventTypes.moveApplied,
          payload: <String, Object?>{
            'type': MillActionTypes.place,
            'move': 'a7',
            'mover': 'first',
          },
        );

        final mill.ExtMove? move = MillSessionRecorderBridge.extMoveFromEvent(
          event,
        );

        expect(move, isNotNull);
        expect(move!.move, 'a7');
        expect(move.side, mill.PieceColor.white);
      },
      skip: _nativeLibrarySkipReason,
    );

    test('ignores non-move events and incomplete payloads', () {
      expect(
        MillSessionRecorderBridge.extMoveFromEvent(
          const GameSessionEvent(MillEventTypes.stateChanged),
        ),
        isNull,
      );
      expect(
        MillSessionRecorderBridge.extMoveFromEvent(
          const GameSessionEvent(
            MillEventTypes.moveApplied,
            payload: <String, Object?>{'move': 'a7'},
          ),
        ),
        isNull,
      );
    });

    test(
      'records moveApplied events into GameRecorder',
      () async {
        final _EventOnlySession session = _EventOnlySession();
        final mill.GameRecorder recorder = mill.GameRecorder();
        final MillSessionRecorderBridge bridge = MillSessionRecorderBridge(
          session: session,
          recorder: recorder,
        );
        addTearDown(bridge.dispose);

        session.emit(
          const GameSessionEvent(
            MillEventTypes.moveApplied,
            payload: <String, Object?>{
              'type': MillActionTypes.place,
              'move': 'a7',
              'mover': 'first',
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(recorder.mainlineMoves, hasLength(1));
        expect(recorder.mainlineMoves.single.move, 'a7');
        expect(recorder.mainlineMoves.single.side, mill.PieceColor.white);

        // Replaying the same event should follow the existing node rather than
        // creating a duplicate move.
        recorder.activeNode = recorder.pgnRoot;
        session.emit(
          const GameSessionEvent(
            MillEventTypes.moveApplied,
            payload: <String, Object?>{
              'type': MillActionTypes.place,
              'move': 'a7',
              'mover': 'first',
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(recorder.mainlineMoves, hasLength(1));
      },
      skip: _nativeLibrarySkipReason,
    );

    test(
      'undo and redo events move the recorder active node',
      () async {
        final _EventOnlySession session = _EventOnlySession();
        final mill.GameRecorder recorder = mill.GameRecorder();
        final MillSessionRecorderBridge bridge = MillSessionRecorderBridge(
          session: session,
          recorder: recorder,
        );
        addTearDown(bridge.dispose);

        recorder.appendMove(mill.ExtMove('a7', side: mill.PieceColor.white));
        recorder.appendMove(mill.ExtMove('d7', side: mill.PieceColor.black));
        expect(recorder.currentPath.map((mill.ExtMove m) => m.move), <String>[
          'a7',
          'd7',
        ]);

        session.emit(const GameSessionEvent(MillEventTypes.undoApplied));
        await Future<void>.delayed(Duration.zero);
        expect(recorder.currentPath.map((mill.ExtMove m) => m.move), <String>[
          'a7',
        ]);

        session.emit(const GameSessionEvent(MillEventTypes.redoApplied));
        await Future<void>.delayed(Duration.zero);
        expect(recorder.currentPath.map((mill.ExtMove m) => m.move), <String>[
          'a7',
          'd7',
        ]);
      },
      skip: _nativeLibrarySkipReason,
    );
  });
}

class _EventOnlySession implements GameSession {
  final StreamController<GameSessionEvent> _events =
      StreamController<GameSessionEvent>.broadcast();
  final ValueNotifier<GameStateSnapshot> _state =
      ValueNotifier<GameStateSnapshot>(
        const GameStateSnapshot(
          gameId: GameId.mill,
          activeSeat: PlayerSeat.first,
          outcome: GameOutcome.ongoing(),
        ),
      );

  void emit(GameSessionEvent event) => _events.add(event);

  @override
  Stream<GameSessionEvent> get events => _events.stream;

  @override
  List<GameAction> get legalActions => const <GameAction>[];

  @override
  GameOutcome get outcome => _state.value.outcome;

  @override
  ValueListenable<GameStateSnapshot> get state => _state;

  @override
  Future<void> apply(GameAction action) async {}

  @override
  Future<void> redo() async {}

  @override
  Future<void> undo() async {}

  @override
  void dispose() {
    _state.dispose();
    _events.close();
  }
}
