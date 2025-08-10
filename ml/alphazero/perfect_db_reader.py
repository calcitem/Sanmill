import ctypes
import os
from typing import List, Tuple

from game.standard_rules import xy_to_coord


# Square(8..31) -> standard coordinate string mapping (from src/uci.cpp)
_SQUARE_TO_TOKEN = {
    # 8..15: inner ring
    8: "d5", 9: "e5", 10: "e4", 11: "e3", 12: "d3", 13: "c3", 14: "c4", 15: "c5",
    # 16..23: middle ring
    16: "d6", 17: "f6", 18: "f4", 19: "f2", 20: "d2", 21: "b2", 22: "b4", 23: "b6",
    # 24..31: outer ring
    24: "d7", 25: "g7", 26: "g4", 27: "g1", 28: "d1", 29: "a1", 30: "a4", 31: "a7",
}

# Reverse mapping: token -> Square(8..31)
_TOKEN_TO_SQUARE = {v: k for k, v in _SQUARE_TO_TOKEN.items()}

# Engine Square(0..39) -> Perfect index(0..23) mapping (from perfect_adaptor.cpp to_perfect_square)
_SQUARE_TO_PERFECT_INDEX = [
    -1, -1, -1, -1, -1, -1, -1, -1,
    18, 19, 20, 21, 22, 23, 16, 17,
    10, 11, 12, 13, 14, 15, 8, 9,
    2, 3, 4, 5, 6, 7, 0, 1,
    -1, -1, -1, -1, -1, -1, -1, -1,
]


def _board_to_tokens(board) -> Tuple[List[str], List[str]]:
    """Convert Board.pieces into white/black token lists (e.g., 'a1','d7')."""
    white: List[str] = []
    black: List[str] = []
    for (x, y), coord in xy_to_coord.items():
        piece = board.pieces[x][y]
        if piece == 1:
            white.append(coord)
        elif piece == -1:
            black.append(coord)
    return white, black


def _tokens_to_perfect_bitboards(white_tokens: List[str], black_tokens: List[str]) -> Tuple[int, int]:
    """Convert token lists into two 24-bit Perfect bitboards."""
    w_bits = 0
    b_bits = 0
    for tok in white_tokens:
        sq = _TOKEN_TO_SQUARE.get(tok)
        if sq is None:
            continue
        pidx = _SQUARE_TO_PERFECT_INDEX[sq]
        if pidx >= 0:
            w_bits |= (1 << pidx)
    for tok in black_tokens:
        sq = _TOKEN_TO_SQUARE.get(tok)
        if sq is None:
            continue
        pidx = _SQUARE_TO_PERFECT_INDEX[sq]
        if pidx >= 0:
            b_bits |= (1 << pidx)
    return w_bits, b_bits


