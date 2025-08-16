"""
Standard Nine Men's Morris rules: coordinates, adjacency and mill triplets.

This module defines:
- coord_to_xy: mapping from standard engine coordinates (a1..g7) to 7x7 grid
- xy_to_coord: inverse mapping
- adjacent: neighbors for single-step moves (no diagonal lines)
- mills: all three-in-a-row combinations

Coordinate system follows the engine's UCI mapping (see src/uci.cpp):
  Inner:  c3,c4,c5,d3,d5,e3,e4,e5
  Middle: b2,b4,b6,d2,d6,f2,f4,f6
  Outer:  a1,a4,a7,d1,d7,g1,g4,g7

Grid coordinates (x, y) range in [0, 6], top-left is (0, 0).
"""

from typing import Dict, List, Tuple


# Coordinate <-> 7x7 grid mapping
coord_to_xy: Dict[str, Tuple[int, int]] = {
    # Outer ring
    "a7": (0, 0), "d7": (3, 0), "g7": (6, 0),
    "g4": (6, 3), "g1": (6, 6), "d1": (3, 6), "a1": (0, 6), "a4": (0, 3),
    # Middle ring
    "b6": (1, 1), "d6": (3, 1), "f6": (5, 1),
    "f4": (5, 3), "f2": (5, 5), "d2": (3, 5), "b2": (1, 5), "b4": (1, 3),
    # Inner ring
    "c5": (2, 2), "d5": (3, 2), "e5": (4, 2),
    "e4": (4, 3), "e3": (4, 4), "d3": (3, 4), "c3": (2, 4), "c4": (2, 3),
}

xy_to_coord: Dict[Tuple[int, int], str] = {v: k for k, v in coord_to_xy.items()}


# Adjacency (no diagonal lines)
# Each entry lists neighbors reachable in one step
adjacent: Dict[str, List[str]] = {
    # Outer ring
    "a7": ["d7", "a4"],
    "d7": ["d6", "g7", "a7"],
    "g7": ["g4", "d7"],
    "g4": ["f4", "g1", "g7"],
    "g1": ["d1", "g4"],
    "d1": ["d2", "a1", "g1"],
    "a1": ["a4", "d1"],
    "a4": ["b4", "a7", "a1"],
    # Middle ring
    "b6": ["d6", "b4"],
    "d6": ["d5", "d7", "f6", "b6"],
    "f6": ["f4", "d6"],
    "f4": ["e4", "g4", "f2", "f6"],
    "f2": ["d2", "f4"],
    "d2": ["d3", "d1", "b2", "f2"],
    "b2": ["b4", "d2"],
    "b4": ["c4", "a4", "b6", "b2"],
    # Inner ring
    "c5": ["d5", "c4"],
    "d5": ["d6", "e5", "c5"],
    "e5": ["e4", "d5"],
    "e4": ["f4", "e3", "e5"],
    "e3": ["d3", "e4"],
    "d3": ["d2", "c3", "e3"],
    "c3": ["c4", "d3"],
    "c4": ["b4", "c5", "c3"],
}


# All mill triplets (three-in-a-row), no diagonals
mills: List[Tuple[str, str, str]] = [
    # Horizontal
    ("a7", "d7", "g7"),
    ("b6", "d6", "f6"),
    ("c5", "d5", "e5"),
    ("a4", "b4", "c4"),
    ("e4", "f4", "g4"),
    ("c3", "d3", "e3"),
    ("b2", "d2", "f2"),
    ("a1", "d1", "g1"),
    # Vertical
    ("a7", "a4", "a1"),
    ("b6", "b4", "b2"),
    ("c5", "c4", "c3"),
    ("d7", "d6", "d5"),
    ("d3", "d2", "d1"),
    ("e5", "e4", "e3"),
    ("f6", "f4", "f2"),
    ("g7", "g4", "g1"),
]


