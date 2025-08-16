#!/usr/bin/env python3
"""
阶段自检脚本：快速验证 3 个阶段（落子 / 走子 / 飞子）下的合法步生成与早停值域。

检查项概览：
1) Stage 1（仅落子）：
   - 初始局面仅生成落子（长度 2）走法
   - 当 put_pieces >= 18 且不在吃子期时，getGameEnded 返回早停值，且值域位于 [-0.5, 0.5]
2) Stage 2（走子不飞子）：
   - 在 period=1（走子期），所有走法均为相邻移动（长度 4 且相邻）
   - 在 period=2（飞子条件成立）时，因禁飞子，仍应回退为相邻移动（长度 4 且相邻）
3) Stage 3（全规则含飞子）：
   - 在 period=2（飞子条件成立）时，允许存在非相邻跳跃（长度 4 且非相邻）的飞子走法

使用方法：
  python validate_curriculum.py [--verbose]

断言失败会抛出异常并以非零码退出；通过则打印 OK 总结。
"""

import argparse
import sys
import numpy as np

from game.Game import Game
from game.GameLogic import Board
from game.standard_rules import xy_to_coord, adjacent


def _all_allowed_positions():
    pos = []
    for x in range(7):
        for y in range(7):
            if Board.allowed_places[x][y] == 1:
                pos.append((x, y))
    return pos


def _fill_board_pieces(board: Board, num_white: int, num_black: int):
    """在空棋盘上按顺序填入指定数量的白/黑子（不保证妙手，仅用于形态构造）。"""
    assert 0 <= num_white <= 9 and 0 <= num_black <= 9
    allowed = _all_allowed_positions()
    # 清空
    for x, y in allowed:
        board.pieces[x][y] = 0

    idx = 0
    for i in range(num_white):
        x, y = allowed[idx]
        board.pieces[x][y] = 1
        idx += 1
    for i in range(num_black):
        x, y = allowed[idx]
        board.pieces[x][y] = -1
        idx += 1


def _is_adjacent_move(move):
    """判断 4 元组走子是否相邻移动（依据标准邻接表）。"""
    assert isinstance(move, (list, tuple)) and len(move) == 4
    sx, sy, dx, dy = move
    s_coord = xy_to_coord.get((sx, sy))
    d_coord = xy_to_coord.get((dx, dy))
    if not s_coord or not d_coord:
        return False
    neighs = adjacent.get(s_coord, [])
    return d_coord in neighs


def check_stage1(verbose: bool = False):
    g = Game()
    g.set_curriculum(True, 1, stage1_heuristic_weight=0.03)

    # 仅落子：初始局面
    b = g.getInitBoard()
    assert b.period == 0, f"Stage1 初始 period 应为 0，实际 {b.period}"
    moves_w = b.get_legal_moves(1)
    moves_b = b.get_legal_moves(-1)
    assert len(moves_w) > 0 and len(moves_b) > 0, "Stage1 初始应存在可落子走法"
    assert all(len(m) == 2 for m in moves_w), "Stage1 白方应只生成长度 2 的落子走法"
    assert all(len(m) == 2 for m in moves_b), "Stage1 黑方应只生成长度 2 的落子走法"
    if verbose:
        print(f"[S1] init legal moves W={len(moves_w)} B={len(moves_b)}")

    # 早停值域：构造 put_pieces >= 18 且非吃子期
    b2 = g.getInitBoard()
    _fill_board_pieces(b2, 9, 9)  # 双方 9 子
    b2.put_pieces = 18
    b2.period = 1  # 非 3 均可触发早停
    r = g.getGameEnded(b2, 1)
    assert -0.5 <= r <= 0.5, f"Stage1 早停值应位于 [-0.5,0.5]，实际 {r}"
    assert abs(r) > 1e-8, f"Stage1 早停值不应为 0，实际 {r}"
    if verbose:
        print(f"[S1] early-stop value (P1) = {r:.4f}")


def check_stage2(verbose: bool = False):
    g = Game()
    g.set_curriculum(True, 2, stage1_heuristic_weight=0.03)

    # 走子期（period=1）：相邻移动
    b1 = g.getInitBoard()
    _fill_board_pieces(b1, 5, 5)
    b1.put_pieces = 18
    b1.period = 1
    assert b1.allow_flying is False, "Stage2 应禁用飞子 (allow_flying=False)"
    moves = b1.get_legal_moves(1)
    # 可能存在无子可动的局面，但此处构造了稀疏 5 vs 5，应当有走法
    assert all(len(m) == 4 for m in moves), "Stage2 period=1 走法应为长度 4"
    assert all(_is_adjacent_move(m) for m in moves), "Stage2 period=1 走法应为相邻移动"
    if verbose:
        print(f"[S2] period=1 adjacent moves = {len(moves)}")

    # 飞子条件（period=2）但禁飞：仍应回退为相邻移动
    b2 = g.getInitBoard()
    _fill_board_pieces(b2, 3, 6)  # 触发飞子条件：白方 <=3
    b2.put_pieces = 18
    b2.period = 2
    assert b2.allow_flying is False, "Stage2 period=2 也应禁飞"
    moves2 = b2.get_legal_moves(1)
    # 可能出现无路可走（被困）——允许为空；若非空，则必须是相邻移动
    assert all(len(m) == 4 for m in moves2), "Stage2 period=2 走法长度应为 4"
    assert all(_is_adjacent_move(m) for m in moves2), "Stage2 period=2 应回退为相邻移动（禁飞）"
    if verbose:
        print(f"[S2] period=2 fallback-adjacent moves = {len(moves2)}")


def check_stage3(verbose: bool = False):
    g = Game()
    g.set_curriculum(True, 3, stage1_heuristic_weight=0.03)

    # 飞子期（period=2）且允许飞子：应存在至少一个非相邻跳跃走法
    b = g.getInitBoard()
    _fill_board_pieces(b, 3, 6)  # 触发飞子条件：白方 <=3
    b.put_pieces = 18
    b.period = 2
    assert b.allow_flying is True, "Stage3 应允许飞子 (allow_flying=True)"
    moves = b.get_legal_moves(1)
    # 必须存在至少一个非相邻移动（飞子）
    has_fly = any(len(m) == 4 and not _is_adjacent_move(m) for m in moves)
    assert has_fly, "Stage3 period=2 应存在至少一个非相邻的飞子走法"
    if verbose:
        print(f"[S3] period=2 flying moves detected (total={len(moves)})")


def main():
    parser = argparse.ArgumentParser(description="阶段自检：验证各阶段合法步与早停值域")
    parser.add_argument("--verbose", action="store_true", help="打印详细检查信息")
    args = parser.parse_args()

    check_stage1(verbose=args.verbose)
    check_stage2(verbose=args.verbose)
    check_stage3(verbose=args.verbose)

    print("✅ Curriculum stages self-check passed: Stage1/2/3")


if __name__ == "__main__":
    main()


