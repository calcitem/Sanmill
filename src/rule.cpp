// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// rule.cpp

#include <cstring>

#include "rule.h"

namespace {

constexpr CaptureRuleConfig kDefaultCaptureRuleConfig {
    false, // enabled
    true,  // onSquareEdges
    true,  // onCrossLines
    true,  // onDiagonalLines
    true,  // inPlacingPhase
    true,  // inMovingPhase
    false  // onlyAvailableWhenOwnPiecesLeq3
};

} // namespace

Rule rule = {
    "Nine Men's Morris", // name
    "Nine Men's Morris", // description
    9,                   // pieceCount
    3,                   // flyPieceCount
    3,                   // piecesAtLeastCount
    false,               // hasDiagonalLines
    MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
    // millFormationActionInPlacingPhase
    false,                                 // mayMoveInPlacingPhase
    false,                                 // isDefenderMoveFirst
    false,                                 // mayRemoveMultiple
    false,                                 // restrictRepeatedMillsFormation
    false,                                 // mayRemoveFromMillsAlways
    false,                                 // oneTimeUseMill
    BoardFullAction::firstPlayerLose,      // boardFullAction
    false,                                 // stopPlacingWhenTwoEmptySquares
    StalemateAction::endWithStalemateLoss, // stalemateAction
    kDefaultCaptureRuleConfig,             // custodianCapture
    kDefaultCaptureRuleConfig,             // interventionCapture
    kDefaultCaptureRuleConfig,             // leapCapture
    true,                                  // mayFly
    100,                                   // nMoveRule
    100,                                   // endgameNMoveRule
    true                                   // threefoldRepetitionRule
};

