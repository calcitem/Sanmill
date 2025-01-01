// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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

#ifndef RULE_H_INCLUDED
#define RULE_H_INCLUDED

#include "types.h"

enum class MillFormationActionInPlacingPhase {
    removeOpponentsPieceFromBoard = 0,
    removeOpponentsPieceFromHandThenOpponentsTurn = 1,
    removeOpponentsPieceFromHandThenYourTurn = 2,
    opponentRemovesOwnPiece = 3,
    markAndDelayRemovingPieces = 4,
    removalBasedOnMillCounts = 5,
};

enum class BoardFullAction {
    firstPlayerLose = 0,
    firstAndSecondPlayerRemovePiece = 1,
    secondAndFirstPlayerRemovePiece = 2,
    sideToMoveRemovePiece = 3,
    agreeToDraw = 4,
};

enum class StalemateAction {
    endWithStalemateLoss = 0,
    changeSideToMove = 1,
    removeOpponentsPieceAndMakeNextMove = 2,
    removeOpponentsPieceAndChangeSideToMove = 3,
    endWithStalemateDraw = 4,
};

// The rule struct manages the various variants of the rules.
struct Rule
{
    char name[32];

    char description[512];

    // The number of pieces each player has
    int pieceCount;

    // When a player is reduced to N pieces, his pieces are free to move to any
    // unoccupied point
    int flyPieceCount;

    int piecesAtLeastCount; // Default is 3

    // Add four diagonal lines to the board.
    bool hasDiagonalLines;

    // The actions that can be taken when forming mills during the placing
    // phase.
    MillFormationActionInPlacingPhase millFormationActionInPlacingPhase;

    // The pieces can move in the placing phase.
    bool mayMoveInPlacingPhase;

    // The player who moves second in the placing phrase moves first in the
    // moving phrase.
    bool isDefenderMoveFirst;

    // If a player close more than one mill at once,
    // she will be able to remove the number of mills she closed.
    bool mayRemoveMultiple;

    // This rule prevents a player from moving a piece back to its original
    // position to immediately reform a mill, if the piece was just used to form
    // a mill in the previous turn.
    bool restrictRepeatedMillsFormation;

    // By default, players must remove any other pieces first before removing a
    // piece from a formed mill. Enable this option to disable the limitation.
    bool mayRemoveFromMillsAlways;

    // Each mill can remove an opponent's piece only once. You can reform it
    // again, but it cannot be used for additional removals.
    bool oneTimeUseMill;

    // At the end of the placing phase, before the moving phase begins,
    // the action follows if the board is full of pieces.
    BoardFullAction boardFullAction;

    // What action follows when no piece can be moved?
    StalemateAction stalemateAction;

    // Player may fly if he is down to three or four (configurable) pieces.
    // If a player has only three or four (configurable) pieces left,
    // she is allowed to move the piece to any free point.
    bool mayFly;

    // The N-move rule in Mill states that if no remove has been made in the
    // last N moves.
    unsigned int nMoveRule;

    // If either player has only three pieces and neither player removes a piece
    // within a specific moves, the game is drawn.
    unsigned int endgameNMoveRule;

    // The threefold repetition rule (also known as repetition of position)
    // states that the game is drawn if the same position occurs three times.
    bool threefoldRepetitionRule;
};

constexpr auto N_RULES = 11;
extern const Rule RULES[N_RULES];
extern Rule rule;
extern bool set_rule(int ruleIdx) noexcept;

#endif /* RULE_H_INCLUDED */
