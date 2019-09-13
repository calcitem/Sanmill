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

#include "board.h"
#include "movegen.h"

 // 名义上是个数组，实际上相当于一个判断是否在棋盘上的函数
const int Board::onBoard[N_LOCATIONS] = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

// 成三表
int Board::millTable[N_LOCATIONS][LINE_TYPES_COUNT][N_RINGS - 1] = { {{0}} };

Board::Board()
{
}

Board::~Board()
{
    if (!millList.empty()) {
        millList.clear();
    }
}

Board &Board::operator= (const Board &other)
{
    if (this == &other)
        return *this;

    memcpy(this->locations, other.locations, sizeof(this->locations));

    if (!millList.empty()) {
        millList.clear();
    }

    if (!other.millList.empty()) {
        for (auto i : other.millList) {
            millList.push_back(i);
        }
    }

    return *this;
}

void Board::createMillTable(const Rule &currentRule)
{
    const int millTable_noObliqueLine[Board::N_LOCATIONS][LINE_TYPES_COUNT][2] = {
        /* 0 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 1 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 2 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 3 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 4 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 5 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 6 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 7 */ {{0, 0}, {0, 0}, {0, 0}},

        /* 8 */ {{16, 24}, {9, 15}, {0, 0}},
        /* 9 */ {{0, 0}, {15, 8}, {10, 11}},
        /* 10 */ {{18, 26}, {11, 9}, {0, 0}},
        /* 11 */ {{0, 0}, {9, 10}, {12, 13}},
        /* 12 */ {{20, 28}, {13, 11}, {0, 0}},
        /* 13 */ {{0, 0}, {11, 12}, {14, 15}},
        /* 14 */ {{22, 30}, {15, 13}, {0, 0}},
        /* 15 */ {{0, 0}, {13, 14}, {8, 9}},

        /* 16 */ {{8, 24}, {17, 23}, {0, 0}},
        /* 17 */ {{0, 0}, {23, 16}, {18, 19}},
        /* 18 */ {{10, 26}, {19, 17}, {0, 0}},
        /* 19 */ {{0, 0}, {17, 18}, {20, 21}},
        /* 20 */ {{12, 28}, {21, 19}, {0, 0}},
        /* 21 */ {{0, 0}, {19, 20}, {22, 23}},
        /* 22 */ {{14, 30}, {23, 21}, {0, 0}},
        /* 23 */ {{0, 0}, {21, 22}, {16, 17}},

        /* 24 */ {{8, 16}, {25, 31}, {0, 0}},
        /* 25 */ {{0, 0}, {31, 24}, {26, 27}},
        /* 26 */ {{10, 18}, {27, 25}, {0, 0}},
        /* 27 */ {{0, 0}, {25, 26}, {28, 29}},
        /* 28 */ {{12, 20}, {29, 27}, {0, 0}},
        /* 29 */ {{0, 0}, {27, 28}, {30, 31}},
        /* 30 */ {{14, 22}, {31, 29}, {0, 0}},
        /* 31 */ {{0, 0}, {29, 30}, {24, 25}},

        /* 32 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 33 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 34 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 35 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 36 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 37 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 38 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 39 */ {{0, 0}, {0, 0}, {0, 0}}
    };

    const int millTable_hasObliqueLines[Board::N_LOCATIONS][LINE_TYPES_COUNT][2] = {
        /*  0 */ {{0, 0}, {0, 0}, {0, 0}},
        /*  1 */ {{0, 0}, {0, 0}, {0, 0}},
        /*  2 */ {{0, 0}, {0, 0}, {0, 0}},
        /*  3 */ {{0, 0}, {0, 0}, {0, 0}},
        /*  4 */ {{0, 0}, {0, 0}, {0, 0}},
        /*  5 */ {{0, 0}, {0, 0}, {0, 0}},
        /*  6 */ {{0, 0}, {0, 0}, {0, 0}},
        /*  7 */ {{0, 0}, {0, 0}, {0, 0}},

        /*  8 */ {{16, 24}, {9, 15}, {0, 0}},
        /*  9 */ {{17, 25}, {15, 8}, {10, 11}},
        /* 10 */ {{18, 26}, {11, 9}, {0, 0}},
        /* 11 */ {{19, 27}, {9, 10}, {12, 13}},
        /* 12 */ {{20, 28}, {13, 11}, {0, 0}},
        /* 13 */ {{21, 29}, {11, 12}, {14, 15}},
        /* 14 */ {{22, 30}, {15, 13}, {0, 0}},
        /* 15 */ {{23, 31}, {13, 14}, {8, 9}},

        /* 16 */ {{8, 24}, {17, 23}, {0, 0}},
        /* 17 */ {{9, 25}, {23, 16}, {18, 19}},
        /* 18 */ {{10, 26}, {19, 17}, {0, 0}},
        /* 19 */ {{11, 27}, {17, 18}, {20, 21}},
        /* 20 */ {{12, 28}, {21, 19}, {0, 0}},
        /* 21 */ {{13, 29}, {19, 20}, {22, 23}},
        /* 22 */ {{14, 30}, {23, 21}, {0, 0}},
        /* 23 */ {{15, 31}, {21, 22}, {16, 17}},

        /* 24 */ {{8, 16}, {25, 31}, {0, 0}},
        /* 25 */ {{9, 17}, {31, 24}, {26, 27}},
        /* 26 */ {{10, 18}, {27, 25}, {0, 0}},
        /* 27 */ {{11, 19}, {25, 26}, {28, 29}},
        /* 28 */ {{12, 20}, {29, 27}, {0, 0}},
        /* 29 */ {{13, 21}, {27, 28}, {30, 31}},
        /* 30 */ {{14, 22}, {31, 29}, {0, 0}},
        /* 31 */ {{15, 23}, {29, 30}, {24, 25}},

        /* 32 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 33 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 34 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 35 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 36 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 37 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 38 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 39 */ {{0, 0}, {0, 0}, {0, 0}}
    };

    if (currentRule.hasObliqueLines) {
        memcpy(millTable, millTable_hasObliqueLines, sizeof(millTable));
    } else {
        memcpy(millTable, millTable_noObliqueLine, sizeof(millTable));
    }

#ifdef DEBUG_MODE
    for (int i = 0; i < N_LOCATIONS; i++) {
        loggerDebug("/* %d */ {", i);
        for (int j = 0; j < N_DIRECTIONS; j++) {
            loggerDebug("{");
            for (int k = 0; k < 2; k++) {
                if (k == 0) {
                    loggerDebug("%d, ", millTable[i][j][k]);
                } else {
                    loggerDebug("%d", millTable[i][j][k]);
                }

            }
            if (j == 2)
                loggerDebug("}");
            else
                loggerDebug("}, ");
        }
        loggerDebug("},\n");
    }

    loggerDebug("======== millTable End =========\n");
#endif /* DEBUG_MODE */
}

