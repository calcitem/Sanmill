// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// engine.dart
//
// Post-Phase-3 shim.  The real Mill engine lives in the Rust/TGF stack
// (`crates/tgf-mill::MillRules`, `crates/tgf-search::Searcher`) and is
// surfaced to Dart through `tgf_kernel_*` FRB calls and
// `NativeMillGameSession`.  Everything that used to talk to the C++
// UCI thread over `MethodChannel("com.calcitem.sanmill/engine")` has
// been deleted; the channel handlers on the iOS / macOS / Android
// runners no longer exist, and the C++ source tree was removed in
// Phase 3 (commit ff357aadc).
//
// This file remains as the home of:
//
//   * `enum GameMode` and its `whoIsAI` / header-icon extension —
//     consumed by the controller, the AI-turn controller, the
//     game-page header, the move-options modal, and the persistence
//     layer.  Migration of these consumers to the typed Rust path is
//     tracked in a follow-up cleanup; for now they share this enum
//     definition.
//   * `aiMoveTypeIcons` — static lookup used by the page header.
//   * `class Engine {}` — empty shim placeholder.  The
//     `GameController.engine` field still exists for one transition
//     so call-sites that read it during dispose / navigation paths
//     do not have to be fanned out in the same patch.  Phase C will
//     remove the field and this class together.

part of '../mill.dart';

/// Empty shim left behind by the Phase 3 / Phase 4 cleanup.
///
/// The class no longer talks to a native UCI engine; every previous
/// public method (search / analyze / startup / shutdown / option
/// broadcast) was a stub after the C++ engine deletion in Phase 3
/// and has been removed.  The remaining `Engine engine` field on
/// `GameController` is kept for one PR so consumers that hold a
/// stale reference compile; the field itself is deleted in Phase C.
class Engine {
  const Engine();
}

enum GameMode {
  humanVsAi,
  humanVsHuman,
  aiVsAi,
  setupPosition,
  puzzle,
  humanVsCloud, // Not Implemented
  humanVsLAN,
  testViaLAN, // Not Implemented
}

Map<AiMoveType, IconData> aiMoveTypeIcons = <AiMoveType, IconData>{
  AiMoveType.traditional: FluentIcons.bot_24_filled,
  AiMoveType.consensus: FluentIcons.bot_add_24_filled,
  AiMoveType.unknown: FluentIcons.bot_24_filled,
};

extension GameModeExtension on GameMode {
  IconData get leftHeaderIcon {
    final IconData botIcon =
        aiMoveTypeIcons[GameController().aiMoveType] ??
        FluentIcons.bot_24_filled;

    switch (this) {
      case GameMode.humanVsAi:
        if (DB().generalSettings.aiMovesFirst) {
          return botIcon;
        } else {
          return FluentIcons.person_24_filled;
        }
      case GameMode.humanVsHuman:
        return FluentIcons.person_24_filled;
      case GameMode.aiVsAi:
        return botIcon;
      case GameMode.setupPosition:
        if (DB().generalSettings.aiMovesFirst) {
          return FluentIcons.bot_24_regular;
        } else {
          return FluentIcons.person_24_regular;
        }
      case GameMode.puzzle:
        return FluentIcons.puzzle_piece_24_filled;
      case GameMode.humanVsCloud:
        return FluentIcons.person_24_filled;
      case GameMode.humanVsLAN:
        return FluentIcons.person_24_filled;
      case GameMode.testViaLAN:
        return FluentIcons.wifi_1_24_filled;
    }
  }

  IconData get rightHeaderIcon {
    final IconData botIcon =
        aiMoveTypeIcons[GameController().aiMoveType] ??
        FluentIcons.bot_24_filled;

    switch (this) {
      case GameMode.humanVsAi:
        if (DB().generalSettings.aiMovesFirst) {
          return FluentIcons.person_24_filled;
        } else {
          return botIcon;
        }
      case GameMode.humanVsHuman:
        return FluentIcons.person_24_filled;
      case GameMode.aiVsAi:
        return botIcon;
      case GameMode.setupPosition:
        if (DB().generalSettings.aiMovesFirst) {
          return FluentIcons.person_24_regular;
        } else {
          return FluentIcons.bot_24_regular;
        }
      case GameMode.puzzle:
        return FluentIcons.lightbulb_24_filled;
      case GameMode.humanVsCloud:
        return FluentIcons.cloud_24_filled;
      case GameMode.humanVsLAN:
        return FluentIcons.wifi_1_24_filled;
      case GameMode.testViaLAN:
        return FluentIcons.wifi_1_24_filled;
    }
  }

  Map<PieceColor, bool> get whoIsAI {
    switch (this) {
      case GameMode.humanVsAi:
      case GameMode.testViaLAN:
        return <PieceColor, bool>{
          PieceColor.white: DB().generalSettings.aiMovesFirst,
          PieceColor.black: !DB().generalSettings.aiMovesFirst,
        };
      case GameMode.puzzle:
        // Puzzle mode: the human plays exactly one side (set by PuzzlePage).
        // The opponent is treated as AI so the rest of the game logic can
        // recognize whose turn it is, while the actual moves are auto-played
        // from the puzzle's predefined solution line.
        final PieceColor? humanColor = GameController().puzzleHumanColor;
        if (humanColor == PieceColor.white) {
          return <PieceColor, bool>{
            PieceColor.white: false,
            PieceColor.black: true,
          };
        }
        if (humanColor == PieceColor.black) {
          return <PieceColor, bool>{
            PieceColor.white: true,
            PieceColor.black: false,
          };
        }

        // If the puzzle hasn't been initialized yet, keep both sides human to
        // avoid triggering engine search from generic AI hooks.
        return <PieceColor, bool>{
          PieceColor.white: false,
          PieceColor.black: false,
        };
      case GameMode.setupPosition:
      case GameMode.humanVsHuman:
      case GameMode.humanVsLAN:
      case GameMode.humanVsCloud:
        return <PieceColor, bool>{
          PieceColor.white: false,
          PieceColor.black: false,
        };
      case GameMode.aiVsAi:
        return <PieceColor, bool>{
          PieceColor.white: true,
          PieceColor.black: true,
        };
    }
  }
}