const Rule RULES[N_RULES] = {
    {                     // Nine Men's Morris
     "Nine Men's Morris", // name
     "Nine Men's Morris", // description
     9,                   // pieceCount
     3,                   // flyPieceCount
     3,                   // piecesAtLeastCount
     false,               // hasDiagonalLines
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
     // millFormationActionInPlacingPhase
     false,                                 // mayMoveInPlacingPhase
     false,                                 // isDefenderMoveFirst
     false,                                 // mayRemoveMultiple
     false,                                 // restrictRepeatedMillsFormation
     false,                                 // mayRemoveFromMillsAlways
     false,                                 // oneTimeUseMill
     BoardFullAction::firstPlayerLose,      // boardFullAction
     false,                                 // stopPlacingWhenTwoEmptySquares
     StalemateAction::endWithStalemateLoss, // stalemateAction
     kDefaultCaptureRuleConfig,             // custodianCapture
     kDefaultCaptureRuleConfig,             // interventionCapture
     kDefaultCaptureRuleConfig,             // leapCapture
     true,                                  // mayFly
     100,                                   // nMoveRule
     100,                                   // endgameNMoveRule
     true},                                 // threefoldRepetitionRule
    {                                       // Twelve Men's Morris
     "Twelve Men's Morris",                 // name
     "Twelve Men's Morris",                 // description
     12,                                    // pieceCount
     3,                                     // flyPieceCount
     3,                                     // piecesAtLeastCount
     true,                                  // hasDiagonalLines
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
     // millFormationActionInPlacingPhase
     false,                                 // mayMoveInPlacingPhase
     false,                                 // isDefenderMoveFirst
     false,                                 // mayRemoveMultiple
     false,                                 // restrictRepeatedMillsFormation
     false,                                 // mayRemoveFromMillsAlways
     false,                                 // oneTimeUseMill
     BoardFullAction::firstPlayerLose,      // boardFullAction
     false,                                 // stopPlacingWhenTwoEmptySquares
     StalemateAction::endWithStalemateLoss, // stalemateAction
     kDefaultCaptureRuleConfig,             // custodianCapture
     kDefaultCaptureRuleConfig,             // interventionCapture
     kDefaultCaptureRuleConfig,             // leapCapture
     true,                                  // mayFly
     100,                                   // nMoveRule
     100,                                   // endgameNMoveRule
     true},                                 // threefoldRepetitionRule
    {                                       // Dooz
     "Dooz",                                // name
     "Dooz",                                // description
     12,                                    // pieceCount
     3,                                     // flyPieceCount
     3,                                     // piecesAtLeastCount
     true,                                  // hasDiagonalLines
     MillFormationActionInPlacingPhase::
         removeOpponentsPieceFromHandThenOpponentsTurn,
     // millFormationActionInPlacingPhase
     false,                                 // mayMoveInPlacingPhase
     false,                                 // isDefenderMoveFirst
     false,                                 // mayRemoveMultiple
     false,                                 // restrictRepeatedMillsFormation
     false,                                 // mayRemoveFromMillsAlways
     false,                                 // oneTimeUseMill
     BoardFullAction::firstPlayerLose,      // boardFullAction
     false,                                 // stopPlacingWhenTwoEmptySquares
     StalemateAction::endWithStalemateLoss, // stalemateAction
     kDefaultCaptureRuleConfig,             // custodianCapture
     kDefaultCaptureRuleConfig,             // interventionCapture
     kDefaultCaptureRuleConfig,             // leapCapture
     true,                                  // mayFly
     100,                                   // nMoveRule
     100,                                   // endgameNMoveRule
     true},                                 // threefoldRepetitionRule
    {                                       // Morabaraba
     "Morabaraba",                          // name
     "Morabaraba",                          // description
     12,                                    // pieceCount
     3,                                     // flyPieceCount
     3,                                     // piecesAtLeastCount
     true,                                  // hasDiagonalLines
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
     // millFormationActionInPlacingPhase
     false,                                 // mayMoveInPlacingPhase
     false,                                 // isDefenderMoveFirst
     true,                                  // mayRemoveMultiple
     false,                                 // restrictRepeatedMillsFormation
     false,                                 // mayRemoveFromMillsAlways
     false,                                 // oneTimeUseMill
     BoardFullAction::firstPlayerLose,      // boardFullAction
     false,                                 // stopPlacingWhenTwoEmptySquares
     StalemateAction::endWithStalemateLoss, // stalemateAction
     kDefaultCaptureRuleConfig,             // custodianCapture
     kDefaultCaptureRuleConfig,             // interventionCapture
     kDefaultCaptureRuleConfig,             // leapCapture
     true,                                  // mayFly
     100,                                   // nMoveRule
     100,                                   // endgameNMoveRule
     true},                                 // threefoldRepetitionRule
    {                                       // Russian Mill
     "Russian Mill",                        // name
     "Russian Mill",                        // description
     9,                                     // pieceCount
     3,                                     // flyPieceCount
     3,                                     // piecesAtLeastCount
     false,                                 // hasDiagonalLines
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
     // millFormationActionInPlacingPhase
     false,                                 // mayMoveInPlacingPhase
     false,                                 // isDefenderMoveFirst
     false,                                 // mayRemoveMultiple
     false,                                 // restrictRepeatedMillsFormation
     false,                                 // mayRemoveFromMillsAlways
     true,                                  // oneTimeUseMill
     BoardFullAction::firstPlayerLose,      // boardFullAction
     false,                                 // stopPlacingWhenTwoEmptySquares
     StalemateAction::endWithStalemateLoss, // stalemateAction
     kDefaultCaptureRuleConfig,             // custodianCapture
     kDefaultCaptureRuleConfig,             // interventionCapture
     kDefaultCaptureRuleConfig,             // leapCapture
     true,                                  // mayFly
     100,                                   // nMoveRule
     100,                                   // endgameNMoveRule
     true},                                 // threefoldRepetitionRule
    {                                       // Lasker Morris
     "Lasker Morris",                       // name
     "Lasker Morris",                       // description
     10,                                    // pieceCount
     3,                                     // flyPieceCount
     3,                                     // piecesAtLeastCount
     false,                                 // hasDiagonalLines
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
     // millFormationActionInPlacingPhase
     true,                                  // mayMoveInPlacingPhase
     false,                                 // isDefenderMoveFirst
     false,                                 // mayRemoveMultiple
     false,                                 // restrictRepeatedMillsFormation
     false,                                 // mayRemoveFromMillsAlways
     false,                                 // oneTimeUseMill
     BoardFullAction::firstPlayerLose,      // boardFullAction
     false,                                 // stopPlacingWhenTwoEmptySquares
     StalemateAction::endWithStalemateLoss, // stalemateAction
     kDefaultCaptureRuleConfig,             // custodianCapture
     kDefaultCaptureRuleConfig,             // interventionCapture
     kDefaultCaptureRuleConfig,             // leapCapture
     true,                                  // mayFly
     100,                                   // nMoveRule
     100,                                   // endgameNMoveRule
     true},                                 // threefoldRepetitionRule
    {                                       // Cheng San Qi
     "Cheng San Qi",                        // name
     "Cheng San Qi",                        // description
     9,                                     // pieceCount
     3,                                     // flyPieceCount
     3,                                     // piecesAtLeastCount
     false,                                 // hasDiagonalLines
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
     // millFormationActionInPlacingPhase
     false,                                 // mayMoveInPlacingPhase
     false,                                 // isDefenderMoveFirst
     false,                                 // mayRemoveMultiple
     false,                                 // restrictRepeatedMillsFormation
     false,                                 // mayRemoveFromMillsAlways
     false,                                 // oneTimeUseMill
     BoardFullAction::firstPlayerLose,      // boardFullAction
     false,                                 // stopPlacingWhenTwoEmptySquares
     StalemateAction::endWithStalemateLoss, // stalemateAction
     kDefaultCaptureRuleConfig,             // custodianCapture
     kDefaultCaptureRuleConfig,             // interventionCapture
     kDefaultCaptureRuleConfig,             // leapCapture
     false,                                 // mayFly
     100,                                   // nMoveRule
     100,                                   // endgameNMoveRule
     true},                                 // threefoldRepetitionRule
    {                                       // Da San Qi
     "Da San Qi",                           // name
     "Da San Qi",                           // description
     12,                                    // pieceCount
     3,                                     // flyPieceCount
     3,                                     // piecesAtLeastCount
     true,                                  // hasDiagonalLines
     MillFormationActionInPlacingPhase::markAndDelayRemovingPieces,
     // millFormationActionInPlacingPhase
     false,                                 // mayMoveInPlacingPhase
     true,                                  // isDefenderMoveFirst
     false,                                 // mayRemoveMultiple
     false,                                 // restrictRepeatedMillsFormation
     true,                                  // mayRemoveFromMillsAlways
     false,                                 // oneTimeUseMill
     BoardFullAction::firstPlayerLose,      // boardFullAction
     false,                                 // stopPlacingWhenTwoEmptySquares
     StalemateAction::endWithStalemateLoss, // stalemateAction
     kDefaultCaptureRuleConfig,             // custodianCapture
     kDefaultCaptureRuleConfig,             // interventionCapture
     kDefaultCaptureRuleConfig,             // leapCapture
     false,                                 // mayFly
     100,                                   // nMoveRule
     100,                                   // endgameNMoveRule
     true},                                 // threefoldRepetitionRule
    {                                       // Zhi Qi
     "Zhi Qi",                              // name
     "Zhi Qi",                              // description
     12,                                    // pieceCount
     3,                                     // flyPieceCount
     3,                                     // piecesAtLeastCount
     true,                                  // hasDiagonalLines
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
     // millFormationActionInPlacingPhase
     false, // mayMoveInPlacingPhase
     false, // isDefenderMoveFirst
     false, // mayRemoveMultiple
     false, // restrictRepeatedMillsFormation
     false, // mayRemoveFromMillsAlways
     false, // oneTimeUseMill
     BoardFullAction::firstAndSecondPlayerRemovePiece, // boardFullAction
     false, // stopPlacingWhenTwoEmptySquares
     StalemateAction::removeOpponentsPieceAndMakeNextMove, // stalemateAction
     kDefaultCaptureRuleConfig,                            // custodianCapture
     kDefaultCaptureRuleConfig, // interventionCapture
     kDefaultCaptureRuleConfig, // leapCapture
     true,                      // mayFly
     100,                       // nMoveRule
     100,                       // endgameNMoveRule
     true},                     // threefoldRepetitionRule
    {                           // El Filja
     "El Filja",                // name
     "El Filja",                // description
     12,                        // pieceCount
     3,                         // flyPieceCount
     3,                         // piecesAtLeastCount
     false,                     // hasDiagonalLines
     MillFormationActionInPlacingPhase::
         removalBasedOnMillCounts, // millFormationActionInPlacingPhase
     false,                        // mayMoveInPlacingPhase
     false,                        // isDefenderMoveFirst
     false,                        // mayRemoveMultiple
     false,                        // restrictRepeatedMillsFormation
     true,                         // mayRemoveFromMillsAlways
     false,                        // oneTimeUseMill
     BoardFullAction::firstAndSecondPlayerRemovePiece, // boardFullAction
     false,                                 // stopPlacingWhenTwoEmptySquares
     StalemateAction::endWithStalemateLoss, // stalemateAction
     kDefaultCaptureRuleConfig,             // custodianCapture
     kDefaultCaptureRuleConfig,             // interventionCapture
     kDefaultCaptureRuleConfig,             // leapCapture
     false,                                 // mayFly
     100,                                   // nMoveRule
     100,                                   // endgameNMoveRule
     true},                                 // threefoldRepetitionRule
    {                                       // Experimental
     "Experimental",                        // name
     "Experimental",                        // description
     12,                                    // pieceCount
     3,                                     // flyPieceCount
     3,                                     // piecesAtLeastCount
     true,                                  // hasDiagonalLines
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
     // millFormationActionInPlacingPhase
     false, // mayMoveInPlacingPhase
     true,  // isDefenderMoveFirst
     false, // mayRemoveMultiple
     false, // restrictRepeatedMillsFormation
     true,  // mayRemoveFromMillsAlways
     false, // oneTimeUseMill
     BoardFullAction::secondAndFirstPlayerRemovePiece, // boardFullAction
     false,                                 // stopPlacingWhenTwoEmptySquares
     StalemateAction::endWithStalemateLoss, // stalemateAction
     kDefaultCaptureRuleConfig,             // custodianCapture
     kDefaultCaptureRuleConfig,             // interventionCapture
     kDefaultCaptureRuleConfig,             // leapCapture
     false,                                 // mayFly
     100,                                   // nMoveRule
     100,                                   // endgameNMoveRule
     true},                                 // threefoldRepetitionRule
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
