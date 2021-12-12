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
constexpr auto POSIBILE_MOVE_COUNT_MAX = (3 * 18) ;

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
    unsigned int warning;

    // number of pieces of this player on the board
    unsigned int pieceCount;

    // number of pieces, which where stolen by the opponent
    unsigned int removedPiecesCount;

    // amount of possible moves
    unsigned int possibleMovesCount;

    // source board position of a possible move
    Square posFrom[POSIBILE_MOVE_COUNT_MAX];

    // target board position of a possible move
    Square posTo[POSIBILE_MOVE_COUNT_MAX];

    void copyPlayer(Player *destination);
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
    static const unsigned int noWarning = 0;
    static const unsigned int playerOneWarning = 2;
    static const unsigned int playerTwoWarning = 4;
    static const unsigned int playerBothWarning = 6;
    static const unsigned int piecePerPlayerCount = 9;

    // only a nonzero value
    static const int gameDrawn = 3;

    // variables

    // one of the values above for each board position
    int board[SQUARE_NB];

    // array containing the warnings for each board position
    unsigned int warnings[SQUARE_NB];

    // true if piece can be moved in this direction
    bool pieceMoveAble[SQUARE_NB][MD_NB];

    // the number of mills, of which this piece is part of
    unsigned int piecePartOfMill[SQUARE_NB];

    // static array containing the index of the neighbour or "size"
    unsigned int connectedSquare[SQUARE_NB][4];

    // static array containing the two neighbors of each squares
    unsigned int neighbour[SQUARE_NB][2][2];

    // number of pieces set in the setting phase
    unsigned int piecesSet;

    // true if piecesSet < 18
    bool settingPhase;

    // number of pieces which must be removed by the current player
    unsigned int pieceMustBeRemoved;

    // pointers to the current and opponent player
    Player *curPlayer, *oppPlayer;

    // useful functions
    void printBoard();
    void copyBoard(fieldStruct *destination);
    void createBoard();
    void deleteBoard();

private:
    // helper functions
    char GetCharFromPiece(int piece);
    void setConnection(unsigned int index, int firstDirection,
                       int secondDirection, int thirdDirection,
                       int fourthDirection);
    void setNeighbour(unsigned int index, unsigned int firstNeighbour0,
                      unsigned int secondNeighbour0,
                      unsigned int firstNeighbour1,
                      unsigned int secondNeighbour1);
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
    virtual void play(fieldStruct *theField, unsigned int *pushFrom,
                      unsigned int *pushTo) = 0;
};

#endif // MUEHLE_AI_H_INCLUDED
