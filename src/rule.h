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

    // Number of pieces each player has at the beginning.
    int piecesCount;

    int piecesAtLeastCount; // Default is 3

    bool hasObliqueLines;

    bool hasBannedLocations;

    bool isDefenderMoveFirst;

    // When closing more than one mill at once, may also take several opponent pieces.
    bool mayTakeMultiple;

    // May take from mills even if there are other pieces available.
    bool mayTakeFromMillsAlways;

    bool isBlackLoseButNotDrawWhenBoardFull;

    bool isLoseButNotChangeSideWhenNoWay;

    // Player may fly if he is down to three pieces.
    bool mayFly;

    int maxStepsLedToDraw;
};

#define N_RULES 4
extern const struct Rule RULES[N_RULES];
extern struct Rule rule;
extern bool set_rule(int ruleIdx);

#endif /* RULE_H */
