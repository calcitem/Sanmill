/*********************************************************************
    millAI.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
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
void fieldStruct::printBoard()
{
    // locals
    unsigned int index;
    char c[SQUARE_NB];

    for (index = 0; index < SQUARE_NB; index++)
        c[index] = GetCharFromPiece(this->board[index]);

    cout << "current player          : "
         << GetCharFromPiece(this->curPlayer->id) << " has "
         << this->curPlayer->numPieces << " pieces\n";
    cout << "opponent player         : "
         << GetCharFromPiece(this->oppPlayer->id) << " has "
         << this->oppPlayer->numPieces << " pieces\n";
    cout << "Num Pieces to be removed: " << this->pieceMustBeRemoved << "\n";
    cout << "setting phase           : "
         << (this->settingPhase ? "true" : "false");
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
// GetCharFromPiece()
//
//-----------------------------------------------------------------------------
char fieldStruct::GetCharFromPiece(int piece)
{
    switch (piece) {
    case fieldStruct::playerOne:
        return 'o';
    case fieldStruct::playerTwo:
        return 'x';
    case fieldStruct::playerOneWarning:
        return '1';
    case fieldStruct::playerTwoWarning:
        return '2';
    case fieldStruct::playerBothWarning:
        return '3';
    case fieldStruct::squareIsFree:
        return ' ';
    }
    return 'f';
}

//-----------------------------------------------------------------------------
// copyBoard()
// Only copies the values without array creation.
//-----------------------------------------------------------------------------
void fieldStruct::copyBoard(fieldStruct *destination)
{
    unsigned int i, j;

    this->curPlayer->copyPlayer(destination->curPlayer);
    this->oppPlayer->copyPlayer(destination->oppPlayer);

    destination->piecesSet = this->piecesSet;
    destination->settingPhase = this->settingPhase;
    destination->pieceMustBeRemoved = this->pieceMustBeRemoved;

    for (i = 0; i < SQUARE_NB; i++) {
        destination->board[i] = this->board[i];
        destination->warnings[i] = this->warnings[i];
        destination->piecePartOfMill[i] = this->piecePartOfMill[i];

        for (j = 0; j < 4; j++) {
            destination->connectedSquare[i][j] = this->connectedSquare[i][j];
            destination->pieceMoveAble[i][j] = this->pieceMoveAble[i][j];
            destination->neighbour[i][j / 2][j % 2] =
                this->neighbour[i][j / 2][j % 2];
        }
    }
}

//-----------------------------------------------------------------------------
// copyPlayer()
// Only copies the values without array creation.
//-----------------------------------------------------------------------------
void Player::copyPlayer(Player *destination)
{
    unsigned int i;

    destination->numPiecesMissing = this->numPiecesMissing;
    destination->numPieces = this->numPieces;
    destination->id = this->id;
    destination->warning = this->warning;
    destination->numPossibleMoves = this->numPossibleMoves;

    for (i = 0; i < MAX_NUM_POS_MOVES; i++)
        destination->posFrom[i] = this->posFrom[i];

    for (i = 0; i < MAX_NUM_POS_MOVES; i++)
        destination->posTo[i] = this->posTo[i];
}

//-----------------------------------------------------------------------------
// createBoard()
// Creates, but doesn't initialize, the arrays of the of the passed board
// structure.
//-----------------------------------------------------------------------------
void fieldStruct::createBoard()
{
    // locals
    unsigned int i;

    curPlayer = new Player;
    oppPlayer = new Player;

    curPlayer->id = playerOne;
    piecesSet = 0;
    pieceMustBeRemoved = 0;
    settingPhase = true;
    curPlayer->warning = (curPlayer->id == playerOne) ? playerOneWarning :
                                                        playerTwoWarning;
    oppPlayer->id = (curPlayer->id == playerOne) ? playerTwo : playerOne;
    oppPlayer->warning = (curPlayer->id == playerOne) ? playerTwoWarning :
                                                        playerOneWarning;
    curPlayer->numPieces = 0;
    oppPlayer->numPieces = 0;
    curPlayer->numPossibleMoves = 0;
    oppPlayer->numPossibleMoves = 0;
    curPlayer->numPiecesMissing = 0;
    oppPlayer->numPiecesMissing = 0;

    // zero
    for (i = 0; i < SQUARE_NB; i++) {
        board[i] = squareIsFree;
        warnings[i] = noWarning;
        piecePartOfMill[i] = 0;
        pieceMoveAble[i][0] = false;
        pieceMoveAble[i][1] = false;
        pieceMoveAble[i][2] = false;
        pieceMoveAble[i][3] = false;
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
    setNeighbour(0, 1, 2, 9, 21);
    setNeighbour(1, 0, 2, 4, 7);
    setNeighbour(2, 0, 1, 14, 23);
    setNeighbour(3, 4, 5, 10, 18);
    setNeighbour(4, 1, 7, 3, 5);
    setNeighbour(5, 3, 4, 13, 20);
    setNeighbour(6, 7, 8, 11, 15);
    setNeighbour(7, 1, 4, 6, 8);
    setNeighbour(8, 6, 7, 12, 17);
    setNeighbour(9, 10, 11, 0, 21);
    setNeighbour(10, 9, 11, 3, 18);
    setNeighbour(11, 9, 10, 6, 15);
    setNeighbour(12, 13, 14, 8, 17);
    setNeighbour(13, 12, 14, 5, 20);
    setNeighbour(14, 12, 13, 2, 23);
    setNeighbour(15, 6, 11, 16, 17);
    setNeighbour(16, 15, 17, 19, 22);
    setNeighbour(17, 15, 16, 8, 12);
    setNeighbour(18, 3, 10, 19, 20);
    setNeighbour(19, 18, 20, 16, 22);
    setNeighbour(20, 5, 13, 18, 19);
    setNeighbour(21, 0, 9, 22, 23);
    setNeighbour(22, 16, 19, 21, 23);
    setNeighbour(23, 2, 14, 21, 22);
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
inline void fieldStruct::setConnection(unsigned int index, int firstDirection,
                                       int secondDirection, int thirdDirection,
                                       int fourthDirection)
{
    connectedSquare[index][0] = firstDirection;
    connectedSquare[index][1] = secondDirection;
    connectedSquare[index][2] = thirdDirection;
    connectedSquare[index][3] = fourthDirection;
}

//-----------------------------------------------------------------------------
// setNeighbour()
//
//-----------------------------------------------------------------------------
inline void fieldStruct::setNeighbour(unsigned int index,
                                      unsigned int firstNeighbour0,
                                      unsigned int secondNeighbour0,
                                      unsigned int firstNeighbour1,
                                      unsigned int secondNeighbour1)
{
    neighbour[index][0][0] = firstNeighbour0;
    neighbour[index][0][1] = secondNeighbour0;
    neighbour[index][1][0] = firstNeighbour1;
    neighbour[index][1][1] = secondNeighbour1;
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
