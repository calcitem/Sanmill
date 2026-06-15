#!/usr/bin/env python3
"""Drive ONE UCI engine to self-play `plies` moves and print each bestmove.

A small interactive UCI helper used to verify that a Sanmill-compatible engine
(the Rust `tgf` CLI or the legacy C++ `master_engine`) plays through a game and
to inspect its move notation (place `d6`, move `a1-a4`, remove `xa1`).

Usage:
    python uci_probe.py "<engine-cmd>" <plies> "<setopts>" "<go-cmd>"

    <engine-cmd>  full path to the engine, optionally followed by args
                  (e.g. "D:/Repo/Sanmill/target/release/tgf.exe uci").
    <plies>       number of half-moves to play (default 20).
    <setopts>     ';'-separated UCI option bodies, e.g.
                  "name SkillLevel value 14;name DeveloperMode value false".
    <go-cmd>      the go command (default "go"; tgf uses "go depth 0").
"""
import shlex
import subprocess
import sys
import time


def main() -> None:
    cmd = sys.argv[1]
    plies = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    setopts = sys.argv[3] if len(sys.argv) > 3 else ""
    go_cmd = sys.argv[4] if len(sys.argv) > 4 else "go"

    args = shlex.split(cmd, posix=False)
    p = subprocess.Popen(
        args,
        shell=False,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    def send(s: str) -> None:
        assert p.stdin is not None
        p.stdin.write(s + "\n")
        p.stdin.flush()

    def read_until(token: str, timeout: float = 120.0):
        end = time.time() + timeout
        while time.time() < end:
            assert p.stdout is not None
            line = p.stdout.readline()
            if not line:
                return None
            line = line.strip()
            if token in line:
                return line
        return None

    send("uci")
    if read_until("uciok") is None:
        print("NO uciok")
        return
    for opt in setopts.split(";"):
        opt = opt.strip()
        if opt:
            send("setoption " + opt)
    send("isready")
    if read_until("readyok") is None:
        print("NO readyok")
        return
    send("ucinewgame")

    moves = []
    for i in range(plies):
        pos = "position startpos"
        if moves:
            pos += " moves " + " ".join(moves)
        send(pos)
        send(go_cmd)
        bm = read_until("bestmove", timeout=600)
        if bm is None:
            print(f"TIMEOUT/no bestmove at ply {i}")
            break
        toks = bm.split()
        mv = toks[toks.index("bestmove") + 1] if "bestmove" in toks else ""
        if mv in ("(none)", "none", "0000", ""):
            print(f"game over / none at ply {i} (raw={bm!r})")
            break
        moves.append(mv)
        print(f"ply {i}: {mv}   raw={bm!r}")
    send("quit")
    time.sleep(0.2)
    print("MOVES:", " ".join(moves))


if __name__ == "__main__":
    main()
