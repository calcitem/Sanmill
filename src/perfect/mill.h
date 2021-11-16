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

#define MAX_NUM_MOVES 10000

#define SAFE_DELETE(p)     \
    {                      \
        if (p) {           \
            delete (p);    \
            (p) = nullptr; \
        }                  \
    }

#define SAFE_DELETE_ARRAY(p) \
    {                        \
        if (p) {             \
            delete[](p);     \
            (p) = nullptr;   \
        }                    \
    }

class Mill {
private:
    // Variables
    unsigned int *moveLogFrom, *moveLogTo, movesDone; // array containing the history of moves done
    MillAI* playerOneAI; // class-pointer to the AI of player one
    MillAI* playerTwoAI; // class-pointer to the AI of player two
    fieldStruct field; // current board
    fieldStruct initialField; // undo of the last move is done by setting the initial board und performing all moves saved in history
    int winner; // playerId of the player who has won the game. zero if game is still running.
    int beginningPlayer; // playerId of the player who makes the first move

    // Functions
    void exit();
    void setNextPlayer();
    void calcPossibleMoves(Player* player);
    void updateMillsAndWarnings(unsigned int newStone);
    bool isNormalMovePossible(unsigned int from, unsigned int to, Player* player);
    void setWarningAndMill(unsigned int stone,
        unsigned int firstNeighbour,
        unsigned int secondNeighbour,
        bool isNewStone);

public:
    // Constructor / destructor
    Mill();
    ~Mill();

    // Functions
    void undoMove();
    void resetGame();
    void beginNewGame(MillAI* firstPlayerAI, MillAI* secondPlayerAI, int currentPlayer);
    void setAI(int player, MillAI* AI);
    bool doMove(unsigned int pushFrom, unsigned int pushTo);
    void getComputersChoice(unsigned int* pushFrom, unsigned int* pushTo);
    bool setCurrentGameState(fieldStruct* curState);
    bool compareWithField(fieldStruct* compareField);
    bool comparePlayers(Player* playerA, Player* playerB);
    void printBoard();
    bool startSettingPhase(MillAI* firstPlayerAI, MillAI* secondPlayerAI, int currentPlayer, bool settingPhase);
    bool putPiece(unsigned int pos, int player);
    bool settingPhaseHasFinished();
    void getChoiceOfSpecialAI(MillAI* AI, unsigned int* pushFrom, unsigned int* pushTo);
    void setUpCalcPossibleMoves(Player* player);
    void setUpSetWarningAndMill(unsigned int stone, unsigned int firstNeighbour, unsigned int secondNeighbour);
    void calcNumberOfRestingStones(int& numWhiteStonesResting, int& numBlackStonesResting);

    // getter
    void getLog(unsigned int& numMovesDone, unsigned int* from, unsigned int* to);
    bool getField(int* pField);
    bool isCurrentPlayerHuman();
    bool isOpponentPlayerHuman();

    bool inSettingPhase()
    {
        return field.settingPhase;
    }

    unsigned int mustStoneBeRemoved()
    {
        return field.stoneMustBeRemoved;
    }

    int getWinner()
    {
        return winner;
    }

    int getCurrentPlayer()
    {
        return field.curPlayer->id;
    }

    unsigned int getLastMoveFrom()
    {
        return (movesDone ? moveLogFrom[movesDone - 1] : field.size);
    }

    unsigned int getLastMoveTo()
    {
        return (movesDone ? moveLogTo[movesDone - 1] : field.size);
    }

    unsigned int getMovesDone()
    {
        return movesDone;
    }

    unsigned int getNumStonesSet()
    {
        return field.stonesSet;
    }

    int getBeginningPlayer()
    {
        return beginningPlayer;
    }

    unsigned int getNumStonOfCurPlayer()
    {
        return field.curPlayer->numStones;
    }

    unsigned int getNumStonOfOppPlayer()
    {
        return field.oppPlayer->numStones;
    }
};

#endif // MILL_H_INCLUDED
