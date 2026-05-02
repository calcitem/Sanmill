// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Typed Dart wrapper around the FRB-generated `tgfKernel*` API.
//
// The Rust side owns the actual `GameKernel` instances; Dart only sees an
// integer handle and a small typed surface (`TgfSnapshot`, `TgfAction`,
// `TgfOutcome`).  This wrapper centralizes lifecycle (`create` / `dispose`),
// converts between FRB DTOs and the framework-level `GameStateSnapshot` /
// `GameAction` value objects, and handles errors as `KernelException`.
//
// Phase 4 wiring strategy:
//   * Othello uses this wrapper exclusively (its rules live entirely in
//     Rust; no fallback path).
//   * Mill keeps the existing `LegacyTgfKernel`-backed `MillRulesPort` for
//     now because the Rust `MillVariantOptions` still covers only a
//     subset of the rule variants (see crates/tgf-mill::MillVariantOptions).
//     Once `mill-rules` lands, Mill will switch to this wrapper too.
//
// All Rust calls are synchronous (`#[frb(sync)]`); we still expose them
// as plain Dart methods so the call sites read naturally even if a future
// FRB revision flips them to `Future`s.

import 'dart:typed_data';

import '../../src/rust/api/kernel.dart' as tgf;
import '../../src/rust/api/simple.dart' as tgf_simple;
import '../game_id.dart';
import '../game_session.dart';
import '../mill_marked_pieces_codec.dart';

/// Surfaced when the underlying Rust kernel returns a [Result::Err].  The
/// inner [reason] is the stable English token from `tgf_core::KernelError`
/// (e.g. "illegal action", "nothing to undo"); UI code maps it to l10n.
class KernelException implements Exception {
  KernelException(this.reason);
  final String reason;

  @override
  String toString() => 'KernelException(reason=$reason)';
}

/// Typed handle to a Rust-side `tgf_core::GameKernel` session.
///
/// The handle is owned by exactly one Dart object; failing to call
/// [dispose] before the wrapper is garbage-collected will leak the Rust
/// side until process exit.  Always call [dispose] in the consumer's
/// teardown path (e.g. `GameSession.dispose`).
class TgfKernel {
  TgfKernel._(this._handle, this.gameId);

  /// Spin up a default-options session for `gameId`.  Currently supports
  /// `mill` and `othello`; extending that list is a Rust-side change in
  /// `crates/tgf-frb/src/api/kernel.rs::build_rules_default`.
  factory TgfKernel.create(String gameId) {
    final int handle = tgf.tgfKernelCreate(gameId: gameId);
    return TgfKernel._(handle, gameId);
  }

  /// Spin up a Mill session with explicit variant options.
  factory TgfKernel.createMill(tgf_simple.MillVariantOptions variant) {
    final int handle = tgf.tgfKernelCreateMill(variant: variant);
    return TgfKernel._(handle, 'mill');
  }

  final int _handle;
  final String gameId;
  bool _disposed = false;

  /// Drop the underlying Rust session.  Safe to call multiple times.
  void dispose() {
    if (_disposed) {
      return;
    }
    tgf.tgfKernelDispose(handle: _handle);
    _disposed = true;
  }

  bool get isDisposed => _disposed;

  void _checkAlive() {
    if (_disposed) {
      throw KernelException('handle already disposed');
    }
  }

  tgf.TgfSnapshot rawSnapshot() {
    _checkAlive();
    return tgf.tgfKernelSnapshot(handle: _handle);
  }

  List<tgf.TgfAction> rawLegalActions() {
    _checkAlive();
    return tgf.tgfKernelLegalActions(handle: _handle);
  }

  tgf.TgfSnapshot rawApply(tgf.TgfAction action) {
    _checkAlive();
    return tgf.tgfKernelApply(handle: _handle, action: action);
  }

  tgf.TgfSnapshot rawUndo() {
    _checkAlive();
    return tgf.tgfKernelUndo(handle: _handle);
  }

  tgf.TgfSnapshot rawRedo() {
    _checkAlive();
    return tgf.tgfKernelRedo(handle: _handle);
  }

  tgf.TgfOutcome rawOutcome() {
    _checkAlive();
    return tgf.tgfKernelOutcome(handle: _handle);
  }

  bool get isTerminal {
    _checkAlive();
    return tgf.tgfKernelIsTerminal(handle: _handle);
  }

  int get undoDepth {
    _checkAlive();
    return tgf.tgfKernelUndoDepth(handle: _handle);
  }

  int get redoDepth {
    _checkAlive();
    return tgf.tgfKernelRedoDepth(handle: _handle);
  }

  // -------------------------------------------------------- setup-position API

  /// Clear the board and reset all pieces for setup-position editing.
  /// Returns the empty-board snapshot.  History is cleared.
  tgf.TgfSnapshot rawSetupClear() {
    _checkAlive();
    return tgf.tgfKernelSetupClear(handle: _handle);
  }

  /// Place or clear a single piece during setup editing.
  /// [owner]: 1 = first player, 2 = second player, other = clear.
  tgf.TgfSnapshot rawSetupSetPiece(int node, int owner) {
    _checkAlive();
    return tgf.tgfKernelSetupSetPiece(
      handle: _handle,
      node: node,
      owner: owner,
    );
  }

