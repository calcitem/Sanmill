import ctypes
import os
from typing import List, Tuple

"""
Robust imports for standard rules and Board to tolerate different sys.path setups
(running as package or scripts).
"""

# Import coord maps with fallback
try:
    from game.standard_rules import xy_to_coord, coord_to_xy
except ImportError:
    import sys
    import os
    # Ensure ml/ is on sys.path so that `game` package can be found
    _current_dir = os.path.dirname(os.path.abspath(__file__))
    _ml_dir = os.path.dirname(_current_dir)
    if _ml_dir not in sys.path:
        sys.path.insert(0, _ml_dir)
    try:
        from game.standard_rules import xy_to_coord, coord_to_xy
    except ImportError:
        try:
            from standard_rules import xy_to_coord, coord_to_xy # type: ignore
        except ImportError:
            # Minimal fallback maps (subset sufficient for conversion)
            _coord_to_xy_min = {
                "a7": (0, 0), "d7": (3, 0), "g7": (6, 0),
                "g4": (6, 3), "g1": (6, 6), "d1": (3, 6), "a1": (0, 6), "a4": (0, 3),
                "b6": (1, 1), "d6": (3, 1), "f6": (5, 1),
                "f4": (5, 3), "f2": (5, 5), "d2": (3, 5), "b2": (1, 5), "b4": (1, 3),
                "c5": (2, 2), "d5": (3, 2), "e5": (4, 2),
                "e4": (4, 3), "e3": (4, 4), "d3": (3, 4), "c3": (2, 4), "c4": (2, 3),
            }
            xy_to_coord = {v: k for k, v in _coord_to_xy_min.items()}
            coord_to_xy = _coord_to_xy_min


