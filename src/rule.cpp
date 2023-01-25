// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

#include <cstring>

#include "rule.h"

Rule rule = {"Nine Men's Morris",
             "Nine Men's Morris",
             9,
             3,
             3,
             false,
             false,
             false,
             false,
             false,
             false,
             false,
             BoardFullAction::firstPlayerLose,
             StalemateAction::endWithStalemateLoss,
             true,
             100,
             100,
             true};

const Rule RULES[N_RULES] = {
    {"Nine Men's Morris", "Nine Men's Morris", 9, 3, 3, false, false, false,
     false, false, false, false, BoardFullAction::firstPlayerLose,
     StalemateAction::endWithStalemateLoss, true, 100, 100, true},
    {"Twelve Men's morris", "Twelve Men's Morris", 12, 3, 3, true, false, false,
     false, false, false, false, BoardFullAction::firstPlayerLose,
     StalemateAction::endWithStalemateLoss, true, 100, 100, true},
    {"Lasker Morris (WIP)", "Lasker Morris", 10, 3, 3, false, false, true,
     false, false, false, false, BoardFullAction::firstPlayerLose,
     StalemateAction::endWithStalemateLoss, true, 100, 100, true},
    {"Cheng San Qi", "Cheng San Qi", 9, 3, 3, false, false, false, false, false,
     false, false, BoardFullAction::firstPlayerLose,
     StalemateAction::endWithStalemateLoss, false, 100, 100, true},
    {"Da San Qi", "Da San Qi", 12, 3, 3, true, true, false, true, false, true,
     false, BoardFullAction::firstPlayerLose,
     StalemateAction::endWithStalemateLoss, false, 100, 100, true},
    {"Zhi Qi", "Zhi Qi", 12, 3, 3, true, false, false, false /* bmf */, false,
     false, false, BoardFullAction::firstAndSecondPlayerRemovePiece,
     StalemateAction::removeOpponentsPieceAndMakeNextMove, true, 100, 100,
     true},
    {"Experimental", "Experimental", 12, 3, 3, true, true, false, true, false,
     true, false, BoardFullAction::secondAndFirstPlayerRemovePiece,
     StalemateAction::endWithStalemateLoss, false, 100, 100, true},
};

bool set_rule(int ruleIdx) noexcept
{
    if (ruleIdx <= 0 || ruleIdx >= N_RULES) {
        return false;
    }

    std::memset(&rule, 0, sizeof(Rule));
    std::memcpy(&rule, &RULES[ruleIdx], sizeof(Rule));

#ifdef NNUE_GENERATE_TRAINING_DATA
    rule.nMoveRule = 30;
#endif

    return true;
}
