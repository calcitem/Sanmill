// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game.dart

part of '../mill.dart';

class Player {
  Player({required this.color, required this.isAi});

  final PieceColor color;
  bool isAi;
}

class Game {
  Game({required GameMode gameMode}) {
    this.gameMode = gameMode;
  }

  static const String _logTag = "[game]";

  bool get isAiSideToMove {
    final PieceColor side = GameController().activeBoardView.sideToMove;
    assert(side == PieceColor.white || side == PieceColor.black);
    return getPlayerByColor(side).isAi;
  }

  bool get isHumanToMove => !isAiSideToMove;

  int? focusIndex;
  int? blurIndex;
  int? removeIndex;
  PieceColor? removePieceColor;
  PieceColor? removeByColor;

  /// One-shot flag: if the last place/move formed a mill, play [Sound.mill]
  /// when the piece lands (put-down completes).
  ///
  /// This keeps sound and animation in sync and avoids playing mill sound
  /// before the piece is visually on the board.
  bool playMillSoundOnLanding = false;

  /// One-shot barrier for sequencing follow-up actions after a mill is formed.
  ///
  /// When a mill is formed, AI may immediately perform a remove move on the
  /// same turn. This barrier completes only after the mill sound effect has
  /// finished playing, so AI can delay the remove animation/sound to avoid
  /// overlapping audio.
  Completer<void>? pendingMillSoundCompleter;

  /// Wait until a deferred mill landing sound finishes before applying a
  /// follow-up remove move.  Mirrors master `engineToGo` which awaited
  /// [pendingMillSoundCompleter] when the AI's next move was a capture.
  Future<void> awaitPendingMillSoundBeforeRemove() async {
    final Completer<void>? pending = pendingMillSoundCompleter;
    if (pending != null && !pending.isCompleted) {
      await pending.future;
    }
    if (pendingMillSoundCompleter == pending) {
      pendingMillSoundCompleter = null;
    }
  }

  final List<Player> players = <Player>[
    Player(color: PieceColor.white, isAi: false),
    Player(color: PieceColor.black, isAi: true),
  ];

  Player getPlayerByColor(PieceColor color) {
    if (color == PieceColor.draw) {
      return Player(color: PieceColor.draw, isAi: false);
    } else if (color == PieceColor.marked) {
      return Player(color: PieceColor.marked, isAi: false);
    } else if (color == PieceColor.nobody) {
      return Player(color: PieceColor.nobody, isAi: false);
    } else if (color == PieceColor.none) {
      return Player(color: PieceColor.none, isAi: false);
    }

    return players.firstWhere((Player player) => player.color == color);
  }

  void reverseWhoIsAi() {
    if (GameController().gameInstance.gameMode == GameMode.humanVsAi) {
      for (final Player player in players) {
        player.isAi = !player.isAi;
      }
    } else if (GameController().gameInstance.gameMode ==
        GameMode.humanVsHuman) {
      final bool whiteIsAi = getPlayerByColor(PieceColor.white).isAi;
      final bool blackIsAi = getPlayerByColor(PieceColor.black).isAi;
      if (whiteIsAi == blackIsAi) {
        getPlayerByColor(GameController().activeBoardView.sideToMove).isAi =
            true;
      } else {
        for (final Player player in players) {
          player.isAi = false;
        }
      }
    }
  }

  late GameMode _gameMode;

  GameMode get gameMode => _gameMode;

  set gameMode(GameMode type) {
    _gameMode = type;

    logger.i("$_logTag Engine type: $type");

    final Map<PieceColor, bool> whoIsAi = type.whoIsAI;
    for (final Player player in players) {
      player.isAi = whoIsAi[player.color]!;
    }

    logger.i(
      "$_logTag White is AI? ${getPlayerByColor(PieceColor.white).isAi}\n"
      "$_logTag Black is AI? ${getPlayerByColor(PieceColor.black).isAi}\n",
    );

    // Clear animation indices when switching game modes to prevent stale
    // animation state from affecting piece rendering in the new mode.
    focusIndex = null;
    blurIndex = null;
  }

  // The legacy `bool doMove(ExtMove)` programmatic move applier was
  // removed together with the rest of the Dart `Position` rule
  // machine.  Production move flows go through
  // `NativeMillGameSession.apply(GameAction)` directly; the
  // `MillSessionRecorderBridge` updates `gameRecorder` from session
  // events.
}
