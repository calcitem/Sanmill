#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later

import unittest

from scripts.mill_puzzle_objectives import (
    normalize_package,
    optimal_solver_move_count,
    validate_public_objectives,
)


class MillPuzzleObjectivesTest(unittest.TestCase):
    def test_removal_is_part_of_the_mill_forming_move(self) -> None:
        puzzle = {
            "id": "malom_movement_white_3_12345678",
            "title": "Win in 3: test",
            "description": "stale",
            "category": "winGame",
            "initialPosition": (
                "********/********/******** w p p "
                "0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes"
            ),
            "solutions": [
                {
                    "moves": [
                        {"notation": "a1", "side": "white"},
                        {"notation": "d1", "side": "black"},
                        {"notation": "a4", "side": "white"},
                        {"notation": "xa7", "side": "white"},
                    ],
                    "isOptimal": True,
                }
            ],
            "tags": ["win-in-3", "distance-band:short"],
        }

        self.assertEqual(optimal_solver_move_count(puzzle), 2)
        mapping = normalize_package({"puzzles": [puzzle]})
        self.assertEqual(
            mapping,
            {
                "malom_movement_white_3_12345678":
                    "malom_movement_white_2_12345678"
            },
        )
        self.assertEqual(puzzle["title"], "White · Win in 2: test")
        self.assertEqual(
            puzzle["description"],
            "White to move. Find the forced win in 2 moves.",
        )
        self.assertIn("win-in-2", puzzle["tags"])
        self.assertIn("objective:win", puzzle["tags"])
        self.assertEqual(validate_public_objectives([puzzle]), [])

    def test_optimal_lines_must_have_one_public_move_count(self) -> None:
        puzzle = {
            "id": "bad",
            "initialPosition": (
                "********/********/******** b p p "
                "0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes"
            ),
            "solutions": [
                {
                    "moves": [{"notation": "a1", "side": "black"}],
                    "isOptimal": True,
                },
                {
                    "moves": [
                        {"notation": "a4", "side": "black"},
                        {"notation": "d1", "side": "white"},
                        {"notation": "a7", "side": "black"},
                    ],
                    "isOptimal": True,
                },
            ],
        }

        with self.assertRaisesRegex(ValueError, "inconsistent optimal"):
            optimal_solver_move_count(puzzle)

    def test_hold_draw_contract_names_side_and_unique_turn(self) -> None:
        puzzle = {
            "id": "malom_draw_black_1_12345678",
            "title": "Black · Hold the draw: find the only defence",
            "description": (
                "Black to move. Find the only move that preserves the draw; "
                "every other legal move loses."
            ),
            "category": "defend",
            "initialPosition": (
                "********/********/******** b m s "
                "4 0 3 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes"
            ),
            "solutions": [
                {
                    "moves": [
                        {"notation": "d3-e3", "side": "black"},
                    ],
                    "isOptimal": True,
                }
            ],
            "tags": [
                "hold-draw-in-1",
                "objective:hold-draw",
                "unique-draw-save",
            ],
        }

        self.assertEqual(validate_public_objectives([puzzle]), [])
        puzzle["description"] = "Keep playing."
        self.assertEqual(
            validate_public_objectives([puzzle]),
            [
                "malom_draw_black_1_12345678 has inconsistent "
                "hold-draw description"
            ],
        )


if __name__ == "__main__":
    unittest.main()
