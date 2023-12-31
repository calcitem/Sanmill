// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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

/// Custom response to throw when importing the game history.
abstract class ImportResponse {}

class ImportFormatException extends FormatException with ImportResponse {
  const ImportFormatException([String? source, int? offset])
      : super("Cannot import ", source, offset);
}
