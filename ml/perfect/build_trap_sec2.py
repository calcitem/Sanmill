"""
Build a compact trap sec2 file (std_traps.sec2) from a full Perfect DB.

This script loads the DLL's exported builder to iterate sectors and extract
positions matching:
 - Forming a mill loses, but other moves draw/win
 - Blocking opponent's mill loses, but other moves draw/win

Usage:
  python -m ml.perfect.build_trap_sec2 --db E:\\Malom\\Malom_Standard_Ultra-strong_1.1.0\\Std_DD_89adjusted --out std_traps.sec2

Notes:
 - The DLL must be built and available as ml/../src/perfect/perfect_db.dll
 - The output file can be placed alongside the DB folder; the engine will load
   it automatically if present.
"""

from __future__ import annotations

import argparse
import ctypes
import os
import sys


def _find_dll() -> str:
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src", "perfect"))
    cand = os.path.join(root, "perfect_db.dll")
    if os.path.exists(cand):
        return cand
    env = os.environ.get("SANMILL_PERFECT_DLL")
    if env and os.path.exists(env):
        return env
    raise FileNotFoundError("perfect_db.dll not found; build via src/perfect/build_dll.bat")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build std_traps.sec2 from full Perfect DB")
    parser.add_argument("--db", required=True, help="Path to directory with std_*.sec2 and std.secval")
    parser.add_argument("--out", default="std_traps.sec2", help="Output file path")
    args = parser.parse_args(argv)

    dll_path = _find_dll()
    dll = ctypes.CDLL(dll_path)

    # int pd_build_trap_sec2(const char* db_path, const char* out_file);
    try:
        dll.pd_build_trap_sec2.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
        dll.pd_build_trap_sec2.restype = ctypes.c_int
    except Exception as e:
        raise RuntimeError("DLL is missing pd_build_trap_sec2 export") from e

    db_path = os.path.abspath(args.db)
    out_file = os.path.abspath(args.out)

    os.makedirs(os.path.dirname(out_file) or ".", exist_ok=True)

    ret = dll.pd_build_trap_sec2(db_path.encode("utf-8"), out_file.encode("utf-8"))
    assert ret == 1, f"DLL builder failed for db={db_path} out={out_file}"
    print(f"OK: wrote {out_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


