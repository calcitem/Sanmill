/*********************************************************************
    millAI.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "millAI.h"

using namespace std;

//-----------------------------------------------------------------------------
// printBoard()
//
//-----------------------------------------------------------------------------
void fieldStruct::printBoard() const
{
    // locals
    char c[SQUARE_NB];

    for (uint32_t sq = 0; sq < SQUARE_NB; sq++)
        c[sq] = getCharFromPiece(this->board[sq]);

    cout << "current player          : "
         << getCharFromPiece(this->curPlayer->id) << " has "
         << this->curPlayer->pieceCount << " pieces\n";
    cout << "opponent player         : "
         << getCharFromPiece(this->oppPlayer->id) << " has "
         << this->oppPlayer->pieceCount << " pieces\n";
    cout << "Num Pieces to be removed: " << this->pieceMustBeRemovedCount
         << "\n";
    cout << "placing phase           : "
         << (this->isPlacingPhase ? "true" : "false");
    cout << "\n";
    cout << "\n   a-----b-----c   " << c[0] << "-----" << c[1] << "-----"
         << c[2];
    cout << "\n   |     |     |   "
         << "|     |     |";
    cout << "\n   | d---e---f |   "
         << "| " << c[3] << "---" << c[4] << "---" << c[5] << " |";
    cout << "\n   | |   |   | |   "
         << "| |   |   | |";
    cout << "\n   | | g-h-i | |   "
         << "| | " << c[6] << "-" << c[7] << "-" << c[8] << " | |";
    cout << "\n   | | | | | | |   "
         << "| | |   | | |";
    cout << "\n   j-k-l   m-n-o   " << c[9] << "-" << c[10] << "-" << c[11]
         << "   " << c[12] << "-" << c[13] << "-" << c[14];
    cout << "\n   | | | | | | |   "
         << "| | |   | | |";
    cout << "\n   | | p-q-r | |   "
         << "| | " << c[15] << "-" << c[16] << "-" << c[17] << " | |";
    cout << "\n   | |   |   | |   "
         << "| |   |   | |";
    cout << "\n   | s---t---u |   "
         << "| " << c[18] << "---" << c[19] << "---" << c[20] << " |";
    cout << "\n   |     |     |   "
         << "|     |     |";
    cout << "\n   v-----w-----x   " << c[21] << "-----" << c[22] << "-----"
         << c[23];
    cout << "\n";
}

//-----------------------------------------------------------------------------
// getCharFromPiece()
//
//-----------------------------------------------------------------------------
char fieldStruct::getCharFromPiece(int piece)
{
    switch (piece) {
    case playerOne:
        return 'o';
    case playerTwo:
        return 'x';
    case playerOneWarning:
        return '1';
    case playerTwoWarning:
        return '2';
    case playerBothWarning:
        return '3';
    case squareIsFree:
        return ' ';
    }
    return 'f';
}

//-----------------------------------------------------------------------------
// copyBoard()
// Only copies the values without array creation.
//-----------------------------------------------------------------------------
void fieldStruct::copyBoard(fieldStruct *dest) const
{
    this->curPlayer->copyPlayer(dest->curPlayer);
    this->oppPlayer->copyPlayer(dest->oppPlayer);

    dest->piecePlacedCount = this->piecePlacedCount;
    dest->isPlacingPhase = this->isPlacingPhase;
    dest->pieceMustBeRemovedCount = this->pieceMustBeRemovedCount;

    for (uint32_t i = 0; i < SQUARE_NB; i++) {
        dest->board[i] = this->board[i];
        dest->warnings[i] = this->warnings[i];
        dest->piecePartOfMillCount[i] = this->piecePartOfMillCount[i];

        for (uint32_t j = 0; j < MD_NB; j++) {
            dest->connectedSquare[i][j] = this->connectedSquare[i][j];
            dest->isPieceMovable[i][j] = this->isPieceMovable[i][j];
            dest->neighbor[i][j / 2][j % 2] = this->neighbor[i][j / 2][j % 2];
        }
    }
}

//-----------------------------------------------------------------------------
// copyPlayer()
// Only copies the values without array creation.
//-----------------------------------------------------------------------------
void Player::copyPlayer(Player *dest) const
{
    uint32_t i;

    dest->removedPiecesCount = this->removedPiecesCount;
    dest->pieceCount = this->pieceCount;
    dest->id = this->id;
    dest->warning = this->warning;
    dest->possibleMovesCount = this->possibleMovesCount;

    for (i = 0; i < POSIBILE_MOVE_COUNT_MAX; i++)
        dest->posFrom[i] = this->posFrom[i];

    for (i = 0; i < POSIBILE_MOVE_COUNT_MAX; i++)
        dest->posTo[i] = this->posTo[i];
}

//-----------------------------------------------------------------------------
// createBoard()
// Creates, but doesn't initialize, the arrays of the of the passed board
// structure.
//-----------------------------------------------------------------------------
void fieldStruct::createBoard()
{
    // locals
    uint32_t i;

    curPlayer = new Player;
    oppPlayer = new Player;

    curPlayer->id = playerOne;
    piecePlacedCount = 0;
    pieceMustBeRemovedCount = 0;
    isPlacingPhase = true;
    curPlayer->warning = curPlayer->id == playerOne ? playerOneWarning :
                                                      playerTwoWarning;
    oppPlayer->id = curPlayer->id == playerOne ? playerTwo : playerOne;
    oppPlayer->warning = (curPlayer->id == playerOne) ? playerTwoWarning :
                                                        playerOneWarning;
    curPlayer->pieceCount = 0;
    oppPlayer->pieceCount = 0;
    curPlayer->possibleMovesCount = 0;
    oppPlayer->possibleMovesCount = 0;
    curPlayer->removedPiecesCount = 0;
    oppPlayer->removedPiecesCount = 0;

    // zero
    for (i = 0; i < SQUARE_NB; i++) {
        board[i] = squareIsFree;
        warnings[i] = noWarning;
        piecePartOfMillCount[i] = 0;
        isPieceMovable[i][MD_CLOCKWISE] = false;
        isPieceMovable[i][MD_ANTICLOCKWISE] = false;
        isPieceMovable[i][MD_INWARD] = false;
        isPieceMovable[i][MD_OUTWARD] = false;
    }

    // set connections
    i = SQUARE_NB;

    setConnection(0, 1, 9, i, i);
    setConnection(1, 2, 4, 0, i);
    setConnection(2, i, 14, 1, i);
    setConnection(3, 4, 10, i, i);
    setConnection(4, 5, 7, 3, 1);
    setConnection(5, i, 13, 4, i);
    setConnection(6, 7, 11, i, i);
    setConnection(7, 8, i, 6, 4);
    setConnection(8, i, 12, 7, i);
    setConnection(9, 10, 21, i, 0);
    setConnection(10, 11, 18, 9, 3);
    setConnection(11, i, 15, 10, 6);
    setConnection(12, 13, 17, i, 8);
    setConnection(13, 14, 20, 12, 5);
    setConnection(14, i, 23, 13, 2);
    setConnection(15, 16, i, i, 11);
    setConnection(16, 17, 19, 15, i);
    setConnection(17, i, i, 16, 12);
    setConnection(18, 19, i, i, 10);
    setConnection(19, 20, 22, 18, 16);
    setConnection(20, i, i, 19, 13);
    setConnection(21, 22, i, i, 9);
    setConnection(22, 23, i, 21, 19);
    setConnection(23, i, i, 22, 14);

    // neighbors
    setNeighbor(0, 1, 2, 9, 21);
    setNeighbor(1, 0, 2, 4, 7);
    setNeighbor(2, 0, 1, 14, 23);
    setNeighbor(3, 4, 5, 10, 18);
    setNeighbor(4, 1, 7, 3, 5);
    setNeighbor(5, 3, 4, 13, 20);
    setNeighbor(6, 7, 8, 11, 15);
    setNeighbor(7, 1, 4, 6, 8);
    setNeighbor(8, 6, 7, 12, 17);
    setNeighbor(9, 10, 11, 0, 21);
    setNeighbor(10, 9, 11, 3, 18);
    setNeighbor(11, 9, 10, 6, 15);
    setNeighbor(12, 13, 14, 8, 17);
    setNeighbor(13, 12, 14, 5, 20);
    setNeighbor(14, 12, 13, 2, 23);
    setNeighbor(15, 6, 11, 16, 17);
    setNeighbor(16, 15, 17, 19, 22);
    setNeighbor(17, 15, 16, 8, 12);
    setNeighbor(18, 3, 10, 19, 20);
    setNeighbor(19, 18, 20, 16, 22);
    setNeighbor(20, 5, 13, 18, 19);
    setNeighbor(21, 0, 9, 22, 23);
    setNeighbor(22, 16, 19, 21, 23);
    setNeighbor(23, 2, 14, 21, 22);
}

//-----------------------------------------------------------------------------
// deleteBoard()
// ...
//-----------------------------------------------------------------------------
void fieldStruct::deleteBoard()
{
    try {
        SAFE_DELETE(curPlayer);
        SAFE_DELETE(oppPlayer);
    } catch (const char *msg) {
        cerr << msg << endl;
    }
}

//-----------------------------------------------------------------------------
// setConnection()
//
//-----------------------------------------------------------------------------
inline void fieldStruct::setConnection(uint32_t index, int firstDirection,
                                       int secondDirection, int thirdDirection,
                                       int fourthDirection)
{
    connectedSquare[index][0] = firstDirection;
    connectedSquare[index][1] = secondDirection;
    connectedSquare[index][2] = thirdDirection;
    connectedSquare[index][3] = fourthDirection;
}

//-----------------------------------------------------------------------------
// setNeighbor()
//
//-----------------------------------------------------------------------------
inline void fieldStruct::setNeighbor(uint32_t index, uint32_t firstNeighbor0,
                                     uint32_t secondNeighbor0,
                                     uint32_t firstNeighbor1,
                                     uint32_t secondNeighbor1)
{
    neighbor[index][0][0] = firstNeighbor0;
    neighbor[index][0][1] = secondNeighbor0;
    neighbor[index][1][0] = firstNeighbor1;
    neighbor[index][1][1] = secondNeighbor1;
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
