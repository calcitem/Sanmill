/*********************************************************************
    Mill.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "mill.h"
#include <cassert>

//-----------------------------------------------------------------------------
// Mill()
// Mill class constructor
//-----------------------------------------------------------------------------
Mill::Mill()
{
    srand(static_cast<unsigned>(time(nullptr)));

    moveLogFrom = nullptr;
    moveLogTo = nullptr;
    playerOneAI = nullptr;
    playerTwoAI = nullptr;
    movesDone = 0;

    winner = 0;
    beginningPlayer = 0;

    field.createBoard();
    initField.createBoard();
}

//-----------------------------------------------------------------------------
// ~Mill()
// Mill class destructor
//-----------------------------------------------------------------------------
Mill::~Mill()
{
    exit();
}

//-----------------------------------------------------------------------------
// deleteArrays()
// Deletes all arrays the Mill class has created.
//-----------------------------------------------------------------------------
void Mill::exit()
{
    SAFE_DELETE_ARRAY(moveLogFrom);
    SAFE_DELETE_ARRAY(moveLogTo);

    field.deleteBoard();
    initField.deleteBoard();
}

//-----------------------------------------------------------------------------
// resetGame()
// Reset the Mill object.
//-----------------------------------------------------------------------------
void Mill::resetGame()
{
    std::memset(moveLogFrom, 0, MOVE_COUNT_MAX);
    std::memset(moveLogTo, 0, MOVE_COUNT_MAX);
    initField.copyBoard(&field);

    winner = 0;
    movesDone = 0;
}

//-----------------------------------------------------------------------------
// beginNewGame()
// Reinitializes the Mill object.
//-----------------------------------------------------------------------------
void Mill::beginNewGame(MillAI *firstPlayerAI, MillAI *secondPlayerAI,
                        int curPlayer)
{
    // free memory
    exit();

    // create arrays
    field.createBoard();
    initField.createBoard();

    // calculate beginning player
    if (curPlayer == field.playerOne || curPlayer == field.playerTwo) {
        beginningPlayer = curPlayer;
    } else {
        beginningPlayer = (rand() % 2) ? field.playerOne : field.playerTwo;
    }

    field.curPlayer->id = beginningPlayer;
    field.oppPlayer->id = field.curPlayer->id == field.playerTwo ?
                              field.playerOne :
                              field.playerTwo;

    winner = 0;
    movesDone = 0;
    playerOneAI = firstPlayerAI;
    playerTwoAI = secondPlayerAI;
    moveLogFrom = new uint32_t[MOVE_COUNT_MAX];
    std::memset(moveLogFrom, 0, sizeof(uint32_t) * MOVE_COUNT_MAX);
    moveLogTo = new uint32_t[MOVE_COUNT_MAX];
    std::memset(moveLogTo, 0, sizeof(uint32_t) * MOVE_COUNT_MAX);

    // remember initField
    field.copyBoard(&initField);
}

//-----------------------------------------------------------------------------
// setNextPlayer()
// Current player and opponent player are switched in the board struct.
//-----------------------------------------------------------------------------
void Mill::setNextPlayer()
{
    Player *tmpPlayer = field.curPlayer;
    field.curPlayer = field.oppPlayer;
    field.oppPlayer = tmpPlayer;
}

//-----------------------------------------------------------------------------
// getComputersChoice()
// Returns the move the AI of the current player would do.
//-----------------------------------------------------------------------------
void Mill::getComputersChoice(uint32_t *pushFrom, uint32_t *pushTo) const
{
    fieldStruct theField;
    *pushFrom = SQUARE_NB;
    *pushTo = SQUARE_NB;
    theField.createBoard();
    // assert(theField.oppPlayer->id >= -1 && theField.oppPlayer->id <= 1);

    field.copyBoard(&theField);

    // assert(theField.oppPlayer->id >= -1 && theField.oppPlayer->id <= 1);

    if ((field.isPlacingPhase || field.curPlayer->possibleMovesCount > 0) &&
        winner == 0) {
        if (field.curPlayer->id == field.playerOne) {
            if (playerOneAI != nullptr)
                playerOneAI->play(&theField, pushFrom, pushTo);
            // assert(theField.oppPlayer->id >= -1 && theField.oppPlayer->id
            // <=1);
        } else {
            if (playerTwoAI != nullptr)
                playerTwoAI->play(&theField, pushFrom, pushTo);
            // assert(theField.oppPlayer->id >= -1 && theField.oppPlayer->id <=
            // 1);
        }
    }

    if (*pushFrom == 24 && *pushTo == 24) {
        assert(false);
    }

    theField.deleteBoard();
}

//-----------------------------------------------------------------------------
// isNormalMovePossible()
// 'Normal' in this context means, by moving the piece along a connection
// without jumping.
//-----------------------------------------------------------------------------
bool Mill::isNormalMovePossible(uint32_t from, uint32_t to,
                                const Player *player) const
{
    // locals
    uint32_t movingDirection, i;

    // param ok ?
    if (from >= SQUARE_NB)
        return false;
    if (to >= SQUARE_NB)
        return false;

    // is piece from player ?
    if (field.board[from] != player->id)
        return false;

    // is dest free ?
    if (field.board[to] != field.squareIsFree)
        return false;

    // when current player has only 3 pieces he is allowed to spring his piece
    if (player->pieceCount > 3 || field.isPlacingPhase) {
        // determine moving direction
        for (i = 0, movingDirection = 4; i < 4; i++)
            if (field.connectedSquare[from][i] == to)
                movingDirection = i;

        // are both squares connected ?
        if (movingDirection == 4)
            return false;
    }

    // everything is ok
    return true;
}

//-----------------------------------------------------------------------------
// generateMoves()
// ...
//-----------------------------------------------------------------------------
void Mill::generateMoves(Player *player)
{
    // locals
    uint32_t i;
    Square from;

    // zero
    for (i = 0; i < POSIBILE_MOVE_COUNT_MAX; i++) {
        player->posTo[i] = SQUARE_NB;
    }

    for (i = 0; i < POSIBILE_MOVE_COUNT_MAX; i++) {
        player->posFrom[i] = SQUARE_NB;
    }

    // calculate
    for (player->possibleMovesCount = 0, from = SQ_0; from < SQUARE_NB;
         ++from) {
        for (Square to = SQ_0; to < SQUARE_NB; ++to) {
            if (isNormalMovePossible(from, to, player)) {
                player->posFrom[player->possibleMovesCount] = from;
                player->posTo[player->possibleMovesCount] = to;
                player->possibleMovesCount++;
            }
        }
    }

    // isPieceMovable
    for (from = SQ_0; from < SQUARE_NB; ++from) {
        for (MoveDirection md = MD_BEGIN; md < MD_NB; ++md) {
            if (field.board[from] == player->id) {
                field.isPieceMovable[from][md] = isNormalMovePossible(
                    from, field.connectedSquare[from][md], player);
            } else {
                field.isPieceMovable[from][md] = false;
            }
        }
    }
}

//-----------------------------------------------------------------------------
// setWarningAndMill()
//
//-----------------------------------------------------------------------------
void Mill::setWarningAndMill(uint32_t piece, uint32_t firstNeighbor,
                             uint32_t secondNeighbor, bool isNewPiece)
{
    // locals
    const int rowOwner = field.board[piece];
    const uint32_t rowOwnerWarning = (rowOwner == field.playerOne) ?
                                         field.playerOneWarning :
                                         field.playerTwoWarning;

    // mill closed ?
    if (rowOwner != field.squareIsFree &&
        field.board[firstNeighbor] == rowOwner &&
        field.board[secondNeighbor] == rowOwner) {
        field.piecePartOfMillCount[piece]++;
        field.piecePartOfMillCount[firstNeighbor]++;
        field.piecePartOfMillCount[secondNeighbor]++;
        if (isNewPiece)
            field.pieceMustBeRemovedCount = 1;
    }

    // warning ?
    if (rowOwner != field.squareIsFree &&
        field.board[firstNeighbor] == field.squareIsFree &&
        field.board[secondNeighbor] == rowOwner)
        field.warnings[firstNeighbor] |= rowOwnerWarning;

    if (rowOwner != field.squareIsFree &&
        field.board[secondNeighbor] == field.squareIsFree &&
        field.board[firstNeighbor] == rowOwner)
        field.warnings[secondNeighbor] |= rowOwnerWarning;
}

//-----------------------------------------------------------------------------
// updateMillsAndWarnings()
//
//-----------------------------------------------------------------------------
void Mill::updateMillsAndWarnings(uint32_t newPiece)
{
    // locals
    uint32_t i;
    bool atLeastOnePieceRemoveAble;

    // zero
    for (i = 0; i < SQUARE_NB; i++)
        field.piecePartOfMillCount[i] = 0;

    for (i = 0; i < SQUARE_NB; i++)
        field.warnings[i] = field.noWarning;

    field.pieceMustBeRemovedCount = 0;

    // go in every direction
    for (i = 0; i < SQUARE_NB; i++) {
        setWarningAndMill(i, field.neighbor[i][0][0], field.neighbor[i][0][1],
                          i == newPiece);
        setWarningAndMill(i, field.neighbor[i][1][0], field.neighbor[i][1][1],
                          i == newPiece);
    }

    // since every mill was detected 3 times
    for (i = 0; i < SQUARE_NB; i++)
        field.piecePartOfMillCount[i] /= 3;

    // no piece must be removed if each belongs to a mill
    for (atLeastOnePieceRemoveAble = false, i = 0; i < SQUARE_NB; i++)
        if (field.piecePartOfMillCount[i] == 0 &&
            field.board[i] == field.oppPlayer->id)
            atLeastOnePieceRemoveAble = true;
    if (!atLeastOnePieceRemoveAble)
        field.pieceMustBeRemovedCount = 0;
}

//-----------------------------------------------------------------------------
// doMove()
//
//-----------------------------------------------------------------------------
bool Mill::doMove(uint32_t pushFrom, uint32_t pushTo)
{
    // avoid index override
    if (movesDone >= MOVE_COUNT_MAX)
        return false;

    // is game still running ?
    if (winner)
        return false;

    // handle the remove of a piece
    if (field.pieceMustBeRemovedCount) {
        // param ok ?
        if (pushFrom >= SQUARE_NB)
            return false;

        // is it piece from the opponent ?
        if (field.board[pushFrom] != field.oppPlayer->id)
            return false;

        // is piece not part of mill?
        if (field.piecePartOfMillCount[pushFrom])
            return false;

        // remove piece
        moveLogFrom[movesDone] = pushFrom;
        moveLogTo[movesDone] = SQUARE_NB;
        field.board[pushFrom] = field.squareIsFree;
        field.oppPlayer->removedPiecesCount++;
        field.oppPlayer->pieceCount--;
        field.pieceMustBeRemovedCount--;
        movesDone++;

        // is the game finished ?
        if ((field.oppPlayer->pieceCount < 3) && !field.isPlacingPhase)
            winner = field.curPlayer->id;

        // update warnings & mills
        updateMillsAndWarnings(SQUARE_NB);

        // calculate possibilities
        generateMoves(field.curPlayer);
        generateMoves(field.oppPlayer);

        // is opponent unable to move ?
        if (field.oppPlayer->possibleMovesCount == 0 && !field.isPlacingPhase)
            winner = field.curPlayer->id;

        // next player
        if (!field.pieceMustBeRemovedCount)
            setNextPlayer();

        // everything is ok
        return true;

        // handle placing phase
    }

    if (field.isPlacingPhase) {
        // param ok ?
        if (pushTo >= SQUARE_NB)
            return false;

        // is dest free ?
        if (field.board[pushTo] != field.squareIsFree)
            return false;

        // set piece
        moveLogFrom[movesDone] = SQUARE_NB;
        moveLogTo[movesDone] = pushTo;
        field.board[pushTo] = field.curPlayer->id;
        field.curPlayer->pieceCount++;
        field.piecePlacedCount++;
        movesDone++;

        // update warnings & mills
        updateMillsAndWarnings(pushTo);

        // calculate possibilities
        generateMoves(field.curPlayer);
        generateMoves(field.oppPlayer);

        // placing phase finished ?
        if (field.piecePlacedCount == 18)
            field.isPlacingPhase = false;

        // is opponent unable to move ?
        if (field.oppPlayer->possibleMovesCount == 0 && !field.isPlacingPhase)
            winner = field.curPlayer->id;

        // next player
        if (!field.pieceMustBeRemovedCount)
            setNextPlayer();

        // everything is ok
        return true;

        // normal move
    }

    // is move possible ?
    if (!isNormalMovePossible(pushFrom, pushTo, field.curPlayer))
        return false;

    // move piece
    moveLogFrom[movesDone] = pushFrom;
    moveLogTo[movesDone] = pushTo;
    field.board[pushFrom] = field.squareIsFree;
    field.board[pushTo] = field.curPlayer->id;
    movesDone++;

    // update warnings & mills
    updateMillsAndWarnings(pushTo);

    // calculate possibilities
    generateMoves(field.curPlayer);
    generateMoves(field.oppPlayer);

    // is opponent unable to move ?
    if (field.oppPlayer->possibleMovesCount == 0 && !field.isPlacingPhase)
        winner = field.curPlayer->id;

    // next player
    if (!field.pieceMustBeRemovedCount)
        setNextPlayer();

    // everything is ok
    return true;
}

//-----------------------------------------------------------------------------
// comparePlayers()
// Compares the two passed players and returns false if they differ.
//-----------------------------------------------------------------------------
bool Mill::comparePlayers(const Player *playerA, const Player *playerB)
{
    // uint32_t i;
    bool ret = true;

    if (playerA->removedPiecesCount != playerB->removedPiecesCount) {
        cout << "error - removedPiecesCount differs!" << std::endl;
        ret = false;
    }

    if (playerA->pieceCount != playerB->pieceCount) {
        cout << "error - pieceCount differs!" << std::endl;
        ret = false;
    }

    if (playerA->id != playerB->id) {
        cout << "error - id differs!" << std::endl;
        ret = false;
    }

    if (playerA->warning != playerB->warning) {
        cout << "error - warning differs!" << std::endl;
        ret = false;
    }

    if (playerA->possibleMovesCount != playerB->possibleMovesCount) {
        cout << "error - possibleMovesCount differs!" << std::endl;
        ret = false;
    }

#if 0
    for (i = 0; i < POSIBILE_MOVE_COUNT_MAX; i++)
        if (playerA->posFrom[i] = playerB->posFrom[i])
            return false;
    for (i = 0; i < POSIBILE_MOVE_COUNT_MAX; i++)
        if (playerA->posTo[i] = playerB->posTo[i])
            return false;
#endif
    return ret;
}

//-----------------------------------------------------------------------------
// printBoard()
// Calls the printBoard() function of the current board.
//       Prints the current game state on the screen.
//-----------------------------------------------------------------------------
void Mill::printBoard() const
{
    field.printBoard();
}

//-----------------------------------------------------------------------------
// undoMove()
// Sets the initial board as the current one and apply all (minus one) moves
// from the move history.
//-----------------------------------------------------------------------------
void Mill::undoMove()
{
    // locals
    const auto moveLogFrom_bak = new uint32_t[movesDone];
    std::memset(moveLogFrom_bak, 0, sizeof(uint32_t) * movesDone);
    const auto moveLogTo_bak = new uint32_t[movesDone];
    std::memset(moveLogTo_bak, 0, sizeof(uint32_t) * movesDone);
    const uint32_t movesDone_bak = movesDone;

    // at least one move must be done
    if (movesDone) {
        // make backup of log
        for (uint32_t i = 0; i < movesDone; i++) {
            moveLogFrom_bak[i] = moveLogFrom[i];
            moveLogTo_bak[i] = moveLogTo[i];
        }

        // reset
        initField.copyBoard(&field);
        winner = 0;
        movesDone = 0;

        // and play again
        for (uint32_t i = 0; i < movesDone_bak - 1; i++) {
            doMove(moveLogFrom_bak[i], moveLogTo_bak[i]);
        }
    }

    // free mem
    delete[] moveLogFrom_bak;
    delete[] moveLogTo_bak;
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
