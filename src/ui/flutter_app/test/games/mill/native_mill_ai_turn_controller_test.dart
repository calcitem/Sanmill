// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/native_mill_ai_turn_controller.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';

void main() {
  group('NativeMillAiTurnController', () {
    test('maps aiMovesFirst to first-player AI seat', () {
      const NativeMillAiTurnController controller = NativeMillAiTurnController(
        generalSettings: GeneralSettings(aiMovesFirst: true),
      );

      expect(controller.aiSeat, PlayerSeat.first);
    });

    test('maps default AI side to second player', () {
      const NativeMillAiTurnController controller =
          NativeMillAiTurnController();

      expect(controller.aiSeat, PlayerSeat.second);
    });

    test('uses fixed depth override when provided', () {
      const NativeMillAiTurnController controller = NativeMillAiTurnController(
        depth: 4,
        generalSettings: GeneralSettings(skillLevel: 30),
      );

      expect(controller.searchDepthForSnapshot(_placingSnapshot()), 4);
    });

    test('uses human-experience placing depth table when enabled', () {
      const NativeMillAiTurnController controller = NativeMillAiTurnController(
        generalSettings: GeneralSettings(
          skillLevel: 30,
          drawOnHumanExperience: true,
        ),
      );

      // 9MM placing index 4 maps to depth 3 in master Mills::get_search_depth.
      expect(
        controller.searchDepthForSnapshot(
          _placingSnapshot(
            whiteInHand: 7,
            blackInHand: 7,
            whiteOnBoard: 2,
            blackOnBoard: 2,
          ),
        ),
        3,
      );
    });

    test(
      'falls back to skill level outside human-experience placing table',
      () {
        const NativeMillAiTurnController controller =
            NativeMillAiTurnController(
              generalSettings: GeneralSettings(
                skillLevel: 6,
                drawOnHumanExperience: false,
              ),
            );

        expect(controller.searchDepthForSnapshot(_placingSnapshot()), 6);
        expect(controller.searchDepthForSnapshot(_movingSnapshot()), 6);
      },
    );
  });
}

GameStateSnapshot _placingSnapshot({
  int whiteInHand = 9,
  int blackInHand = 9,
  int whiteOnBoard = 0,
  int blackOnBoard = 0,
}) {
  final Uint8List payload = Uint8List(256);
  payload[24] = whiteInHand;
  payload[25] = blackInHand;
  payload[26] = whiteOnBoard;
  payload[27] = blackOnBoard;
  return GameStateSnapshot(
    gameId: GameId.mill,
    activeSeat: PlayerSeat.first,
    outcome: const GameOutcome.ongoing(),
    phase: 'placing',
    payload: <String, Object?>{'tgfPayload': payload},
  );
}

GameStateSnapshot _movingSnapshot() {
  final Uint8List payload = Uint8List(256);
  payload[24] = 0;
  payload[25] = 0;
  payload[26] = 9;
  payload[27] = 9;
  return GameStateSnapshot(
    gameId: GameId.mill,
    activeSeat: PlayerSeat.first,
    outcome: const GameOutcome.ongoing(),
    phase: 'moving',
    payload: <String, Object?>{'tgfPayload': payload},
  );
}