void Board::locationToPolar(const int location, int &r, int &s)
{
    //r = location / N_SEATS;
    //s = location % N_SEATS + 1;
    r = location >> 3;
    s = (location & 0x07) + 1;
}

int Board::polarToLocation(int r, int s)
{
    if (r < 1 || r > N_RINGS || s < 1 || s > N_SEATS) {
        return 0;
    }

    return r * N_SEATS + s - 1;
}


int Board::inHowManyMills(int location)
{
    int n = 0;
    int location1, location2;

    for (int l = 0; l < LINE_TYPES_COUNT; l++) {
        location1 = millTable[location][l][0];
        location2 = millTable[location][l][1];
        if ((locations[location] & 0x30) & locations[location1] & locations[location2]) {
            n++;
        }
    }

    return n;
}

int Board::addMills(const Rule &currentRule, int location)
{
    // 成三用一个64位整数了，规则如下
    // 0x   00     00     00    00    00    00    00    00
    //    unused unused piece1 location1 piece2 location2 piece3 pos3
    // piece1、piece2、piece3按照序号从小到大顺序排放
    uint64_t mill = 0;
    int n = 0;
    int p[3], min, temp;
    char m = locations[location] & '\x30';

    for (int i = 0; i < 3; i++) {
        p[0] = location;
        p[1] = millTable[location][i][0];
        p[2] = millTable[location][i][1];

        // 如果没有成三
        if (!(m & locations[p[1]] & locations[p[2]])) {
            continue;
        }

        // 如果成三

        // 排序
        for (int j = 0; j < 2; j++) {
            min = j;

            for (int k = j + 1; k < 3; k++) {
                if (p[min] > p[k])
                    min = k;
            }

            if (min == j) {
                continue;
            }

            temp = p[min];
            p[min] = p[j];
            p[j] = temp;
        }

        // 成三
        mill = (static_cast<uint64_t>(locations[p[0]]) << 40)
            + (static_cast<uint64_t>(p[0]) << 32)
            + (static_cast<uint64_t>(locations[p[1]]) << 24)
            + (static_cast<uint64_t>(p[1]) << 16)
            + (static_cast<uint64_t>(locations[p[2]]) << 8)
            + static_cast<uint64_t>(p[2]);

        // 如果允许相同三连反复去子
        if (currentRule.allowRemovePiecesRepeatedly) {
            n++;
            continue;
        }

        // 如果不允许相同三连反复去子

        // 迭代器
        auto iter = millList.begin();

        // 遍历
        for (iter = millList.begin(); iter != millList.end(); iter++) {
            if (mill == *iter)
                break;
        }

        // 如果没找到历史项
        if (iter == millList.end()) {
            n++;
            millList.push_back(mill);
        }
    }

    return n;
}

