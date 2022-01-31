/*********************************************************************\
    millAI.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#ifndef MUEHLE_AI_H_INCLUDED
#define MUEHLE_AI_H_INCLUDED

#include <cstdio>
#include <iostream>

#include "types.h"

// using namespace std;

// not (9 * 4) = 36 since the possibilities with 3 pieces are more
constexpr auto POSIBILE_MOVE_COUNT_MAX = 3 * 18;

#define SAFE_DELETE(p) \
    { \
        if (p) { \
            delete (p); \
            (p) = nullptr; \
        } \
    }

class Player
{
public:
    // static
    int id {0};

    // static
    uint32_t warning {0};

    // number of pieces of this player on the board
    uint32_t pieceCount {0};

    // number of pieces, which where stolen by the opponent
    uint32_t removedPiecesCount {0};

    // amount of possible moves
    uint32_t possibleMovesCount {0};

    // source board position of a possible move
    // TODO(calcitem): {SQUARE_INVALID}
    Square posFrom[POSIBILE_MOVE_COUNT_MAX] {SQUARE_NB};

    // target board position of a possible move
    // TODO(calcitem): {SQUARE_INVALID}
    Square posTo[POSIBILE_MOVE_COUNT_MAX] {SQUARE_NB};

    void copyPlayer(Player *dest) const;
};

class fieldStruct
{
public:
    // constants

    // trivial
    static constexpr int squareIsFree = 0;

    // so rowOwner can be calculated easy
    static constexpr int playerOne = -1;
    static constexpr int playerTwo = 1;

    // so rowOwner can be calculated easy
    static constexpr int playerBlack = -1;
    static constexpr int playerWhite = 1;

    // so the bitwise or-operation can be applied, without interacting with
    // playerOne & Two
    static constexpr uint32_t noWarning = 0;
    static constexpr uint32_t playerOneWarning = 2;
    static constexpr uint32_t playerTwoWarning = 4;
    static constexpr uint32_t playerBothWarning = 6;
    static constexpr uint32_t piecePerPlayerCount = 9;

    // only a nonzero value
    static constexpr int gameDrawn = 3;

    // variables

    // one of the values above for each board position
    int board[SQUARE_NB] {0};

    // array containing the warnings for each board position
    uint32_t warnings[SQUARE_NB] {0};

    // true if piece can be moved in this direction
    bool isPieceMovable[SQUARE_NB][MD_NB] {{false}};

    // the number of mills, of which this piece is part of
    uint32_t piecePartOfMillCount[SQUARE_NB] {0};

    // static array containing the index of the neighbor or "size"
    uint32_t connectedSquare[SQUARE_NB][4] {{0}};

    // static array containing the two neighbors of each squares
    uint32_t neighbor[SQUARE_NB][2][2] {{{0}}};

    // number of pieces placed in the placing phase
    uint32_t piecePlacedCount {0};

    // true if piecePlacedCount < 18
    bool isPlacingPhase {false};

    // number of pieces which must be removed by the current player
    uint32_t pieceMustBeRemovedCount {0};

    // pointers to the current and opponent player
    Player *curPlayer {nullptr}, *oppPlayer {nullptr};

    // useful functions
    void printBoard() const;
    void copyBoard(fieldStruct *dest) const;
    void createBoard();
    void deleteBoard();

private:
    // helper functions
    static char getCharFromPiece(int piece);
    void setConnection(uint32_t index, int firstDirection, int secondDirection,
                       int thirdDirection, int fourthDirection);
    void setNeighbor(uint32_t index, uint32_t firstNeighbor0,
                     uint32_t secondNeighbor0, uint32_t firstNeighbor1,
                     uint32_t secondNeighbor1);
};

#ifdef __clang__ // TODO(calcitem)
class MillAI
#else
class MillAI abstract
#endif
{
protected:
    fieldStruct dummyField;

public:
    // Constructor / destructor
    MillAI() { dummyField.createBoard(); }

    ~MillAI() { dummyField.deleteBoard(); }

    // Functions
    virtual void play(fieldStruct *theField, uint32_t *pushFrom,
                      uint32_t *pushTo) = 0;
};

#endif // MUEHLE_AI_H_INCLUDED
