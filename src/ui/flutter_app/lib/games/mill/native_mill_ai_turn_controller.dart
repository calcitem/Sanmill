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
    this.depth,
    this.generalSettings = const GeneralSettings(),
    this.maxStepsPerTurn = 8,
  });

  /// Optional fixed depth override used by tests and targeted dogfood paths.
  ///
  /// When null, the depth is derived from [generalSettings.skillLevel] and the
  /// current session snapshot to preserve the legacy "draw on human
  /// experience" placing-phase depth table.
  final int? depth;
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

  int searchDepthForSession(NativeMillGameSession session) {
    return depth ?? searchDepthForSnapshot(session.state.value);
  }

  int searchDepthForSnapshot(GameStateSnapshot snapshot) {
    if (depth != null) {
      return depth!.clamp(1, 64).toInt();
    }
    final int level = generalSettings.skillLevel.clamp(1, 30).toInt();
    if (!generalSettings.drawOnHumanExperience || snapshot.phase != 'placing') {
      return level;
    }

    final Object? rawPayload = snapshot.payload['tgfPayload'];
    if (rawPayload is! List<int> || rawPayload.length < 28) {
      return level;
    }

    final int whiteInHand = rawPayload[24];
    final int blackInHand = rawPayload[25];
    final int whiteOnBoard = rawPayload[26];
    final int blackOnBoard = rawPayload[27];
    final int whiteTotal = whiteInHand + whiteOnBoard;
    final int blackTotal = blackInHand + blackOnBoard;
    final int pieceCount = (whiteTotal > blackTotal ? whiteTotal : blackTotal)
        .clamp(0, 12)
        .toInt();
    final int index = (pieceCount * 2 - whiteInHand - blackInHand)
        .clamp(0, 24)
        .toInt();

    final List<int> table = pieceCount == 12
        ? _placingDepthTable12
        : _placingDepthTable9;
    final int tableDepth = table[index];
    if (tableDepth <= 0) {
      return level;
    }
    return level > tableDepth ? tableDepth : level;
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
        depth: searchDepthForSession(session),
      );
      if (applied == null) {
        break;
      }
      lastApplied = applied;
    }
    return lastApplied;
  }
}

// Matches legacy `Mills::get_search_depth` for non-developer placing phase
// when "DrawOnHumanExperience" is enabled.
const List<int> _placingDepthTable9 = <int>[
  1, 1, 1, 1, // 0 ~ 3
  3, 3, 3, 15, // 4 ~ 7
  15, 5, 18, 0, // 8 ~ 11
  0, 0, 0, 0, // 12 ~ 15
  0, 0, 0, 0, // 16 ~ 19
  0, 0, 0, 0, // 20 ~ 23
  0, // 24
];

const List<int> _placingDepthTable12 = <int>[
  1, 2, 2, 4, // 0 ~ 3
  4, 12, 12, 18, // 4 ~ 7
  12, 0, 0, 0, // 8 ~ 11
  0, 0, 0, 0, // 12 ~ 15
  0, 0, 0, 0, // 16 ~ 19
  0, 0, 0, 0, // 20 ~ 23
  0, // 24
];