  /// Set the side to move during setup editing. [side]: 0 or 1.
  tgf.TgfSnapshot rawSetupSetSide(int side) {
    _checkAlive();
    return tgf.tgfKernelSetupSetSide(handle: _handle, side: side);
  }

  /// Finish setup editing and transition to a playable game state.
  tgf.TgfSnapshot rawSetupFinish() {
    _checkAlive();
    return tgf.tgfKernelSetupFinish(handle: _handle);
  }

  /// Load a position from a Mill FEN string (Phase 6.A.3.B).
  tgf.TgfSnapshot rawSetFromFen(String fen) {
    _checkAlive();
    return tgf.tgfKernelSetFromFen(handle: _handle, fen: fen);
  }

  /// Export the current kernel state as a Mill FEN string (Phase 6.A.3.B).
  String rawExportFen() {
    _checkAlive();
    return tgf.tgfKernelExportFen(handle: _handle);
  }

  /// PVS search event stream for Mill kernels only — uses the session snapshot
  /// and the variant registered at [TgfKernel.createMill].
  ///
  /// When [moveLimitMs] is greater than zero the search is time-bounded
  /// (matches the legacy C++ `MoveTime` UCI option); otherwise depth alone
  /// drives termination.
  Stream<tgf_simple.EngineEvent> millSearchEvents({
    required int depth,
    int moveLimitMs = 0,
  }) {
    _checkAlive();
    if (moveLimitMs > 0) {
      return tgf.tgfKernelMillSearchEventsWithConfig(
        handle: _handle,
        config: tgf_simple.MillEngineConfig(
          algorithm: tgf_simple.MillSearchAlgorithm.pvs,
          depth: depth,
          moveTimeMs: moveLimitMs,
          aiIsLazy: false,
          lastBestValue: 0,
          skillLevel: 1,
        ),
      );
    }
    return tgf.tgfKernelMillSearchEvents(handle: _handle, depth: depth);
  }

  // --------------------------------------------------------------- mappings

  /// Project the typed Rust snapshot into the framework-level
  /// `GameStateSnapshot` value object the Flutter shell already understands.
  GameStateSnapshot toGameStateSnapshot({GameAction? lastAction}) {
    final tgf.TgfSnapshot raw = rawSnapshot();
    return _mapSnapshot(raw, lastAction);
  }

  GameStateSnapshot _mapSnapshot(tgf.TgfSnapshot raw, GameAction? lastAction) {
    final PlayerSeat seat = _mapSide(raw.sideToMove);
    final tgf.TgfOutcome outcomeRaw = rawOutcome();
    final GameOutcome outcome = _mapOutcome(outcomeRaw);
    final Uint8List opaque = Uint8List.fromList(raw.opaquePayload);
    return GameStateSnapshot(
      gameId: _mapGameId(),
      activeSeat: seat,
      outcome: outcome,
      phase: 'phase_${raw.phaseTag}',
      lastAction: lastAction,
      payload: <String, Object?>{
        'tgfHandle': _handle,
        'tgfPhaseTag': raw.phaseTag,
        'tgfMoveNumber': raw.moveNumber,
        'tgfZobrist': raw.zobristKey,
        'tgfPayload': opaque,
        'millMarkedNodes': MillMarkedPiecesCodec.markedNodesFromOpaquePayload(
          opaque,
        ),
      },
    );
  }

  GameId _mapGameId() {
    switch (gameId) {
      case 'mill':
        return GameId.mill;
      case 'othello':
        return GameId.othello;
      default:
        throw KernelException('unknown gameId mapping for "$gameId"');
    }
  }

  static PlayerSeat _mapSide(int rawSide) {
    if (rawSide == 0) {
      return PlayerSeat.first;
    }
    if (rawSide == 1) {
      return PlayerSeat.second;
    }
    return PlayerSeat.none;
  }

  static GameOutcome _mapOutcome(tgf.TgfOutcome raw) {
    switch (raw.kind) {
      case 'win':
        return GameOutcome.win(_mapSide(raw.winner));
      case 'draw':
        return const GameOutcome.draw();
      case 'abandoned':
        return const GameOutcome.abandoned();
      case 'ongoing':
      default:
        return const GameOutcome.ongoing();
    }
  }

  /// Apply [action] using the Rust kernel and return the framework-level
  /// snapshot.  Throws [KernelException] on illegal moves.
  GameStateSnapshot applyTypedAction(
    tgf.TgfAction action, {
    GameAction? lastAction,
  }) {
    final tgf.TgfSnapshot next = rawApply(action);
    return _mapSnapshot(next, lastAction);
  }

  /// Undo the last action.  Throws [KernelException] when at root.
  GameStateSnapshot undoTyped({GameAction? lastAction}) {
    final tgf.TgfSnapshot next = rawUndo();
    return _mapSnapshot(next, lastAction);
  }

  /// Redo the last undone action.  Throws [KernelException] when redo
  /// stack is empty.
  GameStateSnapshot redoTyped({GameAction? lastAction}) {
    final tgf.TgfSnapshot next = rawRedo();
    return _mapSnapshot(next, lastAction);
  }
}