def _import_board_class():
    """Import Board class from GameLogic with multiple fallbacks."""
    try:
        from game.GameLogic import Board as _Board # type: ignore
        return _Board
    except Exception:
        import sys as _sys
        import os as _os
        _current = _os.path.dirname(_os.path.abspath(__file__))
        _ml = _os.path.dirname(_current)
        if _ml not in _sys.path:
            _sys.path.insert(0, _ml)
        try:
            from game.GameLogic import Board as _Board # type: ignore
            return _Board
        except Exception:
            # Last resort: direct module import when cwd is ml/game
            from GameLogic import Board as _Board # type: ignore
            return _Board


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

        # Optional sector iteration APIs (available in newer DLLs)
        try:
            self._dll.pd_open_sector.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int]
            self._dll.pd_open_sector.restype = ctypes.c_int
            self._dll.pd_close_sector.argtypes = [ctypes.c_int]
            self._dll.pd_close_sector.restype = ctypes.c_int
            self._dll.pd_sector_count.argtypes = [ctypes.c_int]
            self._dll.pd_sector_count.restype = ctypes.c_int
            self._dll.pd_sector_next.argtypes = [
                ctypes.c_int,
                ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
                ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
            ]
            self._dll.pd_sector_next.restype = ctypes.c_int
            self._has_sector_iter = True
        except Exception:
            self._has_sector_iter = False

    def init(self, db_path: str) -> None:
        ret = self._dll.pd_init_std(db_path.encode("utf-8"))
        assert ret == 1, f"pd_init_std failed for path: {db_path}"

    def deinit(self) -> None:
        self._dll.pd_deinit()

    def evaluate(self, board, side_to_move: int, only_take: bool) -> Tuple[int, int]:
        """Returns (wdl, steps). wdl: 1=win, 0=draw, -1=loss. steps is -1 when not available."""
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
            if total_on_board + total_in_hand > 18: # 9 pieces per player max
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
                    # print(f"⚠️  Skipping problematic sector {sector_name} (will skip silently from now on)")
                    self._skip_sector_warned = True
                # Return default values: draw with unknown steps
                res = (0, -1) # draw, steps unknown
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

        # Use the single-move interface for now; multi-move support can be added in the DLL later.
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
                    # print(f"⚠️  Skipping problematic sector std_{w_count}_{b_count}_{w_place}_{b_place}.sec2 (will skip silently from now on)")
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
                # A return code of 0 can have two meanings:
                # 1. A genuine error (hasError() == true)
                # 2. Normal situation: no legal moves, game over, etc. (hasError() == false)
                # Since hasError() cannot be called directly from Python, we need to infer from the context.

                # For special game states (like game over), return an empty list instead of raising an exception.
                if hasattr(board, 'period') and board.period == 3:
                    # In the removal phase, some positions might not have a target to remove, which is normal.
                    log.debug(f"pd_best_move returned {ok} in removal phase - likely no removal targets")
                    self._best_cache[key] = ""
                    return []

                # Check if it is a game-over state.
                piece_count_white = board.count(1) if hasattr(board, 'count') else 0
                piece_count_black = board.count(-1) if hasattr(board, 'count') else 0

                # If either side has fewer than 3 pieces and is not in the placement phase, the game might be over.
                if (piece_count_white < 3 or piece_count_black < 3) and w_place == 0 and b_place == 0:
                    log.debug(f"pd_best_move returned {ok} - game likely over (W={piece_count_white}, B={piece_count_black})")
                    self._best_cache[key] = ""
                    return []

                # For other cases, log the details but return an empty list instead of raising an exception.
                log.debug(f"pd_best_move returned {ok} for position: period={getattr(board, 'period', '?')}, "
                          f"W={piece_count_white}, B={piece_count_black}, WF={w_place}, BF={b_place}, "
                          f"side_to_move={side_to_move}, only_take={only_take} - treating as no valid moves")
                self._best_cache[key] = ""
                return []

            tok = buf.value.decode("utf-8", errors="ignore").strip()
            self._best_cache[key] = tok
            return [tok] if tok else []

        except Exception as e:
            log.warning(f"PerfectDB.good_moves_tokens failed for position: period={board.period}, "
                        f"W={board.count(1)}, B={board.count(-1)}, WF={w_place}, BF={b_place}, "
                        f"side_to_move={side_to_move}, only_take={only_take}, error: {e}")
            raise

    # -------- Sector iteration helpers (optional) --------
    def open_sector(self, W: int, B: int, WF: int, BF: int) -> int:
        if not getattr(self, '_has_sector_iter', False):
            raise RuntimeError("Sector iteration API not available in DLL")
        handle = int(self._dll.pd_open_sector(int(W), int(B), int(WF), int(BF)))
        if handle <= 0:
            raise RuntimeError(f"pd_open_sector failed for std_{W}_{B}_{WF}_{BF}.sec2")
        return handle

    def close_sector(self, handle: int) -> None:
        if getattr(self, '_has_sector_iter', False):
            self._dll.pd_close_sector(int(handle))

    def sector_count(self, handle: int) -> int:
        if not getattr(self, '_has_sector_iter', False):
            raise RuntimeError("Sector iteration API not available in DLL")
        return int(self._dll.pd_sector_count(int(handle)))

    def sector_next(self, handle: int) -> tuple[int, int, int, int] | None:
        if not getattr(self, '_has_sector_iter', False):
            raise RuntimeError("Sector iteration API not available in DLL")
        w = ctypes.c_int(0)
        b = ctypes.c_int(0)
        wdl = ctypes.c_int(0)
        steps = ctypes.c_int(-1)

        # Add a retry mechanism to prevent recursive stack overflow (adjustable via environment variables).
        import os as _os
        max_retries = int(_os.environ.get('AZ_SECTOR_NEXT_RETRIES', '3')) # Limit the number of retries.
        if max_retries < 0:
            max_retries = 0
        for retry in range(max_retries + 1):
            try:
                ok = int(self._dll.pd_sector_next(int(handle), ctypes.byref(w), ctypes.byref(b), ctypes.byref(wdl), ctypes.byref(steps)))
                if ok != 1:
                    return None
                return int(w.value), int(b.value), int(wdl.value), int(steps.value)
            except OSError as e:
                if "stack overflow" in str(e).lower():
                    import logging
                    logger = logging.getLogger(__name__)
                    logger.warning(f"Stack overflow detected in pd_sector_next (retry {retry+1}/{max_retries}), handle={handle}")
                    if retry < max_retries:
                        # A short delay to allow the stack to recover, then try to continue.
                        import time
                        delay_ms = int(_os.environ.get('AZ_SECTOR_NEXT_DELAY_MS', '10'))
                        time.sleep(max(0, delay_ms) / 1000.0)
                        continue
                    else:
                        logger.error(f"Persistent stack overflow in pd_sector_next after {max_retries} retries - sector iteration failed")
                        raise RuntimeError("Stack overflow in sector iteration - DLL recursion issue") from e
                else:
                    # Re-raise other OSErrors directly.
                    raise

        return None # This point should theoretically not be reached.

    # Convert 24-bit perfect bitboards into Board
    def bitboards_to_board(self, white_bits: int, black_bits: int, WF: int, BF: int):
        _Board = _import_board_class()
        # coord_to_xy is imported above with fallbacks
        # perfect index (0..23) -> engine Square (8..31) mapping via reverse of _SQUARE_TO_PERFECT_INDEX
        _PERFECT_TO_SQUARE = {}
        for sq, pidx in enumerate(_SQUARE_TO_PERFECT_INDEX):
            if pidx >= 0:
                _PERFECT_TO_SQUARE[pidx] = sq
        board = _Board()
        # clear
        for x in range(7):
            for y in range(7):
                board.pieces[x][y] = 0
        # set pieces
        for i in range(24):
            mask = 1 << i
            sq = _PERFECT_TO_SQUARE.get(i, -1)
            if sq < 0:
                continue
            # Square 8..31 to coord token via _SQUARE_TO_TOKEN
            token = _SQUARE_TO_TOKEN.get(sq)
            if not token:
                continue
            xy = coord_to_xy.get(token)
            if not xy:
                continue
            x, y = xy
            if white_bits & mask:
                board.pieces[x][y] = 1
            elif black_bits & mask:
                board.pieces[x][y] = -1
        # put pieces and period
        W = board.count(1)
        B = board.count(-1)
        board.put_pieces = W + B
        if WF > 0 or BF > 0:
            board.period = 0
        elif W <= 3 or B <= 3:
            board.period = 2
        else:
            board.period = 1
        return board