bool Board::isAllInMills(char ch)
{
    for (int i = LOCATION_BEGIN; i < LOCATION_END; i++) {
        if (locations[i] & ch) {
            if (!inHowManyMills(i)) {
                return false;
            }
        }
    }

    return true;
}

bool Board::isAllInMills(enum player_t player)
{
    char ch = 0x00;

    if (player == PLAYER_1)
        ch = 0x10;
    else if (player == PLAYER_2)
        ch = 0x20;
    else
        return true;

    return isAllInMills(ch);
}

// 判断玩家的棋子周围有几个空位
int Board::getSurroundedEmptyLocationCount(enum player_t turn, const Rule &currentRule, int nPiecesOnBoard_1, int nPiecesOnBoard_2, int location, bool includeFobidden)
{
    int count = 0;

    if ((turn == PLAYER_1 &&
        (nPiecesOnBoard_1 > currentRule.nPiecesAtLeast || !currentRule.allowFlyWhenRemainThreePieces)) ||
         (turn == PLAYER_2 &&
        (nPiecesOnBoard_2 > currentRule.nPiecesAtLeast || !currentRule.allowFlyWhenRemainThreePieces))) {
        int moveLocation;
        for (direction_t d = DIRECTION_BEGIN; d < DIRECTIONS_COUNT; d = (direction_t)(d + 1)) {
            moveLocation = MoveList::moveTable[location][d];
            if (moveLocation) {
                if (locations[moveLocation] == 0x00 ||
                    (includeFobidden && locations[moveLocation] == 0x0F)) {
                    count++;
                }
            }
        }
    }

    return count;
}

