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

#ifndef RULE_H
#define RULE_H

#include "types.h"

// The rule struct manages the various variants of the rules.
struct Rule
{
    const char name[32];

    const char description[512];

    // The number of pieces each player has
    int piecesCount;

    int piecesAtLeastCount; // Default is 3

    // Add four diagonal lines to the board.
    bool hasDiagonalLines;

    // In the placing phase, the points of removed pieces will no longer be able to place.
    bool hasBannedLocations;

    // The player who moves second in the placing phrase moves first in the moving phrase.
    bool isDefenderMoveFirst;

    // If a player close more than one mill at once,
    // she will be able to remove the number of mills she closed.
    bool mayRemoveMultiple;

    // By default, players must remove any other pieces first before removing a piece from a formed mill.
    // Enable this option to disable the limitation.
    bool mayRemoveFromMillsAlways;

    // At the end of the placing phase, when the board is full,
    // the side that places first loses the game, otherwise, the game is a draw.
    bool isBlackLoseButNotDrawWhenBoardFull;

    // The player will lose if his opponent blocks them so that they cannot be moved.
    // Change side to move if this option is disabled.
    bool isLoseButNotChangeSideWhenNoWay;

    // Player may fly if he is down to three pieces.
    bool mayFly;

    // If a player has only three pieces left,
    // she is allowed to move the piece to any free point.
    size_t maxStepsLedToDraw;
};

#define N_RULES 4
extern const struct Rule RULES[N_RULES];
extern struct Rule rule;
extern bool set_rule(int ruleIdx) noexcept;

#endif /* RULE_H */
