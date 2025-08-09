import os
import re
import sys
import time
import queue
import threading
import subprocess
from typing import List, Optional


class MillEngine:
    """
    Thin UCI-like bridge to the Sanmill engine.

    Responsibilities:
    - start/stop the engine process
    - handshake (uci/uciok, isready/readyok)
    - set standard Nine Men's Morris rule options
    - query legal moves via the custom "analyze startpos moves ..." command
    - get bestmove via "go" on a given move list
    """

    def __init__(self, executable: Optional[str] = None, init_timeout_s: float = 5.0):
        self.executable = executable or os.environ.get("SANMILL_ENGINE", "sanmill")
        self.proc: Optional[subprocess.Popen] = None
        self._reader_thread: Optional[threading.Thread] = None
        self._lines: "queue.Queue[str]" = queue.Queue()
        self._stop_reader = threading.Event()
        self.init_timeout_s = init_timeout_s

    # ------------------------- Process Management -------------------------

    def start(self) -> None:
        if self.proc and self.proc.poll() is None:
            return
        self.proc = subprocess.Popen(
            [self.executable],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1,
        )
        self._stop_reader.clear()
        self._reader_thread = threading.Thread(target=self._read_loop, daemon=True)
        self._reader_thread.start()
        self._send("uci")
        self._wait_for(lambda s: "uciok" in s, timeout_s=self.init_timeout_s)
        self._send("isready")
        self._wait_for(lambda s: "readyok" in s, timeout_s=self.init_timeout_s)

    def stop(self) -> None:
        try:
            if self.proc and self.proc.poll() is None:
                self._send("quit")
        except Exception:
            pass
        self._stop_reader.set()
        try:
            if self._reader_thread:
                self._reader_thread.join(timeout=1.0)
        except Exception:
            pass
        try:
            if self.proc and self.proc.poll() is None:
                self.proc.terminate()
        except Exception:
            pass
        self.proc = None
        self._reader_thread = None

    # ----------------------------- Utilities ------------------------------

    def _read_loop(self) -> None:
        assert self.proc is not None and self.proc.stdout is not None
        while not self._stop_reader.is_set():
            line = self.proc.stdout.readline()
            if not line:
                break
            self._lines.put(line.strip())

    def _send(self, cmd: str) -> None:
        assert self.proc is not None and self.proc.stdin is not None
        self.proc.stdin.write(cmd + "\n")
        self.proc.stdin.flush()

    def _wait_for(self, pred, timeout_s: float) -> List[str]:
        deadline = time.time() + timeout_s
        matched: List[str] = []
        while time.time() < deadline:
            try:
                line = self._lines.get(timeout=0.05)
            except queue.Empty:
                continue
            matched.append(line)
            if pred(line):
                return matched
        raise TimeoutError("Engine did not respond in time")

    # ------------------------------- API ----------------------------------

    def set_standard_rules(self) -> None:
        """Set engine rule options to standard Nine Men's Morris.

        These match the engine's option names used by the Flutter UI layer.
        """
        # Pieces and board topology
        self._send("setoption name PiecesCount value 9")
        self._send("setoption name HasDiagonalLines value false")
        # Movement rules
        self._send("setoption name MayMoveInPlacingPhase value false")
        self._send("setoption name MayFly value true")
        self._send("setoption name FlyPieceCount value 3")
        # Removal constraint (default: cannot remove from mills if others exist)
        self._send("setoption name MayRemoveFromMillsAlways value false")
        # Draw rules
        # Keep training rules consistent with Python Game logic (default: 100)
        self._send("setoption name NMoveRule value 100")
        self._send("setoption name EndgameNMoveRule value 100")
        # Apply
        self._send("isready")
        self._wait_for(lambda s: "readyok" in s, timeout_s=2.0)

    def set_threads(self, n: int) -> None:
        """Set engine Threads option and wait for readiness."""
        assert self.proc is not None and self.proc.stdin is not None
        self._send(f"setoption name Threads value {int(n)}")
        self._send("isready")
        self._wait_for(lambda s: "readyok" in s, timeout_s=5.0)

    # ------------------- Perfect database utilities -------------------

    @staticmethod
    def _to_wsl_path(path: str) -> str:
        """Convert a Windows path like 'E:\\dir\\sub' to WSL '/mnt/e/dir/sub'.

        If the input already looks like a POSIX path, return it unchanged.
        """
        import re
        if not path:
            return path
        if path.startswith("/"):
            return path
        m = re.match(r"^([A-Za-z]):\\\\(.*)$", path.replace("/", "\\"))
        if m:
            drive = m.group(1).lower()
            rest = m.group(2).replace("\\", "/")
            return f"/mnt/{drive}/{rest}"
        # Fallback: replace backslashes
        return path.replace("\\", "/")

    def enable_perfect_database(self, path: str) -> None:
        """Enable Perfect Database and set its path.

        - Accepts either Windows or POSIX path. Converts Windows path to WSL.
        - Sends UsePerfectDatabase=true and PerfectDatabasePath.
        - Performs a quick readiness check.
        """
        assert self.proc is not None, "Engine process is not started. Call start() first."
        wsl_path = self._to_wsl_path(path)
        self._send("setoption name UsePerfectDatabase value true")
        self._send(f"setoption name PerfectDatabasePath value {wsl_path}")
        self._send("isready")
        self._wait_for(lambda s: "readyok" in s, timeout_s=3.0)
        # Optional: probe one analysis line to verify labels are present
        try:
            result = self.analyze([], timeout_s=30.0)
            # Print a short confirmation if we detect any labeled outcomes
            if any(v.get('wdl') in ('win', 'draw', 'loss') for v in result.values()):
                print(f"[MillEngine] Perfect DB labeling detected at '{wsl_path}'.")
            else:
                print("[MillEngine] Perfect DB labeling not detected (engine may fallback to traditional search).")
        except Exception as e:
            print(f"[MillEngine] Perfect DB quick check failed: {e}")

    def analyze(self, move_list: List[str], timeout_s: float = None):
        """Run 'analyze startpos moves ...' and parse labeled outcomes.

        Returns a dict mapping engine tokens to a dict payload:
          {
            'a1-a4': {'wdl': 'win'|'draw'|'loss'|'advantage'|'disadvantage'|'unknown',
                      'value': int or None,
                      'steps': int or None}
            ...
          }

        If the engine outputs only plain tokens (no labels), returns empty dict.
        """
        assert self.proc is not None, "Engine process is not started. Call start() first."
        # Allow configurable timeout via environment variable
        if timeout_s is None:
            try:
                timeout_s = float(os.environ.get("SANMILL_ANALYZE_TIMEOUT", "60"))
            except Exception:
                timeout_s = 60.0
        cmd = "analyze startpos"
        if move_list:
            cmd += " moves " + " ".join(move_list)
        self._send(cmd)

        def match(line: str) -> bool:
            return line.startswith("info analysis")

        lines = self._wait_for(match, timeout_s=timeout_s)
        if not lines:
            return {}
        last = lines[-1]

        # Example fragments:
        #   info analysis a1-a4=win(228 in 75 steps) a1=draw(0) xg7=loss(-228 in 75 steps)
        #   info analysis a1-a4=advantage(32) a1=disadvantage(-15)
        import re
        out = {}
        token = r"(?:[a-g][1-7](?:-[a-g][1-7])?|x[a-g][1-7])"
        # Capture: token=label(value [in steps steps])
        pattern = re.compile(
            rf"\b({token})=([A-Za-z]+)\(([-\d]+)(?: in (\d+) steps)?\)")
        for m in pattern.finditer(last):
            mv = m.group(1)
            label = m.group(2).lower()
            val = int(m.group(3)) if m.group(3) is not None else None
            steps = int(m.group(4)) if m.group(4) is not None else None
            out[mv] = {"wdl": label, "value": val, "steps": steps}
        return out

    def choose_with_perfect(self, move_list: List[str]):
        """Pick a move using Perfect DB labels with win/draw/slow-loss priority.

        Returns the engine-token move string.
        Raises ValueError if no labeled legal moves available.
        """
        labels = self.analyze(move_list)
        if not labels:
            raise ValueError("No labels returned by analyze; Perfect DB may be unavailable.")
        win_moves = [m for m, d in labels.items() if d.get('wdl') == 'win']
        if win_moves:
            return win_moves[0]
        draw_moves = [m for m, d in labels.items() if d.get('wdl') == 'draw']
        if draw_moves:
            return draw_moves[0]
        # For losses, prefer the one with maximum steps (slowest loss)
        loss_moves = sorted([(m, d.get('steps') or 0) for m, d in labels.items()], key=lambda x: -x[1])
        if loss_moves:
            return loss_moves[0][0]
        # Fallback: any legal move token
        tokens = list(labels.keys())
        if not tokens:
            raise ValueError("No legal moves found in analysis.")
        return tokens[0]

    def get_legal_moves(self, move_list: List[str], timeout_s: float = 5.0) -> List[str]:
        """Return legal moves in engine notation for the given move sequence.

        Uses the custom 'analyze startpos moves ...' which enumerates all legal
        moves in one line starting with 'info analysis'.
        """
        cmd = "analyze startpos"
        if move_list:
            cmd += " moves " + " ".join(move_list)
        self._send(cmd)
        # Expect a single line beginning with 'info analysis'
        def match(line: str) -> bool:
            return line.startswith("info analysis")
        lines = self._wait_for(match, timeout_s=timeout_s)
        last = lines[-1]
        # Extract move tokens: a1, a1-a4, xg7, etc.
        tokens = re.findall(r"\b(?:[a-g][1-7](?:-[a-g][1-7])?|x[a-g][1-7])\b", last)
        return tokens

    def get_bestmove(self, move_list: List[str], timeout_s: float = 10.0) -> Optional[str]:
        """Return bestmove or None if no bestmove.

        Sends 'position startpos moves ...' then 'go' and waits for a line that
        contains either 'bestmove' or 'nobestmove'. The engine typically emits
        'info score <v> bestmove <move>'.
        """
        pos = "position startpos"
        if move_list:
            pos += " moves " + " ".join(move_list)
        self._send(pos)
        self._send("go")
        def match(line: str) -> bool:
            return ("bestmove" in line) or ("nobestmove" in line)
        try:
            lines = self._wait_for(match, timeout_s=timeout_s)
        except TimeoutError:
            return None
        last = lines[-1]
        if "nobestmove" in last:
            return None
        m = re.search(r"bestmove\s+([a-g][1-7](?:-[a-g][1-7])?|x[a-g][1-7])", last)
        return m.group(1) if m else None


