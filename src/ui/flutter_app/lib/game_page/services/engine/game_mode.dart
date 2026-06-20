// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_mode.dart
//
// Game-mode enum + header-icon extension that used to live next to the
// (now deleted) Mill UCI engine bridge.  Consumers across the
// controller, AI-turn driver, page header, modal, and persistence
// layer share these symbols.

part of '../mill.dart';

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
  AiMoveType.perfect: FluentIcons.database_24_filled,
  AiMoveType.consensus: FluentIcons.bot_add_24_filled,
  AiMoveType.openingBook: FluentIcons.book_24_filled,
  AiMoveType.humanDatabase: FluentIcons.database_24_filled,
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
      case GameMode.puzzle:
        return FluentIcons.puzzle_piece_24_filled;
      case GameMode.setupPosition:
        // Setup-position mode is retired but the enum value is kept
        // as a sentinel so old experience-recording sessions still
        // parse.  The icon is unreachable on this branch but must be
        // a valid `IconData` to keep the switch exhaustive.
        return FluentIcons.person_24_filled;
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
      case GameMode.puzzle:
        return FluentIcons.lightbulb_24_filled;
      case GameMode.setupPosition:
        // See `leftHeaderIcon` -- sentinel branch for the retired
        // setup-position mode.
        return FluentIcons.person_24_filled;
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
