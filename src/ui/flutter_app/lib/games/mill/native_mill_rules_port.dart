// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Rust-native Mill RulesPort.
//
// Backs `NativeMillGameSession` with the `crates/tgf-mill::MillRules`
// implementation through the typed FRB `TgfKernel` surface.  This is
// the production path for the Mill game on `next`; the legacy C++
// bridge it used to parallel was deleted in Phase 3 / Phase 4.

import 'dart:typed_data';

import '../../game_platform/engine/tgf_kernel.dart';
import '../../game_platform/game_id.dart';
import '../../game_platform/game_session.dart';
import '../../game_platform/rules_port.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../src/rust/api/kernel.dart' as tgf;
import '../../src/rust/api/simple.dart' as tgf_simple;
import 'mill_action_codec.dart';
import 'mill_kernel_session.dart';
import 'mill_marked_pieces_codec.dart';
import 'mill_perfect_database_support.dart';
import 'mill_variant_options_mapper.dart';

class NativeMillRulesPort implements RulesPort {
  NativeMillRulesPort({
    MillKernelSession? session,
    RuleSettings ruleSettings = const RuleSettings(),
    GeneralSettings? generalSettings,
  }) : _generalSettings = generalSettings ?? const GeneralSettings(),
       _session =
           session ??
           MillKernelSession.fromVariant(
             ruleSettings.toTgfMillVariantOptions(
               generalSettings: generalSettings,
             ),
           ) {
    _snapshot = _snapshotFromKernel();
  }

  final GeneralSettings _generalSettings;
  final MillKernelSession _session;
  late GameStateSnapshot _snapshot;

  TgfKernel get _kernel => _session.kernel;

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
    final tgf.TgfSnapshot raw = _session.rawSetupClear();
    _snapshot = _snapshotFromRaw(raw);
    return _snapshot;
  }

  /// Place or clear a single piece at [node] during setup editing.
  /// [owner]: 1 = first player, 2 = second player, other = clear.
  GameStateSnapshot setupSetPiece(int node, int owner) {
    final tgf.TgfSnapshot raw = _session.rawSetupSetPiece(node, owner);
    _snapshot = _snapshotFromRaw(raw);
    return _snapshot;
  }

  /// Set the side to move during setup editing. [side]: 0 or 1.
  GameStateSnapshot setupSetSide(int side) {
    final tgf.TgfSnapshot raw = _session.rawSetupSetSide(side);
    _snapshot = _snapshotFromRaw(raw);
    return _snapshot;
  }

  /// Finish setup-position editing and transition to a playable game state.
  GameStateSnapshot setupFinish() {
    final tgf.TgfSnapshot raw = _session.rawSetupFinish();
    _snapshot = _snapshotFromRaw(raw);
    return _snapshot;
  }

  /// Load a board position from a Mill FEN string (Phase 6.A.3.B).
  GameStateSnapshot setFromFen(String fen) {
    final tgf.TgfSnapshot raw = _session.rawSetFromFen(fen);
    _snapshot = _snapshotFromRaw(raw);
    return _snapshot;
  }

  /// Export the current kernel state as a Mill FEN string (Phase 6.A.3.B).
  String exportFen() => _session.rawExportFen();

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
        millMarkedNodesPayloadKey:
            MillMarkedPiecesCodec.markedNodesFromOpaquePayload(opaque),
      },
    );
  }

  /// Stream Rust-native Mill search events from this port's current kernel
  /// state.  This keeps the future engine path tied to the same session
  /// snapshot that legalActions/apply/undo/redo mutate.
  ///
  /// When [moveLimitMs] is greater than zero the search is time-bounded
  /// (matches the legacy C++ `MoveTime` UCI option).
  Stream<tgf_simple.EngineEvent> millSearchEvents({
    required int depth,
    int moveLimitMs = 0,
  }) {
    final bool usePerfectDatabase =
        _generalSettings.usePerfectDatabase &&
        isRuleSupportingPerfectDatabase();
    return _session.searchEvents(
      depth: depth,
      moveLimitMs: moveLimitMs,
      usePerfectDatabase: usePerfectDatabase,
      algorithm: _millSearchAlgorithm(_generalSettings.searchAlgorithm),
      aiIsLazy: _generalSettings.aiIsLazy,
      skillLevel: _generalSettings.skillLevel,
    );
  }

  /// Map the persisted Dart [SearchAlgorithm] enum onto the FRB
  /// [tgf_simple.MillSearchAlgorithm] consumed by the Rust dispatcher.
  /// Falls back to MTD(f) when the setting is null (matches the engine
  /// default documented on `MillEngineConfig`).
  static tgf_simple.MillSearchAlgorithm _millSearchAlgorithm(
    SearchAlgorithm? algorithm,
  ) {
    switch (algorithm) {
      case SearchAlgorithm.alphaBeta:
        return tgf_simple.MillSearchAlgorithm.alphaBeta;
      case SearchAlgorithm.pvs:
        return tgf_simple.MillSearchAlgorithm.pvs;
      case SearchAlgorithm.mtdf:
        return tgf_simple.MillSearchAlgorithm.mtdf;
      case SearchAlgorithm.mcts:
        return tgf_simple.MillSearchAlgorithm.mcts;
      case SearchAlgorithm.random:
        return tgf_simple.MillSearchAlgorithm.random;
      case null:
        return tgf_simple.MillSearchAlgorithm.mtdf;
    }
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
        millMarkedNodesPayloadKey:
            MillMarkedPiecesCodec.markedNodesFromOpaquePayload(opaque),
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
