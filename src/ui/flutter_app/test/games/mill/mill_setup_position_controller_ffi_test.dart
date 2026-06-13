// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_setup_position_controller.dart';
import 'package:sanmill/games/mill/mill_types.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_snapshot_board_view.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/src/rust/frb_generated.dart';

final File _nativeLibrary = File('../../../target/debug/rust_lib_sanmill.dll');
final String? _nativeLibrarySkipReason = _nativeLibrary.existsSync()
    ? null
    : 'Run `cargo build -p rust_lib_sanmill` before this FFI smoke test.';
bool _rustLibInitialized = false;

MillSetupPositionController _newController(NativeMillGameSession session) {
  return MillSetupPositionController(
    session: session,
    ruleSettings: const RuleSettings(),
  )..initFromSession();
}

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

  group('MillSetupPositionController FEN board mapping', () {
    test(
      'painting a white piece at every node round-trips to the same node',
      () {
        // The controller serialises its local board model to a Mill FEN and
        // pushes it through the Rust kernel.  Placing a single piece at each
        // node and reading it back through the native snapshot proves the
        // Dart node -> FEN-slot mapping is the exact inverse of the kernel's
        // FEN parser for all 24 points (a wrong mapping would surface the
        // piece at a different node).
        for (int node = 0; node < 24; node++) {
          final NativeMillGameSession session = NativeMillGameSession();
          final MillSetupPositionController controller = _newController(
            session,
          );

          controller.clear();
          controller.setPaintColor(PieceColor.white);
          controller.tapNode(node);

          final NativeMillSnapshotBoardView view =
              NativeMillSnapshotBoardView.fromSnapshot(session.state.value)!;
          expect(
            view.occupiedNodes().keys.toSet(),
            <int>{node},
            reason: 'white at node $node must be the only occupied point',
          );
          expect(view.pieceAtNode(node), PlayerSeat.first);

          session.dispose();
        }
      },
      skip: _nativeLibrarySkipReason,
    );

    test(
      'white and black placements keep their colours after the FEN round-trip',
      () {
        final NativeMillGameSession session = NativeMillGameSession();
        addTearDown(session.dispose);
        final MillSetupPositionController controller = _newController(session);

        controller.clear();
        const List<int> whiteNodes = <int>[0, 2, 4];
        const List<int> blackNodes = <int>[1, 9, 17];

        controller.setPaintColor(PieceColor.white);
        whiteNodes.forEach(controller.tapNode);
        controller.setPaintColor(PieceColor.black);
        blackNodes.forEach(controller.tapNode);

        final NativeMillSnapshotBoardView view =
            NativeMillSnapshotBoardView.fromSnapshot(session.state.value)!;
        expect(view.occupiedNodes().keys.toSet(), <int>{
          ...whiteNodes,
          ...blackNodes,
        });
        for (final int node in whiteNodes) {
          expect(
            view.pieceAtNode(node),
            PlayerSeat.first,
            reason: 'node $node',
          );
        }
        for (final int node in blackNodes) {
          expect(
            view.pieceAtNode(node),
            PlayerSeat.second,
            reason: 'node $node',
          );
        }
      },
      skip: _nativeLibrarySkipReason,
    );

    test(
      'exportFen then pasteFen into a fresh session preserves the board',
      () {
        final NativeMillGameSession source = NativeMillGameSession();
        addTearDown(source.dispose);
        final MillSetupPositionController sourceController = _newController(
          source,
        );

        sourceController.clear();
        sourceController.setPaintColor(PieceColor.white);
        <int>[3, 11, 19].forEach(sourceController.tapNode);
        sourceController.setPaintColor(PieceColor.black);
        <int>[5, 13, 21].forEach(sourceController.tapNode);
        // Moving phase exercises the in-hand=0 branch of the FEN builder.
        sourceController.setPhase(Phase.moving);

        final String exported = sourceController.exportFen();
        final NativeMillSnapshotBoardView sourceView =
            NativeMillSnapshotBoardView.fromSnapshot(source.state.value)!;

        final NativeMillGameSession target = NativeMillGameSession();
        addTearDown(target.dispose);
        final MillSetupPositionController targetController = _newController(
          target,
        );
        expect(targetController.pasteFen(exported), isTrue);

        final NativeMillSnapshotBoardView targetView =
            NativeMillSnapshotBoardView.fromSnapshot(target.state.value)!;
        expect(
          targetView.occupiedNodes().keys.toSet(),
          sourceView.occupiedNodes().keys.toSet(),
        );
        for (final int node in sourceView.occupiedNodes().keys) {
          expect(
            targetView.pieceAtNode(node),
            sourceView.pieceAtNode(node),
            reason: 'node $node colour must survive export/paste',
          );
        }
        expect(target.state.value.phase, 'moving');
      },
      skip: _nativeLibrarySkipReason,
    );

    test('clearing the board removes every piece', () {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);
      final MillSetupPositionController controller = _newController(session);

      controller.setPaintColor(PieceColor.white);
      controller.tapNode(0);
      controller.tapNode(8);
      controller.clear();

      final NativeMillSnapshotBoardView view =
          NativeMillSnapshotBoardView.fromSnapshot(session.state.value)!;
      expect(view.occupiedNodes(), isEmpty);
    }, skip: _nativeLibrarySkipReason);
  });
}
