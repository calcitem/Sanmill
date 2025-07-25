// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_adaptor.cpp

#include <condition_variable>
#include <mutex>
#include <sstream>
#include <stdexcept>

#include "config.h"

#include "misc.h"
#include "option.h"
#include "perfect_adaptor.h"
#include "perfect_api.h"
#include "perfect_errors.h"
#include "perfect_wrappers.h"
#include "position.h"

#ifdef GABOR_MALOM_PERFECT_AI
#define USE_DEPRECATED_CLR_API_WITHOUT_WARNING

extern int ruleVariant;
extern int maxKsz;

static Move malomRemoveMove = MOVE_NONE;
static Value malomRemoveValue = VALUE_UNKNOWN;

static std::condition_variable cv;

int get_best_move(int whiteBitboard, int blackBitboard, int whiteStonesToPlace,
                  int blackStonesToPlace, int playerToMove,
                  bool onlyStoneTaking, Value &value, const Move &refMove)
{
    return MalomSolutionAccess::get_best_move(whiteBitboard, blackBitboard,
                                              whiteStonesToPlace,
                                              blackStonesToPlace, playerToMove,
                                              onlyStoneTaking, value, refMove);
}

int perfect_init()
{
    malomRemoveMove = MOVE_NONE;
    malomRemoveValue = VALUE_UNKNOWN;

    if (rule.pieceCount == 9) {
        ruleVariant = (int)Wrappers::Constants::Variants::std;
    } else if (rule.pieceCount == 12) {
        ruleVariant = (int)Wrappers::Constants::Variants::mora;
    } else if (rule.pieceCount == 10) {
        ruleVariant = (int)Wrappers::Constants::Variants::lask;
    } else {
        // TODO: Throw exception
        ruleVariant = (int)Wrappers::Constants::Variants::std;
    }

    switch (ruleVariant) {
    case (int)Wrappers::Constants::Variants::std:
        ruleVariantName = "std";
        maxKsz = 9;
        field2Offset = 12;
        break;
    case (int)Wrappers::Constants::Variants::mora:
        ruleVariantName = "mora";
        maxKsz = 12;
        field2Offset = 14;
        break;
    case (int)Wrappers::Constants::Variants::lask:
        ruleVariantName = "lask";
        maxKsz = 10;
        field2Offset = 14;
        break;
    default:
        assert(false);
        break;
    }

#ifdef FULL_SECTOR_GRAPH
    int maxKsz = 12;
#endif

    field1Size = field2Offset;
    field2Size = 8 * eval_struct_size - field2Offset;
    secValMinValue = -(1 << (field1Size - 1));

    sectors.resize(maxKsz + 1);
    for (int i = 0; i <= maxKsz; ++i) {
        sectors[i].resize(maxKsz + 1);
        for (int j = 0; j <= maxKsz; ++j) {
            sectors[i][j].resize(maxKsz + 1);
            for (int k = 0; k <= maxKsz; ++k) {
                sectors[i][j][k].resize(maxKsz + 1);
            }
        }
    }

    return 0;
}

int perfect_exit()
{
    malomRemoveMove = MOVE_NONE;
    malomRemoveValue = VALUE_UNKNOWN;

    return 0;
}

int perfect_reset()
{
    return perfect_init();
}

Square from_perfect_square(uint32_t sq)
{
    constexpr Square map[] = {SQ_30, SQ_31, SQ_24, SQ_25, SQ_26, SQ_27, SQ_28,
                              SQ_29, SQ_22, SQ_23, SQ_16, SQ_17, SQ_18, SQ_19,
                              SQ_20, SQ_21, SQ_14, SQ_15, SQ_8,  SQ_9,  SQ_10,
                              SQ_11, SQ_12, SQ_13, SQ_0};

    return map[sq];
}

