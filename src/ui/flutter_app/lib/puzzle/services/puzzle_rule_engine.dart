// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_rule_engine.dart
//
// Headless Mill rule engine for the puzzle subsystem.
//
// The puzzle feature needs to parse FENs, replay move sequences and read
// the resulting board state (side to move, winner, piece counts, pending
// removal, occupancy) WITHOUT touching the live game session.  Historically
// this was done by spinning up a throwaway legacy Dart `Position` rule
// machine; that machine was deleted with the rule-machine cleanup.
//
// This adapter is the single, well-documented seam between the puzzle code
// and the Rust-native rule kernel (`NativeMillRulesPort`).  Every puzzle
// file that used to instantiate `Position()` for validation/simulation now
// goes through `PuzzleRuleEngine` instead, so the engine dependency lives in
// exactly one place and can evolve without scattering native calls across
// the puzzle tree.
//
// All reads are surfaced through the shared read-only [MillBoardView] so the
// puzzle code shares one position-view abstraction with the rest of the app.

import '../../game_page/services/mill.dart' show MillBoardView;
import '../../game_platform/game_session.dart' show GameAction;
import '../../games/mill/mill_action_codec.dart';
import '../../games/mill/native_mill_rules_port.dart';
import '../../rule_settings/models/rule_settings.dart';

/// A disposable, headless Mill rule engine backed by the Rust kernel.
///
/// Create one with [tryLoad] (FEN-seeded) and remember to call [dispose] when
/// finished.  Instances are cheap relative to a full game session but still
/// own a native kernel handle, so do not leak them in tight loops.
class PuzzleRuleEngine {
  PuzzleRuleEngine._(this._port);

  final NativeMillRulesPort _port;
  bool _disposed = false;

  /// Loads [fen] into a fresh kernel under [rules].
  ///
  /// Returns null when the FEN is rejected by the kernel, so callers can use
  /// this both as a parser and as a validator.
  static PuzzleRuleEngine? tryLoad(
    String fen, {
    RuleSettings rules = const RuleSettings(),
  }) {
    NativeMillRulesPort? port;
    try {
      port = NativeMillRulesPort(ruleSettings: rules);
      port.setFromFen(fen);
      return PuzzleRuleEngine._(port);
    } on Object {
      port?.dispose();
      return null;
    }
  }

  /// Returns true when [fen] is a syntactically and semantically valid Mill
  /// position under [rules].  Loads and immediately disposes a kernel.
  static bool isValidFen(
    String fen, {
    RuleSettings rules = const RuleSettings(),
  }) {
    final PuzzleRuleEngine? engine = tryLoad(fen, rules: rules);
    if (engine == null) {
      return false;
    }
    engine.dispose();
    return true;
  }

  /// Current read-only board view of this engine's position.
  MillBoardView get view {
    assert(!_disposed, 'PuzzleRuleEngine used after dispose().');
    return MillBoardView.fromNativeSnapshot(
          _port.snapshot,
          _port.exportFen(),
        ) ??
        MillBoardView.empty();
  }

  /// Notation strings ("d6", "d6-e5", "xd6") for every currently legal move.
  List<String> legalMoveNotations() {
    assert(!_disposed, 'PuzzleRuleEngine used after dispose().');
    return _port.legalActions
        .map(MillActionCodec.moveStringFrom)
        .where((String? m) => m != null && m.isNotEmpty)
        .cast<String>()
        .toList(growable: false);
  }

  /// Applies the move identified by [notation] if it is currently legal.
  ///
  /// Returns true when the move was applied, false when no legal move matched.
  bool applyMove(String notation) {
    assert(!_disposed, 'PuzzleRuleEngine used after dispose().');
    for (final GameAction action in _port.legalActions) {
      if (MillActionCodec.moveStringFrom(action) == notation) {
        _port.apply(action);
        return true;
      }
    }
    return false;
  }

  /// Replays [moves] in order, stopping at the first illegal move.
  ///
  /// Returns the number of moves successfully applied.
  int applyMoves(Iterable<String> moves) {
    int applied = 0;
    for (final String move in moves) {
      if (!applyMove(move)) {
        break;
      }
      applied++;
    }
    return applied;
  }

  /// Releases the underlying native kernel handle.  Idempotent.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _port.dispose();
  }
}
