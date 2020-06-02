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
#include "location.h"
#include "rule.h"
#include "types.h"

using namespace std;

class Board
{
public:
    Board();
    ~Board();

    Board & operator=(const Board &);

    // 静态成员常量
    // 3圈，禁止修改!
    static const int N_RINGS = 3;

    // 8位，禁止修改!
    static const int N_SEATS = 8;

    static const int MOVE_PRIORITY_TABLE_SIZE = Board::N_RINGS * Board::N_SEATS;

    // 空棋盘点位，用于判断一个棋子位置是否在棋盘上
    static const int onBoard[SQ_EXPANDED_COUNT];

    // 判断位置点是否为星位 (星位是经常会先占的位置)
    static bool isStar(Square square);

    // 成三表，表示棋盘上各个位置有成三关系的对应位置表
    // 这个表跟规则有关，一旦规则改变需要重新修改
    static int millTable[SQ_EXPANDED_COUNT][LINE_TYPES_COUNT][N_RINGS - 1];

    // 生成成三表
    void createMillTable();

    // 局面左右镜像
    void mirror(vector<string> &cmdlist, char *cmdline, int32_t move_, Square square, bool cmdChange = true);

    // 局面内外翻转
    void turn(vector<string> &cmdlist, char *cmdline, int32_t move_, Square square, bool cmdChange = true);

    // 局面逆时针旋转
    void rotate(int degrees, vector<string> &cmdlist, char *cmdline, int32_t move_, Square square, bool cmdChange = true);

    // 判断棋盘 square 处的棋子处于几个“三连”中
    int inHowManyMills(Square square, player_t player, Square squareSelected = SQ_0);

    // 判断玩家的所有棋子是否都处于“三连”状态
    bool isAllInMills(player_t);

    // 判断玩家的棋子周围有几个空位
    int getSurroundedEmptyLocationCount(int sideId, int nPiecesOnBoard[], Square square, bool includeFobidden);

    // 计算指定位置周围有几个棋子
    void getSurroundedPieceCount(Square square, int sideId, int &nPlayerPiece, int &nOpponentPiece, int &nBanned, int &nEmpty);

    // 判断玩家的棋子是否全部被围
    bool isAllSurrounded(int sideId, int nPiecesOnBoard[], player_t ply);

    // 三连加入列表
    int addMills(Square square);

    // 将棋盘下标形式转化为第r圈，第s位，r和s下标都从1开始
    static void squareToPolar(Square square, File &r, Rank &s);

    // 将第c圈，第p位转化为棋盘下标形式，r和s下标都从1开始
    static Square polarToSquare(File r, Rank s);

    static void printBoard();

    player_t locationToPlayer(Square square);

//private:

    // 棋局，抽象为一个 5*8 的数组，上下两行留空
    /*
        0x00 代表无棋子
        0x0F 代表禁点
        0x11~0x1C 代表先手第 1~12 子
        0x21~0x2C 代表后手第 1~12 子
        判断棋子是先手的用 (locations[square] & 0x10)
        判断棋子是后手的用 (locations[square] & 0x20)
     */
    location_t locations[SQ_EXPANDED_COUNT]{};

    Bitboard byTypeBB[PIECE_TYPE_NB];

    /*
        本打算用如下的结构体来表示“三连”
        struct Mill {
            char piece1;    // “三连”中最小的棋子
            char square1;      // 最小棋子的位置
            char piece2;    // 次小的棋子
            char square2;      // 次小棋子的位置
            char piece3;    // 最大的棋子
            char square3;      // 最大棋子的位置
        };

        但为了提高执行效率改用一个64位整数了，规则如下
        0x   00     00     00    00    00    00    00    00
           unused unused piece1 square1 piece2 square2 piece3 square3
    */

    // 三连列表
    uint64_t millList[4];
    int millListSize { 0 };
};

#endif
