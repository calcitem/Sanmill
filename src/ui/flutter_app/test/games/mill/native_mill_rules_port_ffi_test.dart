// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/native_mill_rules_port.dart';
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

        expect(afterApply.lastAction, firstPlace);
        expect(afterApply.activeSeat, PlayerSeat.second);
        expect(port.snapshot, afterApply);

        final GameStateSnapshot afterUndo = port.undo();
        expect(afterUndo.activeSeat, PlayerSeat.first);
        expect(afterUndo.lastAction, isNull);
        expect(port.snapshot, afterUndo);

        final GameStateSnapshot afterRedo = port.redo();
        expect(afterRedo.activeSeat, PlayerSeat.second);
        expect(port.snapshot, afterRedo);
      },
      skip: _nativeLibrarySkipReason,
    );
  });
}
