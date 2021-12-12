/*********************************************************************
    MiniMaxAI.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "miniMaxAI.h"

//-----------------------------------------------------------------------------
// MiniMaxAI()
// MiniMaxAI class constructor
//-----------------------------------------------------------------------------
MiniMaxAI::MiniMaxAI()
{
    depthOfFullTree = 0;

    field = nullptr;
    currentValue = 0.0f;
    gameHasFinished = false;
    ownId = 0;
    curSearchDepth = 0;
    idPossibilities = nullptr;
    oldStates = nullptr;
    possibilities = nullptr;
}

//-----------------------------------------------------------------------------
// ~MiniMaxAI()
// MiniMaxAI class destructor
//-----------------------------------------------------------------------------
MiniMaxAI::~MiniMaxAI() { }

//-----------------------------------------------------------------------------
// play()
//
//-----------------------------------------------------------------------------
void MiniMaxAI::play(fieldStruct *theField, unsigned int *pushFrom,
                     unsigned int *pushTo)
{
    // globals
    field = theField;
    ownId = field->curPlayer->id;
    curSearchDepth = 0;
    unsigned int bestChoice;
    unsigned int searchDepth;

    // automatic depth
    if (depthOfFullTree == 0) {
        if (theField->settingPhase)
            searchDepth = 5;
        else if (theField->curPlayer->pieceCount <= 4)
            searchDepth = 7;
        else if (theField->oppPlayer->pieceCount <= 4)
            searchDepth = 7;
        else
            searchDepth = 7;
    } else {
        searchDepth = depthOfFullTree;
    }

    // Inform user about progress
    cout << "MiniMaxAI is thinking with a depth of " << searchDepth
         << " steps!\n\n\n";

    // reserve memory
    possibilities = new Possibility[searchDepth + 1];
    oldStates = new Backup[searchDepth + 1];
    idPossibilities = new unsigned int[(searchDepth + 1) * POSIBILE_MOVE_COUNT_MAX];

    // start the miniMax-algorithmn
    Possibility *rootPossibilities = (Possibility *)getBestChoice(
        searchDepth, &bestChoice, POSIBILE_MOVE_COUNT_MAX);

    // decode the best choice
    if (field->pieceMustBeRemoved) {
        *pushFrom = bestChoice;
        *pushTo = 0;
    } else if (field->settingPhase) {
        *pushFrom = 0;
        *pushTo = bestChoice;
    } else {
        *pushFrom = rootPossibilities->from[bestChoice];
        *pushTo = rootPossibilities->to[bestChoice];
    }

    // release memory
    delete[] oldStates;
    delete[] idPossibilities;
    delete[] possibilities;

    // release memory
    field = nullptr;
}

//-----------------------------------------------------------------------------
// setSearchDepth()
//
//-----------------------------------------------------------------------------
void MiniMaxAI::setSearchDepth(unsigned int depth)
{
    depthOfFullTree = depth;
}

//-----------------------------------------------------------------------------
// prepareBestChoiceCalculation()
//
//-----------------------------------------------------------------------------
void MiniMaxAI::prepareBestChoiceCalculation()
{
    // calculate current value
    currentValue = 0;
    gameHasFinished = false;
}

//-----------------------------------------------------------------------------
// getPossSettingPhase()
//
//-----------------------------------------------------------------------------
unsigned int *MiniMaxAI::getPossSettingPhase(unsigned int *possibilityCount,
                                             void **pPossibilities)
{
    // locals
    unsigned int i;
    unsigned int *idPossibility =
        &idPossibilities[curSearchDepth * POSIBILE_MOVE_COUNT_MAX];

    // possibilities with cut off
    for ((*possibilityCount) = 0, i = 0; i < SQUARE_NB; i++) {
        // move possible ?
        if (field->board[i] == field->squareIsFree) {
            idPossibility[*possibilityCount] = i;
            (*possibilityCount)++;
        }
    }

    // possibility code is simple
    *pPossibilities = nullptr;

    return idPossibility;
}

//-----------------------------------------------------------------------------
// getPossNormalMove()
//
//-----------------------------------------------------------------------------
unsigned int *MiniMaxAI::getPossNormalMove(unsigned int *possibilityCount,
                                           void **pPossibilities)
{
    // locals
    unsigned int from, to, dir;
    unsigned int *idPossibility =
        &idPossibilities[curSearchDepth * POSIBILE_MOVE_COUNT_MAX];
    Possibility *possibility = &possibilities[curSearchDepth];

    // if he is not allowed to spring
    if (field->curPlayer->pieceCount > 3) {
        for ((*possibilityCount) = 0, from = 0; from < SQUARE_NB;
             from++) {
            for (dir = 0; dir < 4; dir++) {
                // destination
                to = field->connectedSquare[from][dir];

                // move possible ?
                if (to < SQUARE_NB &&
                    field->board[from] == field->curPlayer->id &&
                    field->board[to] == field->squareIsFree) {
                    // piece is moveable
                    idPossibility[*possibilityCount] = *possibilityCount;
                    possibility->from[*possibilityCount] = from;
                    possibility->to[*possibilityCount] = to;
                    (*possibilityCount)++;

                    // current player is allowed to spring
                }
            }
        }
    } else {
        for ((*possibilityCount) = 0, from = 0; from < SQUARE_NB;
             from++) {
            for (to = 0; to < SQUARE_NB; to++) {
                // move possible ?
                if (field->board[from] == field->curPlayer->id &&
                    field->board[to] == field->squareIsFree &&
                    *possibilityCount < POSIBILE_MOVE_COUNT_MAX) {
                    // piece is moveable
                    idPossibility[*possibilityCount] = *possibilityCount;
                    possibility->from[*possibilityCount] = from;
                    possibility->to[*possibilityCount] = to;
                    (*possibilityCount)++;
                }
            }
        }
    }

    // pass possibilities
    *pPossibilities = (void *)possibility;

    return idPossibility;
}

//-----------------------------------------------------------------------------
// getPossPieceRemove()
//
//-----------------------------------------------------------------------------
unsigned int *MiniMaxAI::getPossPieceRemove(unsigned int *possibilityCount,
                                            void **pPossibilities)
{
    // locals
    unsigned int i;
    unsigned int *idPossibility =
        &idPossibilities[curSearchDepth * POSIBILE_MOVE_COUNT_MAX];

    // possibilities with cut off
    for ((*possibilityCount) = 0, i = 0; i < SQUARE_NB; i++) {
        // move possible ?
        if (field->board[i] == field->oppPlayer->id &&
            !field->piecePartOfMill[i]) {
            idPossibility[*possibilityCount] = i;
            (*possibilityCount)++;
        }
    }

    // possibility code is simple
    *pPossibilities = nullptr;

    return idPossibility;
}

//-----------------------------------------------------------------------------
// getPossibilities()
//
//-----------------------------------------------------------------------------
unsigned int *MiniMaxAI::getPossibilities(unsigned int threadNo,
                                          unsigned int *possibilityCount,
                                          bool *opponentsMove,
                                          void **pPossibilities)
{
    // set opponentsMove
    *opponentsMove = (field->curPlayer->id == ownId) ? false : true;

    // When game has ended of course nothing happens any more
    if (gameHasFinished) {
        *possibilityCount = 0;
        return 0;
        // look what is to do
    } else {
        if (field->pieceMustBeRemoved)
            return getPossPieceRemove(possibilityCount, pPossibilities);
        else if (field->settingPhase)
            return getPossSettingPhase(possibilityCount, pPossibilities);
        else
            return getPossNormalMove(possibilityCount, pPossibilities);
    }
}

//-----------------------------------------------------------------------------
// getValueOfSituation()
//
//-----------------------------------------------------------------------------
void MiniMaxAI::getValueOfSituation(unsigned int threadNo, float &floatValue,
                                    TwoBit &shortValue)
{
    floatValue = currentValue;
    shortValue = 0;
}

//-----------------------------------------------------------------------------
// deletePossibilities()
//
//-----------------------------------------------------------------------------
void MiniMaxAI::deletePossibilities(unsigned int threadNo, void *pPossibilities)
{ }

//-----------------------------------------------------------------------------
// undo()
//
//-----------------------------------------------------------------------------
void MiniMaxAI::undo(unsigned int threadNo, unsigned int idPossibility,
                     bool opponentsMove, void *pBackup, void *pPossibilities)
{
    // locals
    Backup *oldState = (Backup *)pBackup;

    // reset old value
    currentValue = oldState->value;
    gameHasFinished = oldState->gameHasFinished;
    curSearchDepth--;

    field->curPlayer = oldState->curPlayer;
    field->oppPlayer = oldState->oppPlayer;
    field->curPlayer->pieceCount = oldState->curPieceCount;
    field->oppPlayer->pieceCount = oldState->oppPieceCount;
    field->curPlayer->removedPiecesCount = oldState->curMissPieces;
    field->oppPlayer->removedPiecesCount = oldState->oppMissPieces;
    field->curPlayer->possibleMovesCount = oldState->curPosMoves;
    field->oppPlayer->possibleMovesCount = oldState->oppPosMoves;
    field->settingPhase = oldState->settingPhase;
    field->piecesSet = oldState->piecesSet;
    field->pieceMustBeRemoved = oldState->pieceMustBeRemoved;
    field->board[oldState->from] = oldState->fieldFrom;
    field->board[oldState->to] = oldState->fieldTo;

    // very expensive
    for (int i = 0; i < SQUARE_NB; i++) {
        field->piecePartOfMill[i] = oldState->piecePartOfMill[i];
        field->warnings[i] = oldState->warnings[i];
    }
}

//-----------------------------------------------------------------------------
// setWarning()
//
//-----------------------------------------------------------------------------
inline void MiniMaxAI::setWarning(unsigned int pieceOne, unsigned int pieceTwo,
                                  unsigned int pieceThree)
{
    // if all 3 fields are occupied by current player than he closed a mill
    if (field->board[pieceOne] == field->curPlayer->id &&
        field->board[pieceTwo] == field->curPlayer->id &&
        field->board[pieceThree] == field->curPlayer->id) {
        field->piecePartOfMill[pieceOne]++;
        field->piecePartOfMill[pieceTwo]++;
        field->piecePartOfMill[pieceThree]++;
        field->pieceMustBeRemoved = 1;
    }

    // is a mill destroyed ?
    if (field->board[pieceOne] == field->squareIsFree &&
        field->piecePartOfMill[pieceOne] && field->piecePartOfMill[pieceTwo] &&
        field->piecePartOfMill[pieceThree]) {
        field->piecePartOfMill[pieceOne]--;
        field->piecePartOfMill[pieceTwo]--;
        field->piecePartOfMill[pieceThree]--;
    }

    // piece was set
    if (field->board[pieceOne] == field->curPlayer->id) {
        // a warning was destroyed
        field->warnings[pieceOne] = field->noWarning;

        // a warning is created
        if (field->board[pieceTwo] == field->curPlayer->id &&
            field->board[pieceThree] == field->squareIsFree)
            field->warnings[pieceThree] |= field->curPlayer->warning;
        if (field->board[pieceThree] == field->curPlayer->id &&
            field->board[pieceTwo] == field->squareIsFree)
            field->warnings[pieceTwo] |= field->curPlayer->warning;

        // piece was removed
    } else if (field->board[pieceOne] == field->squareIsFree) {
        // a warning is created
        if (field->board[pieceTwo] == field->curPlayer->id &&
            field->board[pieceThree] == field->curPlayer->id)
            field->warnings[pieceOne] |= field->curPlayer->warning;
        if (field->board[pieceTwo] == field->oppPlayer->id &&
            field->board[pieceThree] == field->oppPlayer->id)
            field->warnings[pieceOne] |= field->oppPlayer->warning;

        // a warning is destroyed
        if (field->warnings[pieceTwo] &&
            field->board[pieceThree] != field->squareIsFree) {
            // reset warning if necessary
            if (field->board[field->neighbour[pieceTwo][0][0]] ==
                    field->curPlayer->id &&
                field->board[field->neighbour[pieceTwo][0][1]] ==
                    field->curPlayer->id)
                field->warnings[pieceTwo] = field->curPlayer->warning;
            else if (field->board[field->neighbour[pieceTwo][1][0]] ==
                         field->curPlayer->id &&
                     field->board[field->neighbour[pieceTwo][1][1]] ==
                         field->curPlayer->id)
                field->warnings[pieceTwo] = field->curPlayer->warning;
            else if (field->board[field->neighbour[pieceTwo][0][0]] ==
                         field->oppPlayer->id &&
                     field->board[field->neighbour[pieceTwo][0][1]] ==
                         field->oppPlayer->id)
                field->warnings[pieceTwo] = field->oppPlayer->warning;
            else if (field->board[field->neighbour[pieceTwo][1][0]] ==
                         field->oppPlayer->id &&
                     field->board[field->neighbour[pieceTwo][1][1]] ==
                         field->oppPlayer->id)
                field->warnings[pieceTwo] = field->oppPlayer->warning;
            else
                field->warnings[pieceTwo] = field->noWarning;
        } else if (field->warnings[pieceThree] &&
                   field->board[pieceTwo] != field->squareIsFree) {
            // reset warning if necessary
            if (field->board[field->neighbour[pieceThree][0][0]] ==
                    field->curPlayer->id &&
                field->board[field->neighbour[pieceThree][0][1]] ==
                    field->curPlayer->id)
                field->warnings[pieceThree] = field->curPlayer->warning;
            else if (field->board[field->neighbour[pieceThree][1][0]] ==
                         field->curPlayer->id &&
                     field->board[field->neighbour[pieceThree][1][1]] ==
                         field->curPlayer->id)
                field->warnings[pieceThree] = field->curPlayer->warning;
            else if (field->board[field->neighbour[pieceThree][0][0]] ==
                         field->oppPlayer->id &&
                     field->board[field->neighbour[pieceThree][0][1]] ==
                         field->oppPlayer->id)
                field->warnings[pieceThree] = field->oppPlayer->warning;
            else if (field->board[field->neighbour[pieceThree][1][0]] ==
                         field->oppPlayer->id &&
                     field->board[field->neighbour[pieceThree][1][1]] ==
                         field->oppPlayer->id)
                field->warnings[pieceThree] = field->oppPlayer->warning;
            else
                field->warnings[pieceThree] = field->noWarning;
        }
    }
}

//-----------------------------------------------------------------------------
// updateWarning()
//
//-----------------------------------------------------------------------------
inline void MiniMaxAI::updateWarning(unsigned int firstPiece,
                                     unsigned int secondPiece)
{
    // set warnings
    if (firstPiece < SQUARE_NB)
        setWarning(firstPiece, field->neighbour[firstPiece][0][0],
                   field->neighbour[firstPiece][0][1]);
    if (firstPiece < SQUARE_NB)
        setWarning(firstPiece, field->neighbour[firstPiece][1][0],
                   field->neighbour[firstPiece][1][1]);

    if (secondPiece < SQUARE_NB)
        setWarning(secondPiece, field->neighbour[secondPiece][0][0],
                   field->neighbour[secondPiece][0][1]);
    if (secondPiece < SQUARE_NB)
        setWarning(secondPiece, field->neighbour[secondPiece][1][0],
                   field->neighbour[secondPiece][1][1]);

    // no piece must be removed if each belongs to a mill
    unsigned int i;
    bool atLeastOnePieceRemoveAble = false;

    if (field->pieceMustBeRemoved) {
        for (i = 0; i < SQUARE_NB; i++) {
            if (field->piecePartOfMill[i] == 0 &&
                field->board[i] == field->oppPlayer->id) {
                atLeastOnePieceRemoveAble = true;
                break;
            }
        }
    }

    if (!atLeastOnePieceRemoveAble)
        field->pieceMustBeRemoved = 0;
}

//-----------------------------------------------------------------------------
// updatePossibleMoves()
//
//-----------------------------------------------------------------------------
inline void MiniMaxAI::updatePossibleMoves(unsigned int piece,
                                           Player *pieceOwner,
                                           bool pieceRemoved,
                                           unsigned int ignorePiece)
{
    // locals
    unsigned int neighbor, direction;

    // look into every direction
    for (direction = 0; direction < 4; direction++) {
        neighbor = field->connectedSquare[piece][direction];

        // neighbor must exist
        if (neighbor < SQUARE_NB) {
            // relevant when moving from one square to another connected square
            if (ignorePiece == neighbor)
                continue;

            // if there is no neighbour piece than it only affects the actual
            // piece
            if (field->board[neighbor] == field->squareIsFree) {
                if (pieceRemoved)
                    pieceOwner->possibleMovesCount--;
                else
                    pieceOwner->possibleMovesCount++;

                // if there is a neighbour piece than it effects only this one
            } else if (field->board[neighbor] == field->curPlayer->id) {
                if (pieceRemoved)
                    field->curPlayer->possibleMovesCount++;
                else
                    field->curPlayer->possibleMovesCount--;
            } else {
                if (pieceRemoved)
                    field->oppPlayer->possibleMovesCount++;
                else
                    field->oppPlayer->possibleMovesCount--;
            }
        }
    }

    // only 3 pieces resting
    if (field->curPlayer->pieceCount <= 3 && !field->settingPhase)
        field->curPlayer->possibleMovesCount = field->curPlayer->pieceCount *
                                             (SQUARE_NB -
                                              field->curPlayer->pieceCount -
                                              field->oppPlayer->pieceCount);
    if (field->oppPlayer->pieceCount <= 3 && !field->settingPhase)
        field->oppPlayer->possibleMovesCount = field->oppPlayer->pieceCount *
                                             (SQUARE_NB -
                                              field->curPlayer->pieceCount -
                                              field->oppPlayer->pieceCount);
}

//-----------------------------------------------------------------------------
// setPiece()
//
//-----------------------------------------------------------------------------
inline void MiniMaxAI::setPiece(unsigned int to, Backup *backup)
{
    // backup
    backup->from = SQUARE_NB;
    backup->to = to;
    backup->fieldFrom = SQUARE_NB;
    backup->fieldTo = field->board[to];

    // set piece into board
    field->board[to] = field->curPlayer->id;
    field->curPlayer->pieceCount++;
    field->piecesSet++;

    // setting phase finished ?
    if (field->piecesSet == 18)
        field->settingPhase = false;

    // update possible moves
    updatePossibleMoves(to, field->curPlayer, false, SQUARE_NB);

    // update warnings
    updateWarning(to, SQUARE_NB);
}

//-----------------------------------------------------------------------------
// normalMove()
//
//-----------------------------------------------------------------------------
inline void MiniMaxAI::normalMove(unsigned int from, unsigned int to,
                                  Backup *backup)
{
    // backup
    backup->from = from;
    backup->to = to;
    backup->fieldFrom = field->board[from];
    backup->fieldTo = field->board[to];

    // set piece into board
    field->board[from] = field->squareIsFree;
    field->board[to] = field->curPlayer->id;

    // update possible moves
    updatePossibleMoves(from, field->curPlayer, true, to);
    updatePossibleMoves(to, field->curPlayer, false, from);

    // update warnings
    updateWarning(from, to);
}

//-----------------------------------------------------------------------------
// removePiece()
//
//-----------------------------------------------------------------------------
inline void MiniMaxAI::removePiece(unsigned int from, Backup *backup)
{
    // backup
    backup->from = from;
    backup->to = SQUARE_NB;
    backup->fieldFrom = field->board[from];
    backup->fieldTo = SQUARE_NB;

    // remove piece
    field->board[from] = field->squareIsFree;
    field->oppPlayer->pieceCount--;
    field->oppPlayer->removedPiecesCount++;
    field->pieceMustBeRemoved--;

    // update possible moves
    updatePossibleMoves(from, field->oppPlayer, true, SQUARE_NB);

    // update warnings
    updateWarning(from, SQUARE_NB);

    // end of game ?
    if ((field->oppPlayer->pieceCount < 3) && (!field->settingPhase))
        gameHasFinished = true;
}

//-----------------------------------------------------------------------------
// move()
//
//-----------------------------------------------------------------------------
void MiniMaxAI::move(unsigned int threadNo, unsigned int idPossibility,
                     bool opponentsMove, void **pBackup, void *pPossibilities)
{
    // locals
    Backup *oldState = &oldStates[curSearchDepth];
    Possibility *tmpPossibility = (Possibility *)pPossibilities;
    Player *tmpPlayer;
    unsigned int i;

    // calculate place of piece
    *pBackup = (void *)oldState;
    oldState->value = currentValue;
    oldState->gameHasFinished = gameHasFinished;
    oldState->curPlayer = field->curPlayer;
    oldState->oppPlayer = field->oppPlayer;
    oldState->curPieceCount = field->curPlayer->pieceCount;
    oldState->oppPieceCount = field->oppPlayer->pieceCount;
    oldState->curPosMoves = field->curPlayer->possibleMovesCount;
    oldState->oppPosMoves = field->oppPlayer->possibleMovesCount;
    oldState->curMissPieces = field->curPlayer->removedPiecesCount;
    oldState->oppMissPieces = field->oppPlayer->removedPiecesCount;
    oldState->settingPhase = field->settingPhase;
    oldState->piecesSet = field->piecesSet;
    oldState->pieceMustBeRemoved = field->pieceMustBeRemoved;
    curSearchDepth++;

    // very expensive
    for (i = 0; i < SQUARE_NB; i++) {
        oldState->piecePartOfMill[i] = field->piecePartOfMill[i];
        oldState->warnings[i] = field->warnings[i];
    }

    // move
    if (field->pieceMustBeRemoved) {
        removePiece(idPossibility, oldState);
    } else if (field->settingPhase) {
        setPiece(idPossibility, oldState);
    } else {
        normalMove(tmpPossibility->from[idPossibility],
                   tmpPossibility->to[idPossibility], oldState);
    }

    // when opponent is unable to move than current player has won
    if ((!field->oppPlayer->possibleMovesCount) && (!field->settingPhase) &&
        (!field->pieceMustBeRemoved) && (field->oppPlayer->pieceCount > 3))
        gameHasFinished = true;

    // calc value
    if (!opponentsMove)
        currentValue = (float)field->oppPlayer->removedPiecesCount -
                       field->curPlayer->removedPiecesCount +
                       field->pieceMustBeRemoved +
                       field->curPlayer->possibleMovesCount * 0.1f -
                       field->oppPlayer->possibleMovesCount * 0.1f;
    else
        currentValue = (float)field->curPlayer->removedPiecesCount -
                       field->oppPlayer->removedPiecesCount -
                       field->pieceMustBeRemoved +
                       field->oppPlayer->possibleMovesCount * 0.1f -
                       field->curPlayer->possibleMovesCount * 0.1f;

    // when game has finished - perfect for the current player
    if (gameHasFinished && !opponentsMove)
        currentValue = VALUE_GAME_WON - curSearchDepth;

    if (gameHasFinished && opponentsMove)
        currentValue = VALUE_GAME_LOST + curSearchDepth;

    // set next player
    if (!field->pieceMustBeRemoved) {
        tmpPlayer = field->curPlayer;
        field->curPlayer = field->oppPlayer;
        field->oppPlayer = tmpPlayer;
    }
}

//-----------------------------------------------------------------------------
// printMoveInformation()
//
//-----------------------------------------------------------------------------
void MiniMaxAI::printMoveInformation(unsigned int threadNo,
                                     unsigned int idPossibility,
                                     void *pPossibilities)
{
    // locals
    Possibility *tmpPossibility = (Possibility *)pPossibilities;

    // move
    if (field->pieceMustBeRemoved)
        cout << "remove piece from " << (char)(idPossibility + 97);
    else if (field->settingPhase)
        cout << "set piece to " << (char)(idPossibility + 97);
    else
        cout << "move from " << (char)(tmpPossibility->from[idPossibility] + 97)
             << " to " << (char)(tmpPossibility->to[idPossibility] + 97);
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
