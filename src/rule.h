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

struct Rule
{
    const char name[32];

    const char description[512];

    int nTotalPiecesEachSide;   // 9 or 12

    int piecesAtLeastCount; // Default is 3

    bool hasObliqueLines;

    bool hasBannedLocations;

    bool isDefenderMoveFirst;

    bool allowRemoveMultiPiecesWhenCloseMultiMill;

    bool allowRemovePieceInMill;

    bool isBlackLoseButNotDrawWhenBoardFull;

    bool isLoseButNotChangeSideWhenNoWay;

    // Specifies if jumps are allowed when a player remains with three pieces on the board.
    bool flyingAllowed;

    int maxStepsLedToDraw;
};

#define N_RULES 4
extern const struct Rule RULES[N_RULES];
extern struct Rule rule;
extern bool set_rule(int ruleIdx);

#endif /* RULE_H */
