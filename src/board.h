/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef BOARD_H
#define BOARD_H

#include <vector>

#include "config.h"
#include "rule.h"
#include "types.h"

using namespace std;

class Board
{
public:
    Board();
    ~Board();

    Board & operator=(const Board &);

    static const int N_FILES = 3;
    static const int N_RANKS = 8;

    static const int MOVE_PRIORITY_TABLE_SIZE = Board::N_FILES * Board::N_RANKS;

    static const int onBoard[SQUARE_NB];

    static bool isStar(Square square);

    // Relate to Rule
    static int millTable[SQUARE_NB][LD_NB][N_FILES - 1];

    void createMillTable();

    void mirror(vector<string> &cmdlist, char *cmdline, int32_t move_, Square square, bool cmdChange = true);
    void turn(vector<string> &cmdlist, char *cmdline, int32_t move_, Square square, bool cmdChange = true);
    void rotate(int degrees, vector<string> &cmdlist, char *cmdline, int32_t move_, Square square, bool cmdChange = true);

    int inHowManyMills(Square square, Color c, Square squareSelected = SQ_0);
    bool isAllInMills(Color c);

    int getSurroundedEmptyLocationCount(Color sideToMove, int nPiecesOnBoard[], Square square, bool includeFobidden);
    void getSurroundedPieceCount(Square square, Color sideToMove, int &nOurPieces, int &nTheirPieces, int &nBanned, int &nEmpty);
    bool isAllSurrounded(Color sideToMove, int nPiecesOnBoard[]);

    int addMills(Square square);

    static void squareToPolar(Square square, File &file, Rank &rank);
    static Square polarToSquare(File file, Rank rank);

    static void printBoard();

    Color locationToColor(Square square);

//private:

    Piece locations[SQUARE_NB]{};

    Bitboard byTypeBB[PIECE_TYPE_NB];

    /*
        0x   00     00     00    00    00    00    00    00
           unused unused piece1 square1 piece2 square2 piece3 square3
    */

    uint64_t millList[4];
    int millListSize { 0 };
};

#endif