class PerfectDB:
    """DLL wrapper: call Perfect DB directly (no sanmill.exe)."""

    def __init__(self, dll_path: str | None = None):
        dll_path = dll_path or os.environ.get(
            "SANMILL_PERFECT_DLL",
            os.path.join(
                os.path.dirname(os.path.dirname(__file__)),
                "..", "src", "perfect", "perfect_db.dll",
            ),
        )
        self._dll_path = os.path.abspath(dll_path)
        if not os.path.exists(self._dll_path):
            raise FileNotFoundError(f"Perfect DB DLL not found: {self._dll_path}")

        self._dll = ctypes.CDLL(self._dll_path)
        # Simple in-memory caches keyed by (wBits,bBits,wPlace,bPlace,stm,onlyTake)
        self._eval_cache: dict[tuple, tuple[int, int]] = {}
        self._best_cache: dict[tuple, str] = {}

        # int pd_init_std(const char* db_path)
        self._dll.pd_init_std.argtypes = [ctypes.c_char_p]
        self._dll.pd_init_std.restype = ctypes.c_int

        # void pd_deinit()
        self._dll.pd_deinit.argtypes = []
        self._dll.pd_deinit.restype = None

        # int pd_evaluate(int wBits,int bBits,int wPlace,int bPlace,int sideToMove,int onlyTake,int* outWdl,int* outSteps)
        self._dll.pd_evaluate.argtypes = [
            ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
            ctypes.c_int, ctypes.c_int,
            ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
        ]
        self._dll.pd_evaluate.restype = ctypes.c_int

        # Try optional export: pd_best_move (single best token). Can be extended later.
        try:
            self._dll.pd_best_move.argtypes = [
                ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                ctypes.c_int, ctypes.c_int,
                ctypes.c_char_p, ctypes.c_int,
            ]
            self._dll.pd_best_move.restype = ctypes.c_int
            self._has_best = True
        except Exception:
            self._has_best = False

    def init(self, db_path: str) -> None:
        ret = self._dll.pd_init_std(db_path.encode("utf-8"))
        assert ret == 1, f"pd_init_std failed for path: {db_path}"

    def deinit(self) -> None:
        self._dll.pd_deinit()

    def evaluate(self, board, side_to_move: int, only_take: bool) -> Tuple[int, int]:
        """返回 (wdl, steps)。wdl: 1=win, 0=draw, -1=loss。steps 无法计算时为 -1。"""
        white_tok, black_tok = _board_to_tokens(board)
        w_bits, b_bits = _tokens_to_perfect_bitboards(white_tok, black_tok)
        # pieces in hand from Board helpers
        from game.GameLogic import Board as _B
        w_place = board.pieces_in_hand_count(1) if hasattr(board, "pieces_in_hand_count") else max(0, 9 - ((board.put_pieces + 1) // 2))
        b_place = board.pieces_in_hand_count(-1) if hasattr(board, "pieces_in_hand_count") else max(0, 9 - (board.put_pieces // 2))
        
        # Debug output for troubleshooting
        import logging
        log = logging.getLogger(__name__)
        # Temporarily enable debug logging for diagnosis
        log.setLevel(logging.DEBUG)
        handler = logging.StreamHandler()
        handler.setLevel(logging.DEBUG)
        if not log.handlers:
            log.addHandler(handler)
        log.debug(f"PerfectDB.evaluate: period={board.period}, put_pieces={board.put_pieces}, "
                 f"w_count={board.count(1)}, b_count={board.count(-1)}, "
                 f"w_place={w_place}, b_place={b_place}, side_to_move={side_to_move}, only_take={only_take}")
        
        # Calculate expected sector ID for debugging
        w_on_board = board.count(1)
        b_on_board = board.count(-1)
        log.debug(f"Expected sector ID: W={w_on_board}, B={b_on_board}, WF={w_place}, BF={b_place}")
        log.debug(f"Bitboards: w_bits={w_bits:024b}, b_bits={b_bits:024b}")
        
        out_wdl = ctypes.c_int(0)
        out_steps = ctypes.c_int(-1)
        key = (int(w_bits), int(b_bits), int(w_place), int(b_place), int(0 if side_to_move == 1 else 1), int(1 if only_take else 0))
        if key in self._eval_cache:
            return self._eval_cache[key]
        ok = self._dll.pd_evaluate(
            int(w_bits), int(b_bits), int(w_place), int(b_place),
            int(0 if side_to_move == 1 else 1), int(1 if only_take else 0),
            ctypes.byref(out_wdl), ctypes.byref(out_steps),
        )
        if ok != 1:
            log.error(f"pd_evaluate failed with return code {ok}. Parameters: "
                     f"w_bits={w_bits}, b_bits={b_bits}, w_place={w_place}, b_place={b_place}, "
                     f"stm={0 if side_to_move == 1 else 1}, only_take={1 if only_take else 0}")
            log.error(f"Expected sector: std_{w_on_board}_{b_on_board}_{w_place}_{b_place}.sec2")
        assert ok == 1, f"pd_evaluate failed with return code {ok}"
        res = (int(out_wdl.value), int(out_steps.value))
        self._eval_cache[key] = res
        return res

    def good_moves_tokens(self, board, side_to_move: int, only_take: bool, buf_len: int = 4096) -> List[str]:
        white_tok, black_tok = _board_to_tokens(board)
        w_bits, b_bits = _tokens_to_perfect_bitboards(white_tok, black_tok)
        w_place = board.pieces_in_hand_count(1) if hasattr(board, "pieces_in_hand_count") else max(0, 9 - ((board.put_pieces + 1) // 2))
        b_place = board.pieces_in_hand_count(-1) if hasattr(board, "pieces_in_hand_count") else max(0, 9 - (board.put_pieces // 2))
        
        # Debug output for troubleshooting
        import logging
        log = logging.getLogger(__name__)
        log.debug(f"PerfectDB.good_moves_tokens: period={board.period}, put_pieces={board.put_pieces}, "
                 f"w_count={board.count(1)}, b_count={board.count(-1)}, "
                 f"w_place={w_place}, b_place={b_place}, side_to_move={side_to_move}, only_take={only_take}")
        
        # 先用单着接口，后续如需多着可在 DLL 侧补充
        if not self._has_best:
            raise RuntimeError("pd_best_move not available in DLL")
        buf = ctypes.create_string_buffer(buf_len)
        key = (int(w_bits), int(b_bits), int(w_place), int(b_place), int(0 if side_to_move == 1 else 1), int(1 if only_take else 0))
        if key in self._best_cache:
            tok = self._best_cache[key]
            return [tok] if tok else []
        ok = self._dll.pd_best_move(
            int(w_bits), int(b_bits), int(w_place), int(b_place),
            int(0 if side_to_move == 1 else 1), int(1 if only_take else 0),
            buf, int(buf_len),
        )
        if ok != 1:
            log.error(f"pd_best_move failed with return code {ok}. Parameters: "
                     f"w_bits={w_bits}, b_bits={b_bits}, w_place={w_place}, b_place={b_place}, "
                     f"stm={0 if side_to_move == 1 else 1}, only_take={1 if only_take else 0}")
        assert ok == 1, f"pd_best_move failed with return code {ok}"
        tok = buf.value.decode("utf-8", errors="ignore").strip()
        self._best_cache[key] = tok
        return [tok] if tok else []


