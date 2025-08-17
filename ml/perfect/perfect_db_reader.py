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
        # Error logging throttle
        self._error_count = 0
        self._last_error_log = 0

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
        
        # Optional debug output (only if debug logging is enabled)
        import logging
        log = logging.getLogger(__name__)
        if log.isEnabledFor(logging.DEBUG):
            log.debug(f"PerfectDB.evaluate: period={board.period}, put_pieces={board.put_pieces}, "
                     f"w_count={board.count(1)}, b_count={board.count(-1)}, "
                     f"w_place={w_place}, b_place={b_place}, side_to_move={side_to_move}, only_take={only_take}")
            log.debug(f"Expected sector ID: W={board.count(1)}, B={board.count(-1)}, WF={w_place}, BF={b_place}")
            log.debug(f"Bitboards: w_bits={w_bits:024b}, b_bits={b_bits:024b}")
        
        out_wdl = ctypes.c_int(0)
        out_steps = ctypes.c_int(-1)
        key = (int(w_bits), int(b_bits), int(w_place), int(b_place), int(0 if side_to_move == 1 else 1), int(1 if only_take else 0))
        if key in self._eval_cache:
            return self._eval_cache[key]
        
        # Input validation to avoid C++ assertion failures
        try:
            # Basic sanity checks before calling DLL
            w_count = board.count(1)
            b_count = board.count(-1)
            
            # Check for invalid states that might cause C++ assertions
            if w_count < 0 or b_count < 0 or w_count > 9 or b_count > 9:
                raise ValueError(f"Invalid piece counts: W={w_count}, B={b_count}")
            
            if w_place < 0 or b_place < 0 or w_place > 9 or b_place > 9:
                raise ValueError(f"Invalid pieces in hand: WF={w_place}, BF={b_place}")
            
            # Check total pieces consistency
            total_on_board = w_count + b_count
            total_in_hand = w_place + b_place
            if total_on_board + total_in_hand > 18:  # 9 pieces per player max
                raise ValueError(f"Too many total pieces: on_board={total_on_board}, in_hand={total_in_hand}")
            
            # Note: Removed specific configuration filtering - let DLL handle validation
            
            # Prepare parameters for DLL call
            stm_value = int(0 if side_to_move == 1 else 1)
            only_take_value = int(1 if only_take else 0)
            
            # Check for problematic sector and skip it
            sector_name = f"std_{w_count}_{b_count}_{w_place}_{b_place}.sec2"
            
            # Skip the problematic sector std_3_9_0_0.sec2
            if w_count == 3 and b_count == 9 and w_place == 0 and b_place == 0:
                if not hasattr(self, '_skip_sector_warned'):
                    print(f"⚠️  Skipping problematic sector {sector_name} (will skip silently from now on)")
                    self._skip_sector_warned = True
                # Return default values: draw with unknown steps
                res = (0, -1)  # draw, steps unknown
                self._eval_cache[key] = res
                return res
            
            if log.isEnabledFor(logging.DEBUG):
                log.debug(f"DLL Call: w_bits={w_bits:06x}, b_bits={b_bits:06x}, "
                         f"w_place={w_place}, b_place={b_place}, stm={stm_value}, only_take={only_take_value}, "
                         f"sector={sector_name}")
            
            try:
                ok = self._dll.pd_evaluate(
                    int(w_bits), int(b_bits), int(w_place), int(b_place),
                    stm_value, only_take_value,
                    ctypes.byref(out_wdl), ctypes.byref(out_steps),
                )
            except Exception as e:
                # This won't catch C++ assertions, but might catch other errors
                raise RuntimeError(f"DLL call failed for sector {sector_name}: {e}")
            
            if ok != 1:
                raise RuntimeError(f"pd_evaluate failed with return code {ok}")
            
            res = (int(out_wdl.value), int(out_steps.value))
            self._eval_cache[key] = res
            return res
            
        except Exception as e:
            # Count errors but don't log at this level - let the caller handle logging
            # This avoids duplicate error messages
            self._error_count += 1
            # Only log the first few errors for debugging, then suppress
            if self._error_count <= 3:
                log.debug(f"PerfectDB.evaluate failed for position: period={board.period}, "
                         f"W={board.count(1)}, B={board.count(-1)}, WF={w_place}, BF={b_place}, "
                         f"side_to_move={side_to_move}, only_take={only_take}, error: {e}")
            raise

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
        
        try:
            # Same input validation as in evaluate()
            w_count = board.count(1)
            b_count = board.count(-1)
            
            if w_count < 0 or b_count < 0 or w_count > 9 or b_count > 9:
                raise ValueError(f"Invalid piece counts: W={w_count}, B={b_count}")
            
            if w_place < 0 or b_place < 0 or w_place > 9 or b_place > 9:
                raise ValueError(f"Invalid pieces in hand: WF={w_place}, BF={b_place}")
            
            total_on_board = w_count + b_count
            total_in_hand = w_place + b_place
            if total_on_board + total_in_hand > 18:
                raise ValueError(f"Too many total pieces: on_board={total_on_board}, in_hand={total_in_hand}")
            
            # Check for problematic sector and skip it
            stm_value = int(0 if side_to_move == 1 else 1)
            only_take_value = int(1 if only_take else 0)
            key = (int(w_bits), int(b_bits), int(w_place), int(b_place), stm_value, only_take_value)
            
            # Skip the problematic sector std_3_9_0_0.sec2
            if w_count == 3 and b_count == 9 and w_place == 0 and b_place == 0:
                if not hasattr(self, '_skip_sector_warned'):
                    print(f"⚠️  Skipping problematic sector std_{w_count}_{b_count}_{w_place}_{b_place}.sec2 (will skip silently from now on)")
                    self._skip_sector_warned = True
                # Return empty moves list for this problematic sector
                self._best_cache[key] = ""
                return []
            
            if key in self._best_cache:
                tok = self._best_cache[key]
                return [tok] if tok else []
            
            buf = ctypes.create_string_buffer(buf_len)
            
            # Optional detailed debug output for best_move calls
            if log.isEnabledFor(logging.DEBUG):
                log.debug(f"DLL best_move Call: w_bits={w_bits:06x}, b_bits={b_bits:06x}, "
                         f"w_place={w_place}, b_place={b_place}, stm={stm_value}, only_take={only_take_value}, "
                         f"sector=std_{w_count}_{b_count}_{w_place}_{b_place}.sec2")
            
            ok = self._dll.pd_best_move(
                int(w_bits), int(b_bits), int(w_place), int(b_place),
                stm_value, only_take_value,
                buf, int(buf_len),
            )
            
            if ok != 1:
                raise RuntimeError(f"pd_best_move failed with return code {ok}")
            
            tok = buf.value.decode("utf-8", errors="ignore").strip()
            self._best_cache[key] = tok
            return [tok] if tok else []
            
        except Exception as e:
            log.warning(f"PerfectDB.good_moves_tokens failed for position: period={board.period}, "
                       f"W={board.count(1)}, B={board.count(-1)}, WF={w_place}, BF={b_place}, "
                       f"side_to_move={side_to_move}, only_take={only_take}, error: {e}")
            raise


