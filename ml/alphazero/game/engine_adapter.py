"""
Utilities to convert between Python board moves and Sanmill engine tokens.

Python side move formats:
- Placing/Capture: [x, y]
- Moving: [x0, y0, x1, y1]

Engine tokens (UCI-like):
- Placing: 'a1' .. 'g7'
- Moving: 'a1-a4'
- Removal: 'xg7'
"""

from typing import List
from .standard_rules import coord_to_xy, xy_to_coord


def move_to_engine_token(move: List[int]) -> str:
    if len(move) == 2:
        # place or remove decided by period externally; default as place
        x, y = move
        coord = xy_to_coord.get((x, y))
        if not coord:
            raise ValueError(f"Invalid place/remove target: {(x, y)}")
        return coord
    elif len(move) == 4:
        x0, y0, x1, y1 = move
        c0 = xy_to_coord.get((x0, y0))
        c1 = xy_to_coord.get((x1, y1))
        if not c0 or not c1:
            raise ValueError(f"Invalid move: {(x0, y0)} -> {(x1, y1)}")
        return f"{c0}-{c1}"
    else:
        raise ValueError("Move must have length 2 or 4")


def engine_token_to_move(token: str) -> List[int]:
    if token.startswith("x"):
        coord = token[1:]
        xy = coord_to_xy.get(coord)
        if not xy:
            raise ValueError(f"Invalid removal token: {token}")
        return [xy[0], xy[1]]
    if "-" in token:
        c0, c1 = token.split("-")
        p0 = coord_to_xy.get(c0)
        p1 = coord_to_xy.get(c1)
        if not p0 or not p1:
            raise ValueError(f"Invalid move token: {token}")
        return [p0[0], p0[1], p1[0], p1[1]]
    xy = coord_to_xy.get(token)
    if not xy:
        raise ValueError(f"Invalid placement token: {token}")
    return [xy[0], xy[1]]


