// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_responses.dart

part of '../mill.dart';

/// Custom response we can catch without affecting other thrown exceptions.
abstract class GameResponse {}

class GameResponseOK implements GameResponse {
  const GameResponseOK();
}

class IllegalAction implements GameResponse {
  const IllegalAction();
}

class IllegalPhase implements GameResponse {
  const IllegalPhase();
}

/// Custom response we throw when selecting a piece.
abstract class SelectResponse implements GameResponse {}

class CanOnlyMoveToAdjacentEmptyPoints implements SelectResponse {
  const CanOnlyMoveToAdjacentEmptyPoints();
}

class NoPieceSelected implements SelectResponse {
  const NoPieceSelected();
}

class SelectOurPieceToMove implements SelectResponse {
  const SelectOurPieceToMove();
}

/// Custom response we throw when removing pieces.
abstract class RemoveResponse implements GameResponse {}

class NoPieceToRemove implements RemoveResponse {
  const NoPieceToRemove();
}

class CanNotRemoveSelf implements RemoveResponse {
  const CanNotRemoveSelf();
}

class ShouldRemoveSelf implements RemoveResponse {
  const ShouldRemoveSelf();
}

class CanNotRemoveMill implements RemoveResponse {
  const CanNotRemoveMill();
}

class CanNotRemoveNonadjacent implements RemoveResponse {
  const CanNotRemoveNonadjacent();
}

/// Custom response to throw related to the engine.
abstract class EngineResponse {}

class EngineResponseOK implements EngineResponse {
  const EngineResponseOK();
}

class EngineResponseHumanOK implements EngineResponse {
  const EngineResponseHumanOK();
}

class EngineResponseSkip implements EngineResponse {
  const EngineResponseSkip();
}

class EngineNoBestMove implements EngineResponse {
  const EngineNoBestMove();
}

class EngineGameIsOver implements EngineResponse {
  const EngineGameIsOver();
}

class EngineTimeOut implements EngineResponse {
  const EngineTimeOut();
}

class EngineDummy implements EngineResponse {
  const EngineDummy();
}

/// Custom response to throw when navigating the game history.
abstract class HistoryResponse {
  static const String tag = "[_HistoryResponse]";
}

class HistoryOK implements HistoryResponse {
  const HistoryOK();

  @override
  String toString() {
    return "${HistoryResponse.tag} History is OK.";
  }
}

class HistoryAbort implements HistoryResponse {
  const HistoryAbort();

  @override
  String toString() {
    return "${HistoryResponse.tag} History aborted.";
  }
}

class HistoryRule implements HistoryResponse {
  const HistoryRule();

  @override
  String toString() {
    return "${HistoryResponse.tag} Moves and rules do not match.";
  }
}

class HistoryRange implements HistoryResponse {
  const HistoryRange();

  @override
  String toString() {
    return "${HistoryResponse.tag} Current is equal to moveIndex.";
  }
}
