/*********************************************************************\
    Mill.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#ifndef MILL_H_INCLUDED
#define MILL_H_INCLUDED

#include "millAI.h"
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <iostream>

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
    uint32_t *moveLogFrom {nullptr}, *moveLogTo {nullptr}, movesDone {0};

    // class-pointer to the AI of player one
    MillAI *playerOneAI {nullptr};

    // class-pointer to the AI of player two
    MillAI *playerTwoAI {nullptr};

    // current board
    fieldStruct field;

    // undo of the last move is done by setting the initial board and performing
    // all moves saved in history
    fieldStruct initField;

    // playerId of the player who has won the game. zero if game is still
    // running.
    int winner {0};

    // playerId of the player who makes the first move
    int beginningPlayer {0};

    // Functions
    void exit();
    void setNextPlayer();
    void generateMoves(Player *player);
    void updateMillsAndWarnings(uint32_t newPiece);
    bool isNormalMovePossible(uint32_t from, uint32_t to,
                              const Player *player) const;
    void setWarningAndMill(uint32_t piece, uint32_t firstNeighbor,
                           uint32_t secondNeighbor, bool isNewPiece);

public:
    // Constructor / destructor
    Mill();
    ~Mill();

    // Functions
    void undoMove();
    void resetGame();
    void beginNewGame(MillAI *firstPlayerAI, MillAI *secondPlayerAI,
                      int curPlayer);
    bool doMove(uint32_t pushFrom, uint32_t pushTo);
    void getComputersChoice(uint32_t *pushFrom, uint32_t *pushTo) const;
    static bool comparePlayers(const Player *playerA, const Player *playerB);
    void printBoard() const;

    // getter
    [[nodiscard]] bool inPlacingPhase() const { return field.isPlacingPhase; }

    [[nodiscard]] uint32_t mustPieceBeRemoved() const
    {
        return field.pieceMustBeRemovedCount;
    }

    [[nodiscard]] int getWinner() const { return winner; }

    [[nodiscard]] int getCurPlayer() const { return field.curPlayer->id; }

    [[nodiscard]] uint32_t getLastMoveFrom() const
    {
        return movesDone ? moveLogFrom[movesDone - 1] : SQUARE_NB;
    }

    [[nodiscard]] uint32_t getLastMoveTo() const
    {
        return movesDone ? moveLogTo[movesDone - 1] : SQUARE_NB;
    }

    [[nodiscard]] uint32_t getMovesDone() const { return movesDone; }

    [[nodiscard]] uint32_t getPiecesSetCount() const
    {
        return field.piecePlacedCount;
    }

    [[nodiscard]] int getBeginningPlayer() const { return beginningPlayer; }

    [[nodiscard]] uint32_t getCurPlayerPieceCount() const
    {
        return field.curPlayer->pieceCount;
    }

    [[nodiscard]] uint32_t getOpponentPlayerPieceCount() const
    {
        return field.oppPlayer->pieceCount;
    }
};

#endif // MILL_H_INCLUDED
