#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later

import unittest

from scripts.mill_puzzle_similarity import (
    PositionFingerprint,
    minimum_position_distance,
)


class MillPuzzleSimilarityTest(unittest.TestCase):
    def test_colour_exchange_and_solver_exchange_have_zero_distance(self):
        white_to_move = PositionFingerprint(
            white_bits=(1 << 0) | (1 << 4) | (1 << 9),
            black_bits=(1 << 2) | (1 << 7) | (1 << 12),
            white_in_hand=1,
            black_in_hand=2,
            side_to_move=0,
        )
        black_to_move = PositionFingerprint(
            white_bits=white_to_move.black_bits,
            black_bits=white_to_move.white_bits,
            white_in_hand=white_to_move.black_in_hand,
            black_in_hand=white_to_move.white_in_hand,
            side_to_move=1,
        )

        self.assertEqual(
            minimum_position_distance(white_to_move, black_to_move),
            0,
        )

    def test_moving_one_defender_piece_has_distance_two(self):
        left = PositionFingerprint(
            white_bits=(1 << 0) | (1 << 4) | (1 << 9),
            black_bits=(1 << 2) | (1 << 7) | (1 << 12),
            white_in_hand=0,
            black_in_hand=0,
            side_to_move=0,
        )
        right = PositionFingerprint(
            white_bits=left.white_bits,
            black_bits=(left.black_bits ^ (1 << 12)) | (1 << 13),
            white_in_hand=0,
            black_in_hand=0,
            side_to_move=0,
        )

        self.assertEqual(minimum_position_distance(left, right), 2)

    def test_hand_count_changes_contribute_to_distance(self):
        left = PositionFingerprint(1 << 0, 1 << 2, 0, 0, 0)
        right = PositionFingerprint(1 << 0, 1 << 2, 2, 1, 0)

        self.assertEqual(minimum_position_distance(left, right), 3)


if __name__ == "__main__":
    unittest.main()
