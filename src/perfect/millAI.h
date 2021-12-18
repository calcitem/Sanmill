/*********************************************************************\
    millAI.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
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
constexpr auto POSIBILE_MOVE_COUNT_MAX = (3 * 18);

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
    int id;

    // static
    uint32_t warning;

    // number of pieces of this player on the board
    uint32_t pieceCount;

    // number of pieces, which where stolen by the opponent
    uint32_t removedPiecesCount;

    // amount of possible moves
    uint32_t possibleMovesCount;

    // source board position of a possible move
    Square posFrom[POSIBILE_MOVE_COUNT_MAX];

    // target board position of a possible move
    Square posTo[POSIBILE_MOVE_COUNT_MAX];

    void copyPlayer(Player *dest);
};

class fieldStruct
{
public:
    // constants

    // trivial
    static const int squareIsFree = 0;

    // so rowOwner can be calculated easy
    static const int playerOne = -1;
    static const int playerTwo = 1;

    // so rowOwner can be calculated easy
    static const int playerBlack = -1;
    static const int playerWhite = 1;

    // so the bitwise or-operation can be applied, without interacting with
    // playerOne & Two
    static const uint32_t noWarning = 0;
    static const uint32_t playerOneWarning = 2;
    static const uint32_t playerTwoWarning = 4;
    static const uint32_t playerBothWarning = 6;
    static const uint32_t piecePerPlayerCount = 9;

    // only a nonzero value
    static const int gameDrawn = 3;

    // variables

    // one of the values above for each board position
    int board[SQUARE_NB];

    // array containing the warnings for each board position
    uint32_t warnings[SQUARE_NB];

    // true if piece can be moved in this direction
    bool isPieceMovable[SQUARE_NB][MD_NB];

    // the number of mills, of which this piece is part of
    uint32_t piecePartOfMillCount[SQUARE_NB];

    // static array containing the index of the neighbor or "size"
    uint32_t connectedSquare[SQUARE_NB][4];

    // static array containing the two neighbors of each squares
    uint32_t neighbor[SQUARE_NB][2][2];

    // number of pieces placed in the placing phase
    uint32_t piecePlacedCount;

    // true if piecePlacedCount < 18
    bool isPlacingPhase;

    // number of pieces which must be removed by the current player
    uint32_t pieceMustBeRemovedCount;

    // pointers to the current and opponent player
    Player *curPlayer, *oppPlayer;

    // useful functions
    void printBoard();
    void copyBoard(fieldStruct *dest);
    void createBoard();
    void deleteBoard();

private:
    // helper functions
    char getCharFromPiece(int piece);
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
