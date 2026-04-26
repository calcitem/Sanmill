// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Phase 2 temporary adapter: Dart → FRB → Rust → cxx → mature C++ engine.
//
// This wrapper keeps the generated FRB API out of UI code.  It is intentionally
// small and will be replaced by the real Rust GameKernel in later phases.

import '../../src/rust/api/simple.dart' as tgf;
import '../../src/rust/frb_generated.dart';

/// Thin Dart wrapper around the Phase 2 legacy kernel singleton.
class LegacyTgfKernel {
  const LegacyTgfKernel();

  /// Load the native FRB library and initialise bridge utilities.
  Future<void> init() => RustLib.init();

  /// Reset to the selected C++ rule index and return the starting FEN.
  String reset({int ruleIndex = 0}) =>
      tgf.legacyKernelReset(ruleIdx: ruleIndex);

  /// Current C++ FEN string.
  String fen() => tgf.legacyKernelFen();

  /// Current legal actions in UCI notation.
  List<String> legalActions() => tgf.legacyKernelLegalActions();

  /// Apply a UCI-style move (`d7`, `d7-g7`, `xa1`, ...).
  bool applyUci(String move) => tgf.legacyKernelApplyUci(moveUci: move);

  /// Raw C++ Phase enum tag.
  int phaseTag() => tgf.legacyKernelPhaseTag();

  /// Raw C++ Color enum tag for side to move.
  int sideToMove() => tgf.legacyKernelSideToMove();
}
