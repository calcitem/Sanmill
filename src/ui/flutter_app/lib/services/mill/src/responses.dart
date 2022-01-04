/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

part of '../mill.dart';

/// Custom response we can catch without affecting other thrown exceptions.
abstract class MillResponse {}

class IllegalAction implements MillResponse {
  const IllegalAction();
}

class IllegalPhase implements MillResponse {
  const IllegalPhase();
}

/// Custom response we throw when selecting a piece.
abstract class SeclectResponse implements MillResponse {}

class CanOnlyMoveToAdjacentEmptyPoints implements SeclectResponse {
  const CanOnlyMoveToAdjacentEmptyPoints();
}

class SelectOurPieceToMove implements SeclectResponse {
  const SelectOurPieceToMove();
}

/// Custom response we throw when removing pieces.
abstract class RemoveResponse implements MillResponse {}

class NoPieceToRemove implements RemoveResponse {
  const NoPieceToRemove();
}

class CanNotRemoveSelf implements RemoveResponse {
  const CanNotRemoveSelf();
}

class CanNotRemoveMill implements RemoveResponse {
  const CanNotRemoveMill();
}

/// Custom respnonse to throw related to the engine.
abstract class EngineResponse {}

class EngineNoBestMove implements EngineResponse {
  const EngineNoBestMove();
}

class EngineTimeOut extends TimeoutException with EngineResponse {
  EngineTimeOut([String? message, Duration? duration])
      : super(message, duration);
}

/// Custom response to throw when naivigating the game history.
abstract class _HistoryResponse {
  static const tag = "[_HistoryResponse]";
}

class _HistoryRule implements _HistoryResponse {
  const _HistoryRule();

  @override
  String toString() {
    return "${_HistoryResponse.tag} cur is equal to moveIndex.";
  }
}

class _HistoryRange implements _HistoryResponse {
  const _HistoryRange();

  @override
  String toString() {
    return "${_HistoryResponse.tag} cur is equal to moveIndex.";
  }
}
