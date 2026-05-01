// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart' as platform;
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  test('GameController stores active session snapshots', () {
    DB.instance = MockDB();
    addTearDown(() => DB.instance = null);
    final GameController controller = GameController.instance;
    addTearDown(() => controller.activeSessionSnapshot = null);

    const platform.GameStateSnapshot snapshot = platform.GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: platform.PlayerSeat.first,
      outcome: platform.GameOutcome.ongoing(),
      phase: 'placing',
    );

    controller.activeSessionSnapshot = snapshot;

    expect(controller.activeSessionSnapshot, same(snapshot));
    expect(controller.activeSessionSnapshotNotifier.value, same(snapshot));
  });

  test('GameController exposes active native Mill board view', () {
    DB.instance = MockDB();
    addTearDown(() => DB.instance = null);
    final GameController controller = GameController.instance;
    addTearDown(() => controller.activeSessionSnapshot = null);

    final Uint8List payload = Uint8List(256)..[0] = 1;
    final platform.GameStateSnapshot snapshot = platform.GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: platform.PlayerSeat.first,
      outcome: const platform.GameOutcome.ongoing(),
      phase: 'placing',
      payload: <String, Object?>{'tgfPayload': payload},
    );

    controller.activeSessionSnapshot = snapshot;

    expect(
      controller.activeNativeMillBoardView?.pieceAtNode(0),
      platform.PlayerSeat.first,
    );
  });
}
