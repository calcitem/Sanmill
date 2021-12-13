/*********************************************************************\
    Mill.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#ifndef MILL_H_INCLUDED
#define MILL_H_INCLUDED

#include "millAI.h"
#include <cstdio>
#include <iostream>
#include <stdlib.h>
#include <time.h>

#include "../types.h"

using std::cout;
using std::iostream;

constexpr auto MOVE_COUNT_MAX = 10000;

#define SAFE_DELETE(p) \
    { \
        if (p) { \
            delete (p); \
            (p) = nullptr; \
        } \
    }

#define SAFE_DELETE_ARRAY(p) \
    { \
        if (p) { \
            delete[](p); \
            (p) = nullptr; \
        } \
    }

class Mill
{
private:
    // Variables

    // array containing the history of moves done
    unsigned int *moveLogFrom, *moveLogTo, movesDone;

    // class-pointer to the AI of player one
    MillAI *playerOneAI;

    // class-pointer to the AI of player two
    MillAI *playerTwoAI;

    // current board
    fieldStruct field;

    // undo of the last move is done by setting the initial board and performing
    // all moves saved in history
    fieldStruct initField;

    // playerId of the player who has won the game. zero if game is still
    // running.
    int winner;

    // playerId of the player who makes the first move
    int beginningPlayer;

    // Functions
    void exit();
    void setNextPlayer();
    void generateMoves(Player *player);
    void updateMillsAndWarnings(unsigned int newPiece);
    bool isNormalMovePossible(unsigned int from, unsigned int to,
                              Player *player);
    void setWarningAndMill(unsigned int piece, unsigned int firstNeighbor,
                           unsigned int secondNeighbor, bool isNewPiece);

public:
    // Constructor / destructor
    Mill();
    ~Mill();

    // Functions
    void undoMove();
    void resetGame();
    void beginNewGame(MillAI *firstPlayerAI, MillAI *secondPlayerAI,
                      int curPlayer);
    void setAI(int player, MillAI *AI);
    bool doMove(unsigned int pushFrom, unsigned int pushTo);
    void getComputersChoice(unsigned int *pushFrom, unsigned int *pushTo);
    bool setCurGameState(fieldStruct *curState);
    bool compareWithField(fieldStruct *compareField);
    bool comparePlayers(Player *playerA, Player *playerB);
    void printBoard();
    bool startPlacingPhase(MillAI *firstPlayerAI, MillAI *secondPlayerAI,
                           int curPlayer, bool placingPhase);
    bool putPiece(unsigned int pos, int player);
    bool placingPhaseHasFinished();
    void getChoiceOfSpecialAI(MillAI *AI, unsigned int *pushFrom,
                              unsigned int *pushTo);
    void setUpCalcPossibleMoves(Player *player);
    void setUpSetWarningAndMill(unsigned int piece, unsigned int firstNeighbor,
                                unsigned int secondNeighbor);
    void calcRestingPieceCount(int &nWhitePiecesResting,
                               int &nBlackPiecesResting);

    // getter
    void getLog(unsigned int &nMovesDone, unsigned int *from, unsigned int *to);
    bool getField(int *pField);
    bool isCurPlayerHuman();
    bool isOpponentPlayerHuman();

    bool inPlacingPhase() { return field.placingPhase; }

    unsigned int mustPieceBeRemoved() { return field.pieceMustBeRemoved; }

    int getWinner() { return winner; }

    int getCurPlayer() { return field.curPlayer->id; }

    unsigned int getLastMoveFrom()
    {
        return (movesDone ? moveLogFrom[movesDone - 1] : SQUARE_NB);
    }

    unsigned int getLastMoveTo()
    {
        return (movesDone ? moveLogTo[movesDone - 1] : SQUARE_NB);
    }

    unsigned int getMovesDone() { return movesDone; }

    unsigned int getPiecesSetCount() { return field.piecesSet; }

    int getBeginningPlayer() { return beginningPlayer; }

    unsigned int getCurPlayerPieceCount()
    {
        return field.curPlayer->pieceCount;
    }

    unsigned int getOpponentPlayerPieceCount()
    {
        return field.oppPlayer->pieceCount;
    }
};

#endif // MILL_H_INCLUDED
