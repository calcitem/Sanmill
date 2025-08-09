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
        self._send("setoption name NMoveRule value 50")
        self._send("setoption name EndgameNMoveRule value 10")
        # Apply
        self._send("isready")
        self._wait_for(lambda s: "readyok" in s, timeout_s=2.0)

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