int to_perfect_square(Square sq)
{
    constexpr int map[] = {
        -1, -1, -1, -1, -1, -1, -1, -1,
        18, 19, 20, 21, 22, 23, 16, 17, /* 8 - 15 */
        10, 11, 12, 13, 14, 15, 8,  9,  /* 16 - 23 */
        2,  3,  4,  5,  6,  7,  0,  1,  /* 24 - 31 */
        -1, -1, -1, -1, -1, -1, -1, -1,
    };

    return map[sq];
}

size_t count_bits(int n)
{
    int count = 0;
    while (n) {
        n &= (n - 1);
        count++;
    }
    return count;
}

std::vector<Move> convert_bitboard_move(int whiteBitboard, int blackBitboard,
                                        int playerToMove, int moveBitboard)
{
    std::vector<Move> moves;
    int usBitboard = playerToMove == 0 ? whiteBitboard : blackBitboard;
    int themBitboard = playerToMove == 1 ? whiteBitboard : blackBitboard;
    size_t count = count_bits(moveBitboard);

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
                    moves.push_back(Move(from_perfect_square(i)));
                    return moves;
                } else if (hasPiece) {
                    if (themHasPiece) {
                        // Only remove their piece
                        moves.push_back(Move(-from_perfect_square(i)));
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
                make_move(from_perfect_square(from), from_perfect_square(to)));
        } else if (from == -1 && to != -1 && removed != -1) {
            // Place and remove piece
            moves.push_back(Move(from_perfect_square(to)));
            moves.push_back(Move(-from_perfect_square(removed)));
        }
    } else if (count == 3) {
        moves.push_back(
            make_move(from_perfect_square(from), from_perfect_square(to)));
        moves.push_back(Move(-from_perfect_square(removed)));
    } else {
        assert(false);
    }

    assert(moves.size() <= count);

    return moves;
}

Value perfect_search(const Position *pos, Move &move)
{
    using namespace PerfectErrors;

    clearError(); // Clear any previous errors

    Value value = VALUE_UNKNOWN;

    // TODO: Now always return only the first move
    // from the engine, whether it's two moves or one. This means the action
    // for 'removing' is recalculated, which might reduce performance but
    // ensures accuracy. Additionally, when two moves are returned, the result
    // of 'removing' from the second move might differ from that obtained
    // through a new search.
    if (malomRemoveMove != MOVE_NONE) {
        // Move ret = malomRemoveMove;
        value = malomRemoveValue;
        malomRemoveMove = MOVE_NONE;
        malomRemoveValue = VALUE_UNKNOWN;
        // move = ret;
        // return value;
    }

    std::vector<Move> moves;

    // The white stones on the board, encoded as a bitboard:
    // Each of the first 24 bits corresponds to one place on the board.
    // For the mapping between bits, see Bitboard.png.
    // For example, the integer number 131 means that there is a vertical mill
    // on the left side of the board, because 131 = 1 + 2 + 128.
    int whiteBitboard = 0;

    // The black stones on the board.
    int blackBitboard = 0;

    for (int i = 0; i < 24; i++) {
        auto c = color_of(pos->board[from_perfect_square(i)]);
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
    // Using error codes instead of exceptions for better performance
    int moveBitboard = MalomSolutionAccess::get_best_move(
        whiteBitboard, blackBitboard, whiteStonesToPlace, blackStonesToPlace,
        playerToMove, onlyStoneTaking, value, move);

    // Check for error condition (0 indicates error)
    if (moveBitboard == 0) {
        move = MOVE_NONE;
        return VALUE_UNKNOWN;
    }

    moves = convert_bitboard_move(whiteBitboard, blackBitboard, playerToMove,
                                  moveBitboard);

    if (moves.size() == 2) {
        malomRemoveMove = (moves.size() > 1) ? moves[1] : Move();
        malomRemoveValue = value;
    }

    move = moves.empty() ? MOVE_NONE : Move(moves[0]);

    return value;
}

#endif // GABOR_MALOM_PERFECT_AI
