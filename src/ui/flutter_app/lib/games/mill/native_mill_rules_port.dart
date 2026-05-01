// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Rust-native Mill RulesPort.
//
// This port is intentionally parallel to the existing `MillRulesPort`
// (legacy C++ bridge) and is not wired into the main GameController yet.
// It gives tests and future sessions a direct RulesPort backed by
// `crates/tgf-mill::MillRules` through the typed FRB `TgfKernel` surface.

import 'dart:typed_data';

import '../../game_platform/engine/tgf_kernel.dart';
import '../../game_platform/game_id.dart';
import '../../game_platform/game_session.dart';
import '../../game_platform/mill_marked_pieces_codec.dart';
import '../../game_platform/rules_port.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../src/rust/api/kernel.dart' as tgf;
import '../../src/rust/api/simple.dart' as tgf_simple;
import 'mill_action_codec.dart';
import 'mill_variant_options_mapper.dart';

class NativeMillRulesPort implements RulesPort {
  NativeMillRulesPort({
    TgfKernel? kernel,
    RuleSettings ruleSettings = const RuleSettings(),
  }) : _kernel =
           kernel ??
           TgfKernel.createMill(ruleSettings.toTgfMillVariantOptions()) {
    _snapshot = _snapshotFromKernel();
  }

  final TgfKernel _kernel;
  late GameStateSnapshot _snapshot;

  @override
  GameStateSnapshot get snapshot => _snapshot;

  @override
  List<GameAction> get legalActions {
    if (_snapshot.outcome.isTerminal) {
      return const <GameAction>[];
    }
    return _kernel
        .rawLegalActions()
        .map(MillActionCodec.fromTgfAction)
        .toList(growable: false);
  }

  @override
  bool isLegal(GameAction action) {
    final tgf.TgfAction? rustAction = MillActionCodec.toTgfAction(action);
    if (rustAction == null) {
      return false;
    }
    return _kernel.rawLegalActions().contains(rustAction);
  }

  @override
  GameStateSnapshot apply(GameAction action) {
    final tgf.TgfAction? rustAction = MillActionCodec.toTgfAction(action);
    assert(rustAction != null, 'Illegal Mill action payload: ${action.type}.');
    _kernel.rawApply(rustAction!);
    _snapshot = _snapshotFromKernel(lastAction: action);
    return _snapshot;
  }

  GameStateSnapshot undo() {
    _kernel.rawUndo();
    _snapshot = _snapshotFromKernel();
    return _snapshot;
  }

  GameStateSnapshot redo() {
    _kernel.rawRedo();
    _snapshot = _snapshotFromKernel();
    return _snapshot;
  }

  int get undoDepth => _kernel.undoDepth;

  int get redoDepth => _kernel.redoDepth;

  void dispose() => _kernel.dispose();

  // -------------------------------------------------------- setup-position API

  /// Clear the board for setup-position editing.
  /// Returns the new snapshot with all squares empty.
  GameStateSnapshot setupClear() {
    final tgf.TgfSnapshot raw = _kernel.rawSetupClear();
    _snapshot = _snapshotFromRaw(raw);
    return _snapshot;
  }

  /// Place or clear a single piece at [node] during setup editing.
  /// [owner]: 1 = first player, 2 = second player, other = clear.
  GameStateSnapshot setupSetPiece(int node, int owner) {
    final tgf.TgfSnapshot raw = _kernel.rawSetupSetPiece(node, owner);
    _snapshot = _snapshotFromRaw(raw);
    return _snapshot;
  }

  /// Set the side to move during setup editing. [side]: 0 or 1.
  GameStateSnapshot setupSetSide(int side) {
    final tgf.TgfSnapshot raw = _kernel.rawSetupSetSide(side);
    _snapshot = _snapshotFromRaw(raw);
    return _snapshot;
  }

  /// Finish setup-position editing and transition to a playable game state.
  GameStateSnapshot setupFinish() {
    final tgf.TgfSnapshot raw = _kernel.rawSetupFinish();
    _snapshot = _snapshotFromRaw(raw);
    return _snapshot;
  }

  GameStateSnapshot _snapshotFromRaw(tgf.TgfSnapshot raw) {
    final tgf.TgfOutcome outcome = _kernel.rawOutcome();
    final Uint8List opaque = Uint8List.fromList(raw.opaquePayload);
    return GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: _seatFromSide(raw.sideToMove),
      outcome: _outcomeFromTgf(outcome),
      phase: _phaseName(raw.phaseTag),
      payload: <String, Object?>{
        'tgfPhaseTag': raw.phaseTag,
        'tgfMoveNumber': raw.moveNumber,
        'tgfZobrist': raw.zobristKey,
        'tgfOutcomeReason': outcome.reason,
        'tgfPayload': opaque,
        'millMarkedNodes': MillMarkedPiecesCodec.markedNodesFromOpaquePayload(
          opaque,
        ),
      },
    );
  }

  /// Stream Rust-native Mill search events from this port's current kernel
  /// state.  This keeps the future engine path tied to the same session
  /// snapshot that legalActions/apply/undo/redo mutate.
  Stream<tgf_simple.EngineEvent> millSearchEvents({required int depth}) {
    return _kernel.millSearchEvents(depth: depth);
  }

  GameStateSnapshot _snapshotFromKernel({GameAction? lastAction}) {
    final tgf.TgfSnapshot raw = _kernel.rawSnapshot();
    final tgf.TgfOutcome outcome = _kernel.rawOutcome();
    final Uint8List opaque = Uint8List.fromList(raw.opaquePayload);
    return GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: _seatFromSide(raw.sideToMove),
      outcome: _outcomeFromTgf(outcome),
      phase: _phaseName(raw.phaseTag),
      lastAction: lastAction,
      payload: <String, Object?>{
        'tgfPhaseTag': raw.phaseTag,
        'tgfMoveNumber': raw.moveNumber,
        'tgfZobrist': raw.zobristKey,
        'tgfOutcomeReason': outcome.reason,
        'tgfPayload': opaque,
        'millMarkedNodes': MillMarkedPiecesCodec.markedNodesFromOpaquePayload(
          opaque,
        ),
      },
    );
  }

  static PlayerSeat _seatFromSide(int side) {
    return switch (side) {
      0 => PlayerSeat.first,
      1 => PlayerSeat.second,
      _ => PlayerSeat.none,
    };
  }

  static GameOutcome _outcomeFromTgf(tgf.TgfOutcome outcome) {
    return switch (outcome.kind) {
      'win' => GameOutcome.win(_seatFromSide(outcome.winner)),
      'draw' => const GameOutcome.draw(),
      'abandoned' => const GameOutcome.abandoned(),
      _ => const GameOutcome.ongoing(),
    };
  }

  static String _phaseName(int phaseTag) {
    return switch (phaseTag) {
      0 => 'ready',
      1 => 'placing',
      2 => 'moving',
      3 => 'gameOver',
      _ => 'unknown',
    };
  }
}
