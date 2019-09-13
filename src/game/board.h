/*****************************************************************************
 * Copyright (C) 2018-2019 MillGame authors
 *
 * Authors: liuweilhy <liuweilhy@163.com>
 *          Calcitem <calcitem@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

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

    // 静态成员常量
    // 3圈，禁止修改!
    static const int N_RINGS = 3;

    // 8位，禁止修改!
    static const int N_SEATS = 8;

    // 棋盘点的个数：40
    static const int N_LOCATIONS = (Board::N_RINGS + 2) * Board::N_SEATS;

    // 遍历棋盘点所用的起始位置，即 [8, 32)
    static const int LOCATION_BEGIN = N_SEATS;
    static const int LOCATION_END = ((N_RINGS + 1) * N_SEATS);

    // 空棋盘点位，用于判断一个棋子位置是否在棋盘上
    static const int onBoard[N_LOCATIONS];

    // 判断位置点是否为星位 (星位是经常会先占的位置)
    static bool isStarLocation(int location);

    // 成三表，表示棋盘上各个位置有成三关系的对应位置表
    // 这个表跟规则有关，一旦规则改变需要重新修改
    static int millTable[N_LOCATIONS][LINE_TYPES_COUNT][N_RINGS - 1];

    // 生成成三表
    void createMillTable(const Rule &currentRule);

    // 局面左右镜像
    void mirror(list <string> &cmdlist, char *cmdline, int32_t move_, struct Rule &currentRule, int currentPos, bool cmdChange = true);

    // 局面内外翻转
    void turn(list <string> &cmdlist, char *cmdline, int32_t move_, const Rule &currentRule, int currentPos, bool cmdChange = true);

    // 局面逆时针旋转
    void rotate(int degrees, list <string> &cmdlist, char *cmdline, int32_t move_, const Rule &currentRule, int currentPos, bool cmdChange = true);

    // 判断棋盘location处的棋子处于几个“三连”中
    int inHowManyMills(int location);

    // 判断玩家的所有棋子是否都处于“三连”状态
    bool isAllInMills(char ch);
    bool isAllInMills(enum player_t);

    // 判断玩家的棋子周围有几个空位
    int getSurroundedEmptyLocationCount(enum player_t turn, const Rule &currentRule, int nPiecesOnBoard_1, int nPiecesOnBoard_2, int location, bool includeFobidden);

    // 判断玩家的棋子是否被围
    bool isSurrounded(enum player_t turn, const Rule &currentRule, int nPiecesOnBoard_1, int nPiecesOnBoard_2, int location);

    // 判断玩家的棋子是否全部被围
    bool isAllSurrounded(enum player_t turn, const Rule &currentRule, int nPiecesOnBoard_1, int nPiecesOnBoard_2, char ch);

    bool isAllSurrounded(enum player_t turn, const Rule &currentRule, int nPiecesOnBoard_1, int nPiecesOnBoard_2, enum player_t ply);

    // 三连加入列表
    int addMills(const Rule &currentRule, int location);

    // 获取位置点棋子的归属人
    enum player_t getWhosPiece(int r, int s);

    bool getPieceRS(const player_t &player, const int &number, int &r, int &s, struct Rule &currentRule);

    // 获取当前棋子
    bool getCurrentPiece(player_t &player, int &number, int currentPos);

    // 将棋盘下标形式转化为第r圈，第s位，r和s下标都从1开始
    void locationToPolar(int location, int &r, int &s);

    // 将第c圈，第p位转化为棋盘下标形式，r和s下标都从1开始
    int polarToLocation(int r, int s);

//private:

    // 棋局，抽象为一个 5*8 的数组，上下两行留空
    /*
        0x00 代表无棋子
        0x0F 代表禁点
        0x11~0x1C 代表先手第 1~12 子
        0x21~0x2C 代表后手第 1~12 子
        判断棋子是先手的用 (location[i] & 0x10)
        判断棋子是后手的用 (location[i] & 0x20)
     */
    int locations[N_LOCATIONS]{};

    /*
        本打算用如下的结构体来表示“三连”
        struct Mill {
            char piece1;    // “三连”中最小的棋子
            char location1;      // 最小棋子的位置
            char piece2;    // 次小的棋子
            char location2;      // 次小棋子的位置
            char piece3;    // 最大的棋子
            char location3;      // 最大棋子的位置
        };

        但为了提高执行效率改用一个64位整数了，规则如下
        0x   00     00     00    00    00    00    00    00
           unused unused piece1 location1 piece2 location2 piece3 location3
    */

    // 三连列表
    vector<uint64_t> millList;
};

#endif