// 判断玩家的棋子是否被围
bool Board::isSurrounded(enum player_t turn, const Rule &currentRule, int nPiecesOnBoard_1, int nPiecesOnBoard_2, int location)
{
    // 判断location处的棋子是否被“闷”
    if ((turn == PLAYER_1 &&
        (nPiecesOnBoard_1 > currentRule.nPiecesAtLeast || !currentRule.allowFlyWhenRemainThreePieces)) ||
         (turn == PLAYER_2 &&
        (nPiecesOnBoard_2 > currentRule.nPiecesAtLeast || !currentRule.allowFlyWhenRemainThreePieces))) {
        int i, moveLocation;
        for (i = 0; i < 4; i++) {
            moveLocation = MoveList::moveTable[location][i];
            if (moveLocation && !locations[moveLocation])
                break;
        }
        // 被围住
        if (i == 4)
            return true;
    }
    // 没被围住
    return false;
}

bool Board::isAllSurrounded(enum player_t turn, const Rule &currentRule, int nPiecesOnBoard_1, int nPiecesOnBoard_2, char ch)
{
    // 如果摆满
    if (nPiecesOnBoard_1 + nPiecesOnBoard_2 >= N_SEATS * N_RINGS)
        return true;

    // 判断是否可以飞子
    if ((turn == PLAYER_1 &&
        (nPiecesOnBoard_1 <= currentRule.nPiecesAtLeast && currentRule.allowFlyWhenRemainThreePieces)) ||
         (turn == PLAYER_2 &&
        (nPiecesOnBoard_2 <= currentRule.nPiecesAtLeast && currentRule.allowFlyWhenRemainThreePieces))) {
        return false;
    }

    // 查询整个棋盘
    int moveLocation;
    for (int i = 1; i < N_SEATS * (N_RINGS + 1); i++) {
        if (!(ch & locations[i])) {
            continue;
        }

        for (direction_t d = DIRECTION_BEGIN; d < DIRECTIONS_COUNT; d = (direction_t)(d + 1)) {
            moveLocation = MoveList::moveTable[i][d];
            if (moveLocation && !locations[moveLocation])
                return false;
        }
    }

    return true;
}

// 判断玩家的棋子是否全部被围
bool Board::isAllSurrounded(enum player_t turn, const Rule &currentRule, int nPiecesOnBoard_1, int nPiecesOnBoard_2, enum player_t ply)
{
    char t = '\x30';

    if (ply == PLAYER_1)
        t &= '\x10';
    else if (ply == PLAYER_2)
        t &= '\x20';

    return isAllSurrounded(turn, currentRule, nPiecesOnBoard_1, nPiecesOnBoard_2, t);
}

enum player_t Board::getWhosPiece(int r, int s)
{
    int location = polarToLocation(r, s);

    if (locations[location] & '\x10')
        return PLAYER_1;

    if (locations[location] & '\x20')
        return PLAYER_2;

    return PLAYER_NOBODY;
}

// Unused
bool Board::getPieceRS(const player_t &player, const int &number, int &r, int &s, struct Rule &currentRule)
{
    int piece;

    if (player == PLAYER_1) {
        piece = 0x10;
    } else if (player == PLAYER_2) {
        piece = 0x20;
    } else {
        return false;
    }

    if (number > 0 && number <= currentRule.nTotalPiecesEachSide)
        piece &= number;
    else
        return false;

    for (int i = LOCATION_BEGIN; i < LOCATION_END; i++) {
        if (locations[i] == piece) {
            locationToPolar(i, r, s);
            return true;
        }
    }

    return false;
}

// 获取当前棋子
bool Board::getCurrentPiece(player_t &player, int &number, int location)
{
    if (!onBoard[location])
        return false;

    int p = locations[location];

    if (p & 0x10) {
        player = PLAYER_1;
        number = p - 0x10;
    } else if (p & 0x20) {
        player = PLAYER_2;
        number = p - 0x20;
    } else {
        return false;
    }

    return true;
}

