// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// rule.cpp

#include <cstring>

#include "rule.h"

Rule rule = {"Nine Men's Morris",
             "Nine Men's Morris",
             9,
             3,
             3,
             false,
             MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
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
    {"Nine Men's Morris", "Nine Men's Morris", 9, 3, 3, false,
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard, false,
     false, false, false, false, false, BoardFullAction::firstPlayerLose,
     StalemateAction::endWithStalemateLoss, true, 100, 100, true},
    {"Twelve Men's Morris", "Twelve Men's Morris", 12, 3, 3, true,
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard, false,
     false, false, false, false, false, BoardFullAction::firstPlayerLose,
     StalemateAction::endWithStalemateLoss, true, 100, 100, true},
    {"Dooz", "Dooz", 12, 3, 3, true,
     MillFormationActionInPlacingPhase::
         removeOpponentsPieceFromHandThenOpponentsTurn,
     false, false, false, false, false, false, BoardFullAction::firstPlayerLose,
     StalemateAction::endWithStalemateLoss, true, 100, 100, true},
    {"Morabaraba", "Morabaraba", 12, 3, 3, true,
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard, false,
     false, false, true, false, false, BoardFullAction::firstPlayerLose,
     StalemateAction::endWithStalemateLoss, true, 100, 100, true},
    {"Russian Mill", "Russian Mill", 9, 3, 3, false,
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard, false,
     false, false, false, false, true, BoardFullAction::firstPlayerLose,
     StalemateAction::endWithStalemateLoss, true, 100, 100, true},
    {"Lasker Morris", "Lasker Morris", 10, 3, 3, false,
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard, true,
     false, false, false, false, false, BoardFullAction::firstPlayerLose,
     StalemateAction::endWithStalemateLoss, true, 100, 100, true},
    {"Cheng San Qi", "Cheng San Qi", 9, 3, 3, false,
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard, false,
     false, false, false, false, false, BoardFullAction::firstPlayerLose,
     StalemateAction::endWithStalemateLoss, false, 100, 100, true},
    {"Da San Qi", "Da San Qi", 12, 3, 3, true,
     MillFormationActionInPlacingPhase::markAndDelayRemovingPieces, false, true,
     false, false, true, false, BoardFullAction::firstPlayerLose,
     StalemateAction::endWithStalemateLoss, false, 100, 100, true},
    {"Zhi Qi", "Zhi Qi", 12, 3, 3, true,
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard, false,
     false /* bmf */, false, false, false, false,
     BoardFullAction::firstAndSecondPlayerRemovePiece,
     StalemateAction::removeOpponentsPieceAndMakeNextMove, true, 100, 100,
     true},
    {"El Filja", "El Filja", 12, 3, 3, false,
     MillFormationActionInPlacingPhase::removalBasedOnMillCounts, false, false,
     false, false, true, false,
     BoardFullAction::firstAndSecondPlayerRemovePiece,
     StalemateAction::endWithStalemateLoss, false, 100, 100, true},
    {"Experimental", "Experimental", 12, 3, 3, true,
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard, false,
     true, false, false, true, false,
     BoardFullAction::secondAndFirstPlayerRemovePiece,
     StalemateAction::endWithStalemateLoss, false, 100, 100, true},
};

bool set_rule(int ruleIdx) noexcept
{
    if (ruleIdx < 0 || ruleIdx >= N_RULES) {
        return false;
    }

    std::memset(&rule, 0, sizeof(Rule));
    std::memcpy(&rule, &RULES[ruleIdx], sizeof(Rule));

#ifdef NNUE_GENERATE_TRAINING_DATA
    rule.nMoveRule = 30;
#endif

    return true;
}
