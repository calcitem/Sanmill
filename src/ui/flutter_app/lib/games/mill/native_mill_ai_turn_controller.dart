// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_session.dart';
import '../../general_settings/models/general_settings.dart';
import 'native_mill_game_session.dart';

/// Minimal AI-turn adapter for the Rust-native Mill dogfood path.
///
/// This intentionally does not touch `GameController`, timers, or recording.
/// It only answers: "Is the active side controlled by AI, and if so, can the
/// native search produce and apply one legal action?"  `engineToGo` can layer
/// UI side effects on top later.
class NativeMillAiTurnController {
  const NativeMillAiTurnController({
    this.depth = 1,
    this.generalSettings = const GeneralSettings(),
  });

  final int depth;
  final GeneralSettings generalSettings;

  PlayerSeat get aiSeat =>
      generalSettings.aiMovesFirst ? PlayerSeat.first : PlayerSeat.second;

  bool isAiTurn(NativeMillGameSession session) {
    return !session.outcome.isTerminal &&
        session.state.value.activeSeat == aiSeat;
  }

  Future<GameAction?> playIfAiTurn(NativeMillGameSession session) {
    if (!isAiTurn(session)) {
      return Future<GameAction?>.value();
    }
    return session.searchAndApplyBestAction(depth: depth);
  }
}