void Board::mirror(list <string> &cmdlist, char* cmdline, int32_t move_, struct Rule &currentRule, int location, bool cmdChange /*= true*/)
{
    int ch;
    int r, s;
    int i;

    for (r = 1; r <= N_RINGS; r++) {
        for (s = 1; s < N_SEATS / 2; s++) {
            ch = locations[r * N_SEATS + s];
            locations[r * N_SEATS + s] = locations[(r + 1) * N_SEATS - s];
            //updateHash(i * N_SEATS + j);
            locations[(r + 1) * N_SEATS - s] = ch;
            //updateHash((i + 1) * N_SEATS - j);
        }
    }

    uint64_t llp[3] = { 0 };

    if (move_ < 0) {
        r = (-move_) / N_SEATS;
        s = (-move_) % N_SEATS;
        s = (N_SEATS - s) % N_SEATS;
        move_ = -(r * N_SEATS + s);
    } else {
        llp[0] = static_cast<uint64_t>(move_ >> 8);
        llp[1] = move_ & 0x00ff;

        for (i = 0; i < 2; i++) {
            r = static_cast<int>(llp[i]) / N_SEATS;
            s = static_cast<int>(llp[i]) % N_SEATS;
            s = (N_SEATS - s) % N_SEATS;
            llp[i] = (static_cast<uint64_t>(r) * N_SEATS + s);
        }

        move_ = static_cast<int16_t>(((llp[0] << 8) | llp[1]));
    }

    if (location != 0) {
        r = location / N_SEATS;
        s = location % N_SEATS;
        s = (N_SEATS - s) % N_SEATS;
        location = r * N_SEATS + s;
    }

    if (currentRule.allowRemovePiecesRepeatedly) {
        for (auto &mill : millList) {
            llp[0] = (mill & 0x000000ff00000000) >> 32;
            llp[1] = (mill & 0x0000000000ff0000) >> 16;
            llp[2] = (mill & 0x00000000000000ff);

            for (i = 0; i < 3; i++) {
                r = static_cast<int>(llp[i]) / N_SEATS;
                s = static_cast<int>(llp[i]) % N_SEATS;
                s = (N_SEATS - s) % N_SEATS;
                llp[i] = static_cast<uint64_t>(r * N_SEATS + s);
            }

            mill &= 0xffffff00ff00ff00;
            mill |= (llp[0] << 32) | (llp[1] << 16) | llp[2];
        }
    }

    // 命令行解析
    if (cmdChange) {
        int r1, s1, r2, s2;
        int args = 0;
        int mm = 0, ss = 0;

        args = sscanf(cmdline, "(%1u,%1u)->(%1u,%1u) %2u:%2u", &r1, &s1, &r2, &s2, &mm, &ss);
        if (args >= 4) {
            s1 = (N_SEATS - s1 + 1) % N_SEATS;
            s2 = (N_SEATS - s2 + 1) % N_SEATS;
            cmdline[3] = '1' + static_cast<char>(s1);
            cmdline[10] = '1' + static_cast<char>(s2);
        } else {
            args = sscanf(cmdline, "-(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
            if (args >= 2) {
                s1 = (N_SEATS - s1 + 1) % N_SEATS;
                cmdline[4] = '1' + static_cast<char>(s1);
            } else {
                args = sscanf(cmdline, "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
                if (args >= 2) {
                    s1 = (N_SEATS - s1 + 1) % N_SEATS;
                    cmdline[3] = '1' + static_cast<char>(s1);
                }
            }
        }

        for (auto &iter : cmdlist) {
            args = sscanf(iter.c_str(), "(%1u,%1u)->(%1u,%1u) %2u:%2u", &r1, &s1, &r2, &s2, &mm, &ss);
            if (args >= 4) {
                s1 = (N_SEATS - s1 + 1) % N_SEATS;
                s2 = (N_SEATS - s2 + 1) % N_SEATS;
                iter[3] = '1' + static_cast<char>(s1);
                iter[10] = '1' + static_cast<char>(s2);
            } else {
                args = sscanf(iter.c_str(), "-(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
                if (args >= 2) {
                    s1 = (N_SEATS - s1 + 1) % N_SEATS;
                    iter[4] = '1' + static_cast<char>(s1);
                } else {
                    args = sscanf(iter.c_str(), "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
                    if (args >= 2) {
                        s1 = (N_SEATS - s1 + 1) % N_SEATS;
                        iter[3] = '1' + static_cast<char>(s1);
                    }
                }
            }
        }
    }
}

void Board::turn(list <string> &cmdlist, char *cmdline, int32_t move_, const Rule &currentRule, int location, bool cmdChange /*= true*/)
{
    int ch;
    int r, s;
    int i;

    for (s = 0; s < N_SEATS; s++) {
        ch = locations[N_SEATS + s];
        locations[N_SEATS + s] = locations[N_SEATS * N_RINGS + s];
        //updateHash(N_SEATS + s);
        locations[N_SEATS * N_RINGS + s] = ch;
        //updateHash(N_SEATS * N_RINGS + s);
    }

    uint64_t llp[3] = { 0 };

    if (move_ < 0) {
        r = (-move_) / N_SEATS;
        s = (-move_) % N_SEATS;

        if (r == 1)
            r = N_RINGS;
        else if (r == N_RINGS)
            r = 1;

        move_ = -(r * N_SEATS + s);
    } else {
        llp[0] = static_cast<uint64_t>(move_ >> 8);
        llp[1] = move_ & 0x00ff;

        for (i = 0; i < 2; i++) {
            r = static_cast<int>(llp[i]) / N_SEATS;
            s = static_cast<int>(llp[i]) % N_SEATS;

            if (r == 1)
                r = N_RINGS;
            else if (r == N_RINGS)
                r = 1;

            llp[i] = static_cast<uint64_t>(r * N_SEATS + s);
        }

        move_ = static_cast<int16_t>(((llp[0] << 8) | llp[1]));
    }

    if (location != 0) {
        r = location / N_SEATS;
        s = location % N_SEATS;

        if (r == 1)
            r = N_RINGS;
        else if (r == N_RINGS)
            r = 1;

        location = r * N_SEATS + s;
    }

    if (currentRule.allowRemovePiecesRepeatedly) {
        for (auto &mill : millList) {
            llp[0] = (mill & 0x000000ff00000000) >> 32;
            llp[1] = (mill & 0x0000000000ff0000) >> 16;
            llp[2] = (mill & 0x00000000000000ff);

            for (i = 0; i < 3; i++) {
                r = static_cast<int>(llp[i]) / N_SEATS;
                s = static_cast<int>(llp[i]) % N_SEATS;

                if (r == 1)
                    r = N_RINGS;
                else if (r == N_RINGS)
                    r = 1;

                llp[i] = static_cast<uint64_t>(r * N_SEATS + s);
            }

            mill &= 0xffffff00ff00ff00;
            mill |= (llp[0] << 32) | (llp[1] << 16) | llp[2];
        }
    }

    // 命令行解析
    if (cmdChange) {
        int r1, s1, r2, s2;
        int args = 0;
        int mm = 0, ss = 0;

        args = sscanf(cmdline, "(%1u,%1u)->(%1u,%1u) %2u:%2u",
                      &r1, &s1, &r2, &s2, &mm, &ss);

        if (args >= 4) {
            if (r1 == 1)
                r1 = N_RINGS;
            else if (r1 == N_RINGS)
                r1 = 1;

            if (r2 == 1)
                r2 = N_RINGS;
            else if (r2 == N_RINGS)
                r2 = 1;

            cmdline[1] = '0' + static_cast<char>(r1);
            cmdline[8] = '0' + static_cast<char>(r2);
        } else {
            args = sscanf(cmdline, "-(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
            if (args >= 2) {
                if (r1 == 1)
                    r1 = N_RINGS;
                else if (r1 == N_RINGS)
                    r1 = 1;
                cmdline[2] = '0' + static_cast<char>(r1);
            } else {
                args = sscanf(cmdline, "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
                if (args >= 2) {
                    if (r1 == 1)
                        r1 = N_RINGS;
                    else if (r1 == N_RINGS)
                        r1 = 1;
                    cmdline[1] = '0' + static_cast<char>(r1);
                }
            }
        }

        for (auto &iter : cmdlist) {
            args = sscanf(iter.c_str(),
                          "(%1u,%1u)->(%1u,%1u) %2u:%2u",
                          &r1, &s1, &r2, &s2, &mm, &ss);

            if (args >= 4) {
                if (r1 == 1)
                    r1 = N_RINGS;
                else if (r1 == N_RINGS)
                    r1 = 1;

                if (r2 == 1)
                    r2 = N_RINGS;
                else if (r2 == N_RINGS)
                    r2 = 1;

                iter[1] = '0' + static_cast<char>(r1);
                iter[8] = '0' + static_cast<char>(r2);
            } else {
                args = sscanf(iter.c_str(), "-(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
                if (args >= 2) {
                    if (r1 == 1)
                        r1 = N_RINGS;
                    else if (r1 == N_RINGS)
                        r1 = 1;

                    iter[2] = '0' + static_cast<char>(r1);
                } else {
                    args = sscanf(iter.c_str(), "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
                    if (args >= 2) {
                        if (r1 == 1)
                            r1 = N_RINGS;
                        else if (r1 == N_RINGS)
                            r1 = 1;

                        iter[1] = '0' + static_cast<char>(r1);
                    }
                }
            }
        }
    }
}

void Board::rotate(int degrees, list <string> &cmdlist, char *cmdline, int32_t move_, const Rule &currentRule, int location, bool cmdChange /*= true*/)
{
    // 将degrees转化为0~359之间的数
    degrees = degrees % 360;

    if (degrees < 0)
        degrees += 360;

    if (degrees == 0 || degrees % 90)
        return;

    degrees /= 45;

    int ch1, ch2;
    int r, s;
    int i;

    if (degrees == 2) {
        for (r = 1; r <= N_RINGS; r++) {
            ch1 = locations[r * N_SEATS];
            ch2 = locations[r * N_SEATS + 1];

            for (s = 0; s < N_SEATS - 2; s++) {
                locations[r * N_SEATS + s] = locations[r * N_SEATS + s + 2];
            }

            locations[r * N_SEATS + 6] = ch1;
            //updateHash(i * N_SEATS + 6);
            locations[r * N_SEATS + 7] = ch2;
            //updateHash(i * N_SEATS + 7);
        }
    } else if (degrees == 6) {
        for (r = 1; r <= N_RINGS; r++) {
            ch1 = locations[r * N_SEATS + 7];
            ch2 = locations[r * N_SEATS + 6];

            for (s = N_SEATS - 1; s >= 2; s--) {
                locations[r * N_SEATS + s] = locations[r * N_SEATS + s - 2];
                //updateHash(i * N_SEATS + j);
            }

            locations[r * N_SEATS + 1] = ch1;
            //updateHash(i * N_SEATS + 1);
            locations[r * N_SEATS] = ch2;
            //updateHash(i * N_SEATS);
        }
    } else if (degrees == 4) {
        for (r = 1; r <= N_RINGS; r++) {
            for (s = 0; s < N_SEATS / 2; s++) {
                ch1 = locations[r * N_SEATS + s];
                locations[r * N_SEATS + s] = locations[r * N_SEATS + s + 4];
                //updateHash(i * N_SEATS + j);
                locations[r * N_SEATS + s + 4] = ch1;
                //updateHash(i * N_SEATS + j + 4);
            }
        }
    } else {
        return;
    }

    uint64_t llp[3] = { 0 };

    if (move_ < 0) {
        r = (-move_) / N_SEATS;
        s = (-move_) % N_SEATS;
        s = (s + N_SEATS - degrees) % N_SEATS;
        move_ = -(r * N_SEATS + s);
    } else {
        llp[0] = static_cast<uint64_t>(move_ >> 8);
        llp[1] = move_ & 0x00ff;
        r = static_cast<int>(llp[0]) / N_SEATS;
        s = static_cast<int>(llp[0]) % N_SEATS;
        s = (s + N_SEATS - degrees) % N_SEATS;
        llp[0] = static_cast<uint64_t>(r * N_SEATS + s);
        r = static_cast<int>(llp[1]) / N_SEATS;
        s = static_cast<int>(llp[1]) % N_SEATS;
        s = (s + N_SEATS - degrees) % N_SEATS;
        llp[1] = static_cast<uint64_t>(r * N_SEATS + s);
        move_ = static_cast<int16_t>(((llp[0] << 8) | llp[1]));
    }

    if (location != 0) {
        r = location / N_SEATS;
        s = location % N_SEATS;
        s = (s + N_SEATS - degrees) % N_SEATS;
        location = r * N_SEATS + s;
    }

    if (currentRule.allowRemovePiecesRepeatedly) {
        for (auto &mill : millList) {
            llp[0] = (mill & 0x000000ff00000000) >> 32;
            llp[1] = (mill & 0x0000000000ff0000) >> 16;
            llp[2] = (mill & 0x00000000000000ff);

            for (i = 0; i < 3; i++) {
                r = static_cast<int>(llp[i]) / N_SEATS;
                s = static_cast<int>(llp[i]) % N_SEATS;
                s = (s + N_SEATS - degrees) % N_SEATS;
                llp[i] = static_cast<uint64_t>(r * N_SEATS + s);
            }

            mill &= 0xffffff00ff00ff00;
            mill |= (llp[0] << 32) | (llp[1] << 16) | llp[2];
        }
    }

    // 命令行解析
    if (cmdChange) {
        int r1, s1, r2, s2;
        int args = 0;
        int mm = 0, ss = 0;

        args = sscanf(cmdline, "(%1u,%1u)->(%1u,%1u) %2u:%2u", &r1, &s1, &r2, &s2, &mm, &ss);
        if (args >= 4) {
            s1 = (s1 - 1 + N_SEATS - degrees) % N_SEATS;
            s2 = (s2 - 1 + N_SEATS - degrees) % N_SEATS;
            cmdline[3] = '1' + static_cast<char>(s1);
            cmdline[10] = '1' + static_cast<char>(s2);
        } else {
            args = sscanf(cmdline, "-(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);

            if (args >= 2) {
                s1 = (s1 - 1 + N_SEATS - degrees) % N_SEATS;
                cmdline[4] = '1' + static_cast<char>(s1);
            } else {
                args = sscanf(cmdline, "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);

                if (args >= 2) {
                    s1 = (s1 - 1 + N_SEATS - degrees) % N_SEATS;
                    cmdline[3] = '1' + static_cast<char>(s1);
                }
            }
        }

        for (auto &iter : cmdlist) {
            args = sscanf(iter.c_str(), "(%1u,%1u)->(%1u,%1u) %2u:%2u", &r1, &s1, &r2, &s2, &mm, &ss);

            if (args >= 4) {
                s1 = (s1 - 1 + N_SEATS - degrees) % N_SEATS;
                s2 = (s2 - 1 + N_SEATS - degrees) % N_SEATS;
                iter[3] = '1' + static_cast<char>(s1);
                iter[10] = '1' + static_cast<char>(s2);
            } else {
                args = sscanf(iter.c_str(), "-(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);

                if (args >= 2) {
                    s1 = (s1 - 1 + N_SEATS - degrees) % N_SEATS;
                    iter[4] = '1' + static_cast<char>(s1);
                } else {
                    args = sscanf(iter.c_str(), "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
                    if (args >= 2) {
                        s1 = (s1 - 1 + N_SEATS - degrees) % N_SEATS;
                        iter[3] = '1' + static_cast<char>(s1);
                    }
                }
            }
        }
    }
}
