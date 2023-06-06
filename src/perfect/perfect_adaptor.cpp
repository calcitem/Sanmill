// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.


#include <condition_variable>
#include <mutex>
#include <sstream>
#include <stdexcept>

#include "config.h"

#include "misc.h"
#include "option.h"
#include "perfect_adaptor.h"
#include "position.h"
#include "perfect_api.h"

#ifdef GABOR_MALOM_PERFECT_AI
#define USE_DEPRECATED_CLR_API_WITHOUT_WARNING

static Move malom_remove_move = MOVE_NONE;

static std::mutex mtx;
static std::condition_variable cv;

int GetBestMove(int whiteBitboard, int blackBitboard, int whiteStonesToPlace,
                int blackStonesToPlace, int playerToMove, bool onlyStoneTaking)
{
    return MalomSolutionAccess::getBestMove(whiteBitboard, blackBitboard,
                                            whiteStonesToPlace,
                                            blackStonesToPlace, playerToMove,
                                            onlyStoneTaking);
}

int perfect_init()
{
    malom_remove_move = MOVE_NONE;

    return 0;
}

int perfect_exit()
{
    malom_remove_move = MOVE_NONE;

    return 0;
}

int perfect_reset()
{
    
    perfect_init();

    return 0;
}

Square from_perfect_sq(uint32_t sq)
{
    constexpr Square map[] = {SQ_30, SQ_31, SQ_24, SQ_25, SQ_26, SQ_27, SQ_28,
                              SQ_29, SQ_22, SQ_23, SQ_16, SQ_17, SQ_18, SQ_19,
                              SQ_20, SQ_21, SQ_14, SQ_15, SQ_8,  SQ_9,  SQ_10,
                              SQ_11, SQ_12, SQ_13, SQ_0};

    return map[sq];
}

#if 0
unsigned to_perfect_sq(Square sq)
{
    constexpr int map[] = {
        -1, -1, -1, -1, -1, -1, -1, -1,
        18,  19,  20, 21, 22, 23, 16, 17, /* 8 - 15 */
        10,  11,  12, 13, 14, 15, 8, 9, /* 16 - 23 */
        2,  3,  4, 5, 6, 7, 0,  1, /* 24 - 31 */
        -1, -1, -1, -1, -1, -1, -1, -1,
    };

    return map[sq];
}
#endif

int countBits(int n)
{
    int count = 0;
    while (n) {
        n &= (n - 1);
        count++;
    }
    return count;
}

std::vector<Move> convertBitboardMove(int whiteBitboard, int blackBitboard,
                                      int playerToMove, int moveBitboard)
{
    std::vector<Move> moves;
    int usBitboard = playerToMove == 0 ? whiteBitboard : blackBitboard;
    int themBitboard = playerToMove == 1 ? whiteBitboard : blackBitboard;
    int count = countBits(moveBitboard);

    int from = -1;
    int to = -1;
    int removed = -1;

    for (int i = 0; i < 24; ++i) {
        int mask = 1 << i;
        bool usHasPiece = usBitboard & mask;
        bool themHasPiece = themBitboard & mask;
        bool noPiece = !usHasPiece && !themHasPiece;
        bool hasPiece = !noPiece;
        bool changed = moveBitboard & mask;

        if (changed) {
            if (count == 1) {
                if (noPiece) {
                    // The stone is placed here
                    moves.push_back(Move(from_perfect_sq(i)));
                    return moves;
                } else if (hasPiece) {
                    if (themHasPiece) {
                        // Only remove their piece
                        moves.push_back(Move(-from_perfect_sq(i)));
                        return moves;
                    } else if (usHasPiece) {
                        // Only remove our piece, not move
                        assert(false);
                    }
                }
            } else if (count == 2 || count == 3) {
                if (hasPiece) {
                    if (usHasPiece) {
                        from = i;
                    } else if (themHasPiece) {
                        // Remove their piece
                        removed = i;
                    }
                } else if (noPiece) {
                    to = i;
                }
            } else {
                assert(false);
            }
        }
    }

    if (count == 2) {
        if (from != -1 && to != -1 && removed == -1) {
            // Move
            moves.push_back(
                make_move(from_perfect_sq(from), from_perfect_sq(to)));
        } else if (from == -1 && to != -1 && removed != -1) {
            // Place and remove piece
            moves.push_back(Move(from_perfect_sq(to)));
            moves.push_back(Move(-from_perfect_sq(removed)));
        }
    } else if (count == 3) {
        moves.push_back(make_move(from_perfect_sq(from), from_perfect_sq(to)));
        moves.push_back(Move(-from_perfect_sq(removed)));
    } else {
        assert(false);
    }

    assert(moves.size() <= count);

    return moves;
}

Move perfect_search(Position *pos)
{
    if (malom_remove_move != MOVE_NONE) {
        Move ret = malom_remove_move;
        malom_remove_move = MOVE_NONE;
        return ret;
    }

    // The white stones on the board, encoded as a bitboard:
    // Each of the first 24 bits corresponds to one place on the board.
    // For the mapping between bits, see Bitboard.png.
    // For example, the integer number 131 means that there is a vertical mill
    // on the left side of the board, because 131 = 1 + 2 + 128.
    int whiteBitboard = 0;

    // The black stones on the board.
    int blackBitboard = 0;

    for (int i = 0; i < 24; i++) {
        auto c = color_of(pos->board[from_perfect_sq(i)]);
        if (c == WHITE) {
            whiteBitboard |= 1 << i;
        } else if (c == BLACK) {
            blackBitboard |= 1 << i;
        }
    }

    // The number of stones the white player can still place on the board.
    int whiteStonesToPlace = pos->piece_in_hand_count(WHITE);

    // The number of stones the black player can still place on the board.
    int blackStonesToPlace = pos->piece_in_hand_count(BLACK);

    // 0 if white is to move, 1 if black is to move.
    int playerToMove = pos->side_to_move() == WHITE ? 0 : 1;

    // Always set this to false if you want to handle
    // mill-closing and stone-removal as a single move.
    // If you set it to true, it is assumed that a mill was just closed
    // and only the stone to be removed is returned.
    bool onlyStoneTaking = (pos->piece_to_remove_count(pos->side_to_move()) >
                            0);

    // Return value:
    // The move is returned as a bitboard,
    // which has a bit set for each change on the board:
    // - If the place corresponding to a set bit is empty,
    //   then a stone of the player to move appears there.
    // - If the place corresponding to a set bit currently has a stone,
    //   then that stone disappears. (If it's a stone of the opponent,
    //   then this move involves a stone-removal.
    //   If it's a stone of the player to move,
    //   then this is a sliding or jumping move,
    //   and that stone is being slided or jumped to a different place.)
    // If this increases the number of stones the player to move has,
    // then that player will have one less stone to place after the move.
    int moveBitboard = GetBestMove(whiteBitboard, blackBitboard,
                                   whiteStonesToPlace, blackStonesToPlace,
                                   playerToMove, onlyStoneTaking);

    std::vector<Move> moves = convertBitboardMove(whiteBitboard, blackBitboard,
                                                  playerToMove, moveBitboard);

    if (moves.size() == 2) {
        malom_remove_move = moves.at(1);
    }

    return Move(moves.at(0));
}

#endif // GABOR_MALOM_PERFECT_AI
