// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Mill-specific session adapter that decorates a generic [TgfKernel] with
// the search-event stream, setup-position editing entry points, and Mill
// FEN import / export operations.  Lives under `lib/games/mill/` so the
// game-neutral [TgfKernel] does not need to know about Mill APIs.

import '../../game_platform/engine/tgf_kernel.dart';
import '../../src/rust/api/kernel.dart' as tgf;
import '../../src/rust/api/mill_kernel.dart' as tgf_mill;
import '../../src/rust/api/simple.dart' as tgf_simple;

/// Wraps a [TgfKernel] and exposes the FRB entry points that are only
/// meaningful for Mill kernels.  Each instance borrows the underlying
/// kernel; lifecycle is the caller's responsibility (typically a
/// `GameSession`).
class MillKernelSession {
  MillKernelSession(this.kernel) : assert(kernel.gameId == 'mill');

  /// Spin up a fresh Mill kernel with explicit variant options and wrap
  /// it in a [MillKernelSession].
  factory MillKernelSession.fromVariant(tgf_simple.MillVariantOptions variant) {
    final int handle = tgf_mill.tgfKernelCreateMill(variant: variant);
    final TgfKernel adopted = TgfKernel.adopt(handle: handle, gameId: 'mill');
    return MillKernelSession(adopted);
  }

  final TgfKernel kernel;
  int _lastRawBestValue = 0;

  /// PVS search event stream backed by the Rust `tgfKernelMillSearchEvents*`
  /// FRB entry points.  Uses the variant options that were passed when the
  /// kernel was created (see `tgf_kernel_create_mill`).
  ///
  /// When [moveLimitMs] is greater than zero the search is time-bounded
  /// (matches the legacy C++ `MoveTime` UCI option); otherwise depth alone
  /// drives termination.
  Stream<tgf_simple.EngineEvent> searchEvents({
    required int depth,
    int moveLimitMs = 0,
    bool usePerfectDatabase = false,
    tgf_simple.MillSearchAlgorithm algorithm =
        tgf_simple.MillSearchAlgorithm.pvs,
    bool aiIsLazy = false,
    int skillLevel = 1,
    bool shuffling = true,
  }) {
    if (kernel.isDisposed) {
      throw KernelException('handle already disposed');
    }
    final Stream<tgf_simple.EngineEvent> events = tgf_mill
        .tgfKernelMillSearchEventsWithConfig(
          handle: kernel.rawHandle,
          config: tgf_simple.MillEngineConfig(
            algorithm: algorithm,
            depth: depth,
            moveTimeMs: moveLimitMs,
            aiIsLazy: aiIsLazy,
            lastBestValue: _lastRawBestValue,
            skillLevel: skillLevel,
            usePerfectDatabase: usePerfectDatabase,
            shuffling: shuffling,
          ),
        );
    return events.map((tgf_simple.EngineEvent event) {
      if (event.kind == 'bestMove') {
        _lastRawBestValue = _rawScoreFromReason(event.reason);
      }
      return event;
    });
  }

  /// Query the perfect database for the current kernel position without
  /// running search or mutating the session.
  tgf.TgfAction? rawPerfectDbBestAction({
    required bool usePerfectDatabase,
    bool aiIsLazy = false,
    bool shuffling = true,
  }) {
    if (kernel.isDisposed) {
      throw KernelException('handle already disposed');
    }
    return tgf_mill.tgfKernelMillPerfectDbBestAction(
      handle: kernel.rawHandle,
      config: tgf_simple.MillEngineConfig(
        algorithm: tgf_simple.MillSearchAlgorithm.pvs,
        depth: 1,
        moveTimeMs: 0,
        aiIsLazy: aiIsLazy,
        lastBestValue: _lastRawBestValue,
        skillLevel: 1,
        usePerfectDatabase: usePerfectDatabase,
        shuffling: shuffling,
      ),
    );
  }

  // ---------------------------------------------------------- setup-position

  /// Clear the board and reset all pieces for setup-position editing.
  /// Returns the empty-board snapshot.  History is cleared.
  tgf.TgfSnapshot rawSetupClear() {
    return tgf_mill.tgfKernelSetupClear(handle: kernel.rawHandle);
  }

  /// Place or clear a single piece during setup editing.
  /// [owner]: 1 = first player, 2 = second player, other = clear.
  tgf.TgfSnapshot rawSetupSetPiece(int node, int owner) {
    return tgf_mill.tgfKernelSetupSetPiece(
      handle: kernel.rawHandle,
      node: node,
      owner: owner,
    );
  }

  /// Set the side to move during setup editing.  [side]: 0 or 1.
  tgf.TgfSnapshot rawSetupSetSide(int side) {
    return tgf_mill.tgfKernelSetupSetSide(handle: kernel.rawHandle, side: side);
  }

  /// Finish setup editing and transition to a playable game state.
  tgf.TgfSnapshot rawSetupFinish() {
    return tgf_mill.tgfKernelSetupFinish(handle: kernel.rawHandle);
  }

  /// Load a position from a Mill FEN string.
  tgf.TgfSnapshot rawSetFromFen(String fen) {
    return tgf_mill.tgfKernelSetFromFen(handle: kernel.rawHandle, fen: fen);
  }

  /// Export the current kernel state as a Mill FEN string.
  String rawExportFen() {
    return tgf_mill.tgfKernelExportFen(handle: kernel.rawHandle);
  }

  /// Analyse the kernel's current position, returning one verdict per legal
  /// move plus detected trap moves.  Verdicts come from the perfect database
  /// (win/draw/loss) or a heuristic-search fallback (advantage/disadvantage).
  /// Trap moves are only populated when [trapAwareness] is set.
  tgf_simple.MillAnalysisReport rawPerfectDbAnalyze({
    required bool trapAwareness,
  }) {
    return tgf_mill.tgfKernelMillPerfectDbAnalyze(
      handle: kernel.rawHandle,
      trapAwareness: trapAwareness,
    );
  }

  int _rawScoreFromReason(String reason) {
    final RegExpMatch? match = RegExp(
      r'(?:^|\s)rawScore=(-?\d+)(?:\s|$)',
    ).firstMatch(reason);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1)!) ?? 0;
  }
}
