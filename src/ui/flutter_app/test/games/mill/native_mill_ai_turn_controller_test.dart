// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
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
  });
}
