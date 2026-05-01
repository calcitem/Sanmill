// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_session.dart';
import '../../general_settings/models/general_settings.dart';
import 'native_mill_game_session.dart';

/// Minimal AI-turn adapter for the Rust-native Mill dogfood path.
///
/// This intentionally does not touch `GameController`, timers, or recording.
/// It only answers: "Is the active side controlled by AI, and if so, run the
/// native search to consume the entire AI obligation (place / move / remove
/// chain)."  `engineToGo` can layer UI side effects on top later.
class NativeMillAiTurnController {
  const NativeMillAiTurnController({
    this.depth = 1,
    this.generalSettings = const GeneralSettings(),
    this.maxStepsPerTurn = 8,
  });

  final int depth;
  final GeneralSettings generalSettings;

  /// Safety cap on how many native search-and-apply iterations are performed
  /// for a single human-triggered AI turn.  In Mill, a single AI obligation
  /// chain is at most place/move + (1..3 removes), so 8 is conservative.
  final int maxStepsPerTurn;

  PlayerSeat get aiSeat =>
      generalSettings.aiMovesFirst ? PlayerSeat.first : PlayerSeat.second;

  bool isAiTurn(NativeMillGameSession session) {
    return !session.outcome.isTerminal &&
        session.state.value.activeSeat == aiSeat;
  }

  /// Run native search-and-apply until the active seat changes away from the
  /// AI (or the game ends).  This handles mill formation correctly: after a
  /// Place that completes a mill, `state.value.activeSeat` stays on the AI
  /// side because `pending_removals[ai] > 0`, so the caller still sees an
  /// AI turn and we must keep searching for the Remove action.
  ///
  /// Returns the LAST applied action for logging / UI.  Returns null when no
  /// AI move was applied (e.g. the search aborted on the first iteration).
  Future<GameAction?> playIfAiTurn(NativeMillGameSession session) async {
    if (!isAiTurn(session)) {
      return null;
    }
    GameAction? lastApplied;
    for (int step = 0; step < maxStepsPerTurn; step++) {
      if (!isAiTurn(session)) {
        break;
      }
      final GameAction? applied = await session.searchAndApplyBestAction(
        depth: depth,
      );
      if (applied == null) {
        break;
      }
      lastApplied = applied;
    }
    return lastApplied;
  }
}
