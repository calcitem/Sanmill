// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// types_test.cpp

#include "gtest/gtest.h"

#include "types.h"

namespace {

TEST(TypesTest, toggleColor)
{
    EXPECT_EQ(~WHITE, BLACK);
    EXPECT_EQ(~BLACK, WHITE);
}

TEST(TypesTest, makeSquare)
{
    EXPECT_EQ(make_square(FILE_A, RANK_1), SQ_8);
    EXPECT_EQ(make_square(FILE_A, RANK_2), SQ_9);
    EXPECT_EQ(make_square(FILE_A, RANK_3), SQ_10);
    EXPECT_EQ(make_square(FILE_A, RANK_4), SQ_11);
    EXPECT_EQ(make_square(FILE_A, RANK_5), SQ_12);
    EXPECT_EQ(make_square(FILE_A, RANK_6), SQ_13);
    EXPECT_EQ(make_square(FILE_A, RANK_7), SQ_14);
    EXPECT_EQ(make_square(FILE_A, RANK_8), SQ_15);

    EXPECT_EQ(make_square(FILE_B, RANK_1), SQ_16);
    EXPECT_EQ(make_square(FILE_B, RANK_2), SQ_17);
    EXPECT_EQ(make_square(FILE_B, RANK_3), SQ_18);
    EXPECT_EQ(make_square(FILE_B, RANK_4), SQ_19);
    EXPECT_EQ(make_square(FILE_B, RANK_5), SQ_20);
    EXPECT_EQ(make_square(FILE_B, RANK_6), SQ_21);
    EXPECT_EQ(make_square(FILE_B, RANK_7), SQ_22);
    EXPECT_EQ(make_square(FILE_B, RANK_8), SQ_23);

    EXPECT_EQ(make_square(FILE_C, RANK_1), SQ_24);
    EXPECT_EQ(make_square(FILE_C, RANK_2), SQ_25);
    EXPECT_EQ(make_square(FILE_C, RANK_3), SQ_26);
    EXPECT_EQ(make_square(FILE_C, RANK_4), SQ_27);
    EXPECT_EQ(make_square(FILE_C, RANK_5), SQ_28);
    EXPECT_EQ(make_square(FILE_C, RANK_6), SQ_29);
    EXPECT_EQ(make_square(FILE_C, RANK_7), SQ_30);
    EXPECT_EQ(make_square(FILE_C, RANK_8), SQ_31);
}

TEST(TypesTest, makePiece)
{
    EXPECT_EQ(make_piece(WHITE), W_PIECE);
    EXPECT_EQ(make_piece(BLACK), B_PIECE);

    EXPECT_EQ(make_piece(WHITE, WHITE_PIECE), W_PIECE);
    EXPECT_EQ(make_piece(BLACK, WHITE_PIECE), B_PIECE);
    EXPECT_EQ(make_piece(NOCOLOR, MARKED), MARKED_PIECE);
}

TEST(TypesTest, colorOf)
{
    EXPECT_EQ(color_of(W_PIECE), WHITE);
    EXPECT_EQ(color_of(B_PIECE), BLACK);
}

TEST(TypesTest, isOk)
{
    EXPECT_TRUE(is_ok(SQ_NONE));
    EXPECT_FALSE(is_ok(SQ_7));
    EXPECT_TRUE(is_ok(SQ_8));
    EXPECT_TRUE(is_ok(SQ_16));
    EXPECT_TRUE(is_ok(SQ_24));
    EXPECT_TRUE(is_ok(SQ_31));
    EXPECT_FALSE(is_ok(SQ_32));
    EXPECT_FALSE(is_ok(SQ_33));
    EXPECT_FALSE(is_ok(SQ_39));

    EXPECT_FALSE(is_ok(make_move(SQ_8, SQ_8)));
}

TEST(TypesTest, fileOf)
{
    EXPECT_EQ(file_of(SQ_8), FILE_A);
    EXPECT_EQ(file_of(SQ_9), FILE_A);
    EXPECT_EQ(file_of(SQ_10), FILE_A);
    EXPECT_EQ(file_of(SQ_11), FILE_A);
    EXPECT_EQ(file_of(SQ_12), FILE_A);
    EXPECT_EQ(file_of(SQ_13), FILE_A);
    EXPECT_EQ(file_of(SQ_14), FILE_A);
    EXPECT_EQ(file_of(SQ_15), FILE_A);

    EXPECT_EQ(file_of(SQ_16), FILE_B);
    EXPECT_EQ(file_of(SQ_17), FILE_B);
    EXPECT_EQ(file_of(SQ_18), FILE_B);
    EXPECT_EQ(file_of(SQ_19), FILE_B);
    EXPECT_EQ(file_of(SQ_20), FILE_B);
    EXPECT_EQ(file_of(SQ_21), FILE_B);
    EXPECT_EQ(file_of(SQ_22), FILE_B);
    EXPECT_EQ(file_of(SQ_23), FILE_B);

    EXPECT_EQ(file_of(SQ_24), FILE_C);
    EXPECT_EQ(file_of(SQ_25), FILE_C);
    EXPECT_EQ(file_of(SQ_26), FILE_C);
    EXPECT_EQ(file_of(SQ_27), FILE_C);
    EXPECT_EQ(file_of(SQ_28), FILE_C);
    EXPECT_EQ(file_of(SQ_29), FILE_C);
    EXPECT_EQ(file_of(SQ_30), FILE_C);
    EXPECT_EQ(file_of(SQ_31), FILE_C);
}

TEST(TypesTest, rankOf)
{
    EXPECT_EQ(rank_of(SQ_8), RANK_1);
    EXPECT_EQ(rank_of(SQ_9), RANK_2);
    EXPECT_EQ(rank_of(SQ_10), RANK_3);
    EXPECT_EQ(rank_of(SQ_11), RANK_4);
    EXPECT_EQ(rank_of(SQ_12), RANK_5);
    EXPECT_EQ(rank_of(SQ_13), RANK_6);
    EXPECT_EQ(rank_of(SQ_14), RANK_7);
    EXPECT_EQ(rank_of(SQ_15), RANK_8);

    EXPECT_EQ(rank_of(SQ_16), RANK_1);
    EXPECT_EQ(rank_of(SQ_17), RANK_2);
    EXPECT_EQ(rank_of(SQ_18), RANK_3);
    EXPECT_EQ(rank_of(SQ_19), RANK_4);
    EXPECT_EQ(rank_of(SQ_20), RANK_5);
    EXPECT_EQ(rank_of(SQ_21), RANK_6);
    EXPECT_EQ(rank_of(SQ_22), RANK_7);
    EXPECT_EQ(rank_of(SQ_23), RANK_8);

    EXPECT_EQ(rank_of(SQ_24), RANK_1);
    EXPECT_EQ(rank_of(SQ_25), RANK_2);
    EXPECT_EQ(rank_of(SQ_26), RANK_3);
    EXPECT_EQ(rank_of(SQ_27), RANK_4);
    EXPECT_EQ(rank_of(SQ_28), RANK_5);
    EXPECT_EQ(rank_of(SQ_29), RANK_6);
    EXPECT_EQ(rank_of(SQ_30), RANK_7);
    EXPECT_EQ(rank_of(SQ_31), RANK_8);
}

TEST(TypesTest, makeMove)
{
    Move m = MOVE_NONE;
    Square originFrom = SQ_NONE;
    Square originTo = SQ_NONE;
    Square from = SQ_NONE;
    Square to = SQ_NONE;

    originFrom = SQ_8;
    originTo = SQ_9;
    m = make_move(originFrom, originTo);
    from = from_sq(m);
    to = to_sq(m);
    EXPECT_EQ(from, originFrom);
    EXPECT_EQ(to, originTo);

    originFrom = SQ_23;
    originTo = SQ_31;
    m = make_move(originFrom, originTo);
    from = from_sq(m);
    to = to_sq(m);
    EXPECT_EQ(from, originFrom);
    EXPECT_EQ(to, originTo);

    originFrom = SQ_20;
    originTo = SQ_28;
    m = make_move(originFrom, originTo);
    from = from_sq(m);
    to = to_sq(m);
    EXPECT_EQ(from, originFrom);
    EXPECT_EQ(to, originTo);
}

TEST(TypesTest, reverseMove)
{
    EXPECT_EQ(reverse_move(make_move(SQ_8, SQ_9)), make_move(SQ_9, SQ_8));
    EXPECT_EQ(reverse_move(make_move(SQ_30, SQ_31)), make_move(SQ_31, SQ_30));
}

} // namespace
