/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019 Calcitem <calcitem@outlook.com>

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

#include "board.h"
#include "movegen.h"

 // 名义上是个数组，实际上相当于一个判断是否在棋盘上的函数
const int Board::onBoard[SQ_EXPANDED_COUNT] = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

// 成三表
int Board::millTable[SQ_EXPANDED_COUNT][LINE_TYPES_COUNT][N_RINGS - 1] = { {{0}} };

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
    memcpy(this->locations, other.locations, sizeof(this->locations));

    // TODO: 确定 millList 确实不用复制?

    return *this;
}

void Board::createMillTable()
{
    const int millTable_noObliqueLine[SQ_EXPANDED_COUNT][LINE_TYPES_COUNT][2] = {
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

    const int millTable_hasObliqueLines[SQ_EXPANDED_COUNT][LINE_TYPES_COUNT][2] = {
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

    if (rule.hasObliqueLines) {
        memcpy(millTable, millTable_hasObliqueLines, sizeof(millTable));
    } else {
        memcpy(millTable, millTable_noObliqueLine, sizeof(millTable));
    }

#ifdef DEBUG_MODE
    for (int i = 0; i < SQ_EXPANDED_COUNT; i++) {
        loggerDebug("/* %d */ {", i);
        for (int j = 0; j < DIRECTIONS_COUNT; j++) {
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

void Board::squareToPolar(const square_t square, int &r, int &s)
{
    //r = square / N_SEATS;
    //s = square % N_SEATS + 1;
    r = square >> 3;
    s = (square & 0x07) + 1;
}

square_t Board::polarToSquare(int r, int s)
{
    assert(!(r < 1 || r > N_RINGS || s < 1 || s > N_SEATS));

    return static_cast<square_t>(r * N_SEATS + s - 1);
}

int Board::inHowManyMills(square_t square)
{
    int n = 0;

    for (int l = 0; l < LINE_TYPES_COUNT; l++) {
        if ((locations[square] & 0x30) &
            locations[millTable[square][l][0]] &
            locations[millTable[square][l][1]]) {
            n++;
        }
    }

    return n;
}

int Board::inHowManyMills(square_t square, player_t player)
{
    int n = 0;

    for (int l = 0; l < LINE_TYPES_COUNT; l++) {
        if (player &
            locations[millTable[square][l][0]] &
            locations[millTable[square][l][1]]) {
            n++;
        }
    }

    return n;
}

int Board::addMills(square_t square)
{
    // 成三用一个64位整数了，规则如下
    // 0x   00     00     00    00    00    00    00    00
    //    unused unused piece1 square1 piece2 square2 piece3 pos3
    // piece1、piece2、piece3按照序号从小到大顺序排放
    uint64_t mill = 0;
    int n = 0;
    int idx[3], min, temp;
    char m = locations[square] & 0x30;

    for (int i = 0; i < 3; i++) {
        idx[0] = square;
        idx[1] = millTable[square][i][0];
        idx[2] = millTable[square][i][1];

        // 如果没有成三
        if (!(m & locations[idx[1]] & locations[idx[2]])) {
            continue;
        }

        // 如果成三

        // 排序
        for (int j = 0; j < 2; j++) {
            min = j;

            for (int k = j + 1; k < 3; k++) {
                if (idx[min] > idx[k])
                    min = k;
            }

            if (min == j) {
                continue;
            }

            temp = idx[min];
            idx[min] = idx[j];
            idx[j] = temp;
        }

        // 成三
        mill = (static_cast<uint64_t>(locations[idx[0]]) << 40)
            + (static_cast<uint64_t>(idx[0]) << 32)
            + (static_cast<uint64_t>(locations[idx[1]]) << 24)
            + (static_cast<uint64_t>(idx[1]) << 16)
            + (static_cast<uint64_t>(locations[idx[2]]) << 8)
            + static_cast<uint64_t>(idx[2]);

        // 如果允许相同三连反复去子
        if (rule.allowRemovePiecesRepeatedly) {
            n++;
            continue;
        }

        // 如果不允许相同三连反复去子

        // 迭代器
        auto iter = millList.begin();

        // 遍历
        for ( ; iter != millList.end(); iter++) {
            if (mill == *iter) {
                break;
            }
        }

        // 如果没找到历史项
        if (iter == millList.end()) {
            n++;
            millList.push_back(mill);
        }
    }

    return n;
}

bool Board::isAllInMills(player_t player)
{
    for (square_t i = SQ_BEGIN; i < SQ_END; i = static_cast<square_t>(i + 1)) {
        if (locations[i] & (uint8_t)player) {
            if (!inHowManyMills(i)) {
                return false;
            }
        }
    }

    return true;
}

// 判断指定位置周围有几个空位 (可以包含禁点一起统计)
int Board::getSurroundedEmptyLocationCount(int sideId, int nPiecesOnBoard[],
                                           square_t square, bool includeFobidden)
{
    //assert(rule.hasForbiddenLocations == includeFobidden);

    int count = 0;

    if (nPiecesOnBoard[sideId] > rule.nPiecesAtLeast ||
        !rule.allowFlyWhenRemainThreePieces) {
        square_t moveSquare;
        for (direction_t d = DIRECTION_BEGIN; d < DIRECTIONS_COUNT; d = (direction_t)(d + 1)) {
            moveSquare = static_cast<square_t>(MoveList::moveTable[square][d]);
            if (moveSquare) {
                if (locations[moveSquare] == 0x00 ||
                    (includeFobidden && locations[moveSquare] == PIECE_FORBIDDEN)) {
                    count++;
                }
            }
        }
    }

    return count;
}

// 计算指定位置周围有几个棋子
void Board::getSurroundedPieceCount(square_t square, int sideId, int &nPlayerPiece, int &nOpponentPiece, int &nForbidden, int &nEmpty)
{
    square_t moveSquare;

    for (direction_t d = DIRECTION_BEGIN; d < DIRECTIONS_COUNT; d = (direction_t)(d + 1)) {
        moveSquare = static_cast<square_t>(MoveList::moveTable[square][d]);

        if (!moveSquare) {
            continue;
        }

        enum piece_t pieceType = static_cast<piece_t>(locations[moveSquare]);

        switch (pieceType) {
        case NO_PIECE:
            nEmpty++;
            break;
        case PIECE_FORBIDDEN:
            nForbidden++;
            break;
        default:
            if (sideId == pieceType >> PLAYER_SHIFT) {
                nPlayerPiece++;
            } else {
                nOpponentPiece++;
            }
            break;
        }
    }
}

// 判断玩家的棋子是否被围
bool Board::isSurrounded(int sideId, int nPiecesOnBoard[], square_t square)
{
    int i;
    square_t moveSquare;

    // 判断square处的棋子是否被“闷”
    if (nPiecesOnBoard[sideId] > rule.nPiecesAtLeast ||
        !rule.allowFlyWhenRemainThreePieces) {
        for (i = 0; i < 4; i++) {
            moveSquare = static_cast<square_t>(MoveList::moveTable[square][i]);
            if (moveSquare && !locations[moveSquare])
                break;
        }

        // 被围住
        if (i == 4) {
            return true;
        }
    }
    // 没被围住
    return false;
}

bool Board::isAllSurrounded(int sideId, int nPiecesOnBoard[], char ch)
{
    // 如果摆满
    if (nPiecesOnBoard[BLACK] + nPiecesOnBoard[WHITE] >= N_SEATS * N_RINGS)
        return true;

    // 判断是否可以飞子
    if (nPiecesOnBoard[sideId] <= rule.nPiecesAtLeast &&
        rule.allowFlyWhenRemainThreePieces) {
        return false;
    }

    // 查询整个棋盘
    square_t moveSquare;
    int locend = N_SEATS * (N_RINGS + 1);

    for (int i = 1; i < locend; i++) {
        if (!(ch & locations[i])) {
            continue;
        }

        for (direction_t d = DIRECTION_BEGIN; d < DIRECTIONS_COUNT; d = (direction_t)(d + 1)) {
            moveSquare = static_cast<square_t>(MoveList::moveTable[i][d]);
            if (moveSquare && !locations[moveSquare]) {
                return false;
            }
        }
    }

    return true;
}

// 判断玩家的棋子是否全部被围
bool Board::isAllSurrounded(int sideId, int nPiecesOnBoard[], player_t player)
{
    char t = 0x30 & player; // 非 chSide

    return isAllSurrounded(sideId, nPiecesOnBoard, t);
}

#if 0
player_t Board::getWhosPiece(int r, int s)
{
    square_t square = polarToSquare(r, s);

    if (locations[square] & PLAYER_BLACK)
        return PLAYER_BLACK;

    if (locations[square] & PLAYER_WHITE)
        return PLAYER_WHITE;

    return PLAYER_NOBODY;
}

bool Board::getPieceRS(const player_t &player, const int &number, int &r, int &s, struct Rule &rule)
{
    int piece;

    if (player == PLAYER_BLACK) {
        piece = PIECE_BLACK;
    } else if (player == PLAYER_WHITE) {
        piece = PIECE_WHITE;
    } else {
        return false;
    }

    if (number > 0 && number <= rule.nTotalPiecesEachSide)
        piece &= number;
    else
        return false;

    for (int i = SQ_BEGIN; i < SQ_END; i++) {
        if (locations[i] == piece) {
            squareToPolar(i, r, s);
            return true;
        }
    }

    return false;
}

// 获取当前棋子
bool Board::getCurrentPiece(player_t &player, int &number, square_t square)
{
    if (!onBoard[square])
        return false;

    int p = locations[square];

    if (p & PIECE_BLACK) {
        player = PLAYER_BLACK;
        number = p - PIECE_BLACK;
    } else if (p & PIECE_WHITE) {
        player = PLAYER_WHITE;
        number = p - PIECE_WHITE;
    } else {
        return false;
    }

    return true;
}
#endif

bool Board::isStar(square_t square)
{
    if (rule.nTotalPiecesEachSide == 12) {
        return (square == 17 ||
                square == 19 ||
                square == 21 ||
                square == 23);
    }

    return (square == 16 ||
            square == 18 ||
            square == 20 ||
            square == 22);
}

void Board::mirror(vector<string> &cmdlist, char* cmdline, int32_t move_, square_t square, bool cmdChange /*= true*/)
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

    if (square != 0) {
        r = square / N_SEATS;
        s = square % N_SEATS;
        s = (N_SEATS - s) % N_SEATS;
        square = static_cast<square_t>(r * N_SEATS + s);
    }

    if (rule.allowRemovePiecesRepeatedly) {
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

void Board::turn(vector <string> &cmdlist, char *cmdline, int32_t move_, square_t square, bool cmdChange /*= true*/)
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

    if (square != 0) {
        r = square / N_SEATS;
        s = square % N_SEATS;

        if (r == 1)
            r = N_RINGS;
        else if (r == N_RINGS)
            r = 1;

        square = static_cast<square_t>(r * N_SEATS + s);
    }

    if (rule.allowRemovePiecesRepeatedly) {
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

void Board::rotate(int degrees, vector<string> &cmdlist, char *cmdline, int32_t move_, square_t square, bool cmdChange /*= true*/)
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

    if (square != 0) {
        r = square / N_SEATS;
        s = square % N_SEATS;
        s = (s + N_SEATS - degrees) % N_SEATS;
        square = static_cast<square_t>(r * N_SEATS + s);
    }

    if (rule.allowRemovePiecesRepeatedly) {
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

void Board::printBoard()
{
    if (rule.nTotalPiecesEachSide == 12) {
        loggerDebug("\n"
            "31 ----- 24 ----- 25\n"
            "| \\       |      / |\n"
            "|  23 -- 16 -- 17  |\n"
            "|  | \\    |   / |  |\n"
            "|  |  15-08-09  |  |\n"
            "30-22-14    10-18-26\n"
            "|  |  13-12-11  |  |\n"
            "|  | /    |   \\ |  |\n"
            "|  21 -- 20 -- 19  |\n"
            "| /       |      \\ |\n"
            "29 ----- 28 ----- 27\n"
            "\n");
    } else {
        loggerDebug("\n"
            "31 ----- 24 ----- 25\n"
            "|         |        |\n"
            "|  23 -- 16 -- 17  |\n"
            "|  |      |     |  |\n"
            "|  |  15-08-09  |  |\n"
            "30-22-14    10-18-26\n"
            "|  |  13-12-11  |  |\n"
            "|  |      |     |  |\n"
            "|  21 -- 20 -- 19  |\n"
            "|         |        |\n"
            "29 ----- 28 ----- 27\n"
            "\n");
    }
}
