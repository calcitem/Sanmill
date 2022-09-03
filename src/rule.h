// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

// The rule struct manages the various variants of the rules.
struct Rule
{
    const char name[32];

    const char description[512];

    // The number of pieces each player has
    int pieceCount;

    // When a player is reduced to N pieces, his pieces are free to move to any
    // unoccupied point
    int flyPieceCount;

    int piecesAtLeastCount; // Default is 3

    // Add four diagonal lines to the board.
    bool hasDiagonalLines;

    // In the placing phase, the points of removed pieces will no longer be able
    // to place.
    bool hasBannedLocations;

    // The pieces can move in the placing phase.
    bool mayMoveInPlacingPhase;

    // The player who moves second in the placing phrase moves first in the
    // moving phrase.
    bool isDefenderMoveFirst;

    // If a player close more than one mill at once,
    // she will be able to remove the number of mills she closed.
    bool mayRemoveMultiple;

    // By default, players must remove any other pieces first before removing a
    // piece from a formed mill. Enable this option to disable the limitation.
    bool mayRemoveFromMillsAlways;

    // If a player forms the mill in the placing phase, she will remove the
    // opponent's unplaced piece and continue to make a move.
    bool mayOnlyRemoveUnplacedPieceInPlacingPhase;

    // At the end of the placing phase, when the board is full,
    // the side that places first loses the game, otherwise, the game is a draw.
    bool isWhiteLoseButNotDrawWhenBoardFull;

    // The player will lose if his opponent blocks them so that they cannot be
    // moved. Change side to move if this option is disabled.
    bool isLoseButNotChangeSideWhenNoWay;

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

constexpr auto N_RULES = 5;
extern const Rule RULES[N_RULES];
extern Rule rule;
extern bool set_rule(int ruleIdx) noexcept;

#endif /* RULE_H_INCLUDED */
