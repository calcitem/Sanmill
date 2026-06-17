#!/usr/bin/env python3
"""Compare Rust and legacy Mill engine search latency on fixed UCI cases.

This script is intentionally a diagnostic harness, not a default CI test.  It
drives both engines through UCI with the same position, options, and go command,
then reports wall time, best move, score, and nodes when the engine exposes
them.  The case set is chosen to split performance issues by phase:

* placing phase
* moving phase
* pending capture/removal
* reduced-material positions
* the NMoveRule=30/EndgameNMoveRule=20 Flutter parity position

Example:
  cargo build --release -p tgf-cli
  python3 scripts/compare_engine_perf.py --skills 5,10,15 --repeat 3
"""

from __future__ import annotations

import argparse
import csv
import dataclasses
import queue
import re
import shlex
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CURRENT = "target/release/tgf uci"
DEFAULT_MASTER = str(Path.home() / "Sanmill-master" / "master_engine")

BASE_OPTIONS = {
    "DeveloperMode": "false",
    "DrawOnHumanExperience": "true",
    "Shuffling": "false",
    "MoveTime": "0",
    "Algorithm": "2",
    "UsePerfectDatabase": "false",
    # Keep moving/flying phase diagnostics bounded; callers can override.
    "NMoveRule": "20",
    "EndgameNMoveRule": "20",
    "ThreefoldRepetitionRule": "true",
}

SKILL1_BLACK_MOVE13 = (
    "d6",
    "f4",
    "d2",
    "b4",
    "e4",
    "d5",
    "c4",
    "d3",
    "g4",
    "d7",
    "a4",
    "d1",
    "e5",
    "e3",
    "c3",
    "c5",
    "f6",
    "b6",
    "a4-a7",
    "b4-a4",
    "c4-b4",
    "c5-c4",
    "g4-g1",
    "d7-g7",
    "g1-g4",
)

SKILL15_PLACING8 = (
    "d6",
    "f4",
    "d2",
    "b4",
    "g4",
    "d7",
    "a4",
    "d1",
)

SKILL15_PLACING14 = (
    *SKILL15_PLACING8,
    "d5",
    "d3",
    "f6",
    "b6",
    "b2",
    "f2",
)

SKILL2_MOVING_ENTRY = (
    "d6",
    "f4",
    "d2",
    "b4",
    "g4",
    "d7",
    "a4",
    "d1",
    "e4",
    "d5",
    "c4",
    "d3",
    "f6",
    "b6",
    "b2",
    "f2",
    "g7",
    "g1",
)

SKILL5_CAPTURE_PENDING = (
    "d6",
    "f4",
    "d2",
    "b4",
    "g4",
    "d7",
    "a4",
    "d1",
    "d5",
    "d3",
    "e4",
    "f6",
    "f2",
    "b2",
    "b6",
    "g7",
    "a7",
    "c3",
    "d5-c5",
    "c3-c4",
    "e4-e5",
    "c4-c3",
    "d6-d5",
)

SKILL5_REDUCED_MATERIAL = (
    *SKILL5_CAPTURE_PENDING,
    "xd3",
    "c3-d3",
    "c5-c4",
    "f6-d6",
    "c4-c5",
    "xf4",
    "b4-c4",
    "e5-e4",
    "d6-f6",
    "f2-f4",
    "xd3",
    "b2-b4",
    "e4-e5",
    "xd1",
    "f6-d6",
    "e5-e4",
    "xc4",
    "b4-c4",
    "f4-f6",
)

SKILL15_N30_E20_BLACK20 = (
    "d6",
    "f4",
    "d2",
    "b4",
    "g4",
    "d7",
    "a4",
    "d1",
    "d5",
    "d3",
    "f6",
    "b6",
    "b2",
    "f2",
    "e5",
    "c5",
    "c3",
    "e4",
    "c3-c4",
    "d3-c3",
    "a4-a1",
    "d1-g1",
    "a1-a4",
    "c3-d3",
    "c4-c3",
    "d7-a7",
    "c3-c4",
    "d3-c3",
    "a4-a1",
    "a7-a4",
    "a1-d1",
    "a4-a1",
    "d2-d3",
    "f2-d2",
    "d6-d7",
    "b6-d6",
    "d7-a7",
    "a1-a4",
    "a7-d7",
)


@dataclasses.dataclass(frozen=True)
class Case:
    name: str
    moves: tuple[str, ...]
    note: str
    options: dict[str, str] = dataclasses.field(default_factory=dict)


@dataclasses.dataclass(frozen=True)
class ProbeResult:
    engine: str
    case: str
    skill: int
    requested_depth: str
    run: int
    elapsed_ms: float
    bestmove: str
    score: str
    depth: str
    nodes: str
    nps: str
    raw_bestmove_line: str


CASES = {
    case.name: case
    for case in (
        Case("start", (), "empty board placing phase"),
        Case("placing4", ("d6", "f4", "d2", "b4"), "early placing phase"),
        Case("placing8", SKILL15_PLACING8, "skill15 parity prefix before white move 5"),
        Case("placing14", SKILL15_PLACING14, "skill15 parity prefix before white move 8"),
        Case("moving_entry", SKILL2_MOVING_ENTRY, "first moving-phase root"),
        Case("moving_loop", SKILL1_BLACK_MOVE13, "stable moving loop root"),
        Case("capture_pending", SKILL5_CAPTURE_PENDING, "root is a remove action"),
        Case("reduced_material", SKILL5_REDUCED_MATERIAL, "post-capture reduced material"),
        Case(
            "flutter_n30_e20_black20",
            SKILL15_N30_E20_BLACK20,
            "Flutter NMoveRule=30/EndgameNMoveRule=20 parity root",
            {"NMoveRule": "30", "EndgameNMoveRule": "20"},
        ),
    )
}


class UciProcess:
    def __init__(self, command: str) -> None:
        self.command = command
        self.args = shlex.split(command)
        assert self.args, "empty engine command"
        self.process = subprocess.Popen(
            self.args,
            cwd=REPO_ROOT,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        self.lines: queue.Queue[str] = queue.Queue()
        self.reader = threading.Thread(target=self._read_stdout, daemon=True)
        self.reader.start()

    def _read_stdout(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.lines.put(line.rstrip("\n"))

    def send(self, command: str) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write(command + "\n")
        self.process.stdin.flush()

    def read_until(self, pattern: re.Pattern[str], timeout: float) -> tuple[str, list[str]]:
        deadline = time.monotonic() + timeout
        seen: list[str] = []
        while time.monotonic() < deadline:
            if self.process.poll() is not None and self.lines.empty():
                raise RuntimeError(
                    f"engine exited before {pattern.pattern!r}: {self.command}"
                )
            remaining = max(0.01, deadline - time.monotonic())
            try:
                line = self.lines.get(timeout=remaining)
            except queue.Empty:
                break
            seen.append(line)
            if pattern.search(line):
                return line, seen
        tail = "\n".join(seen[-20:])
        raise TimeoutError(
            f"timeout waiting for {pattern.pattern!r} from {self.command}\n{tail}"
        )

    def drain_quiet(self, quiet_timeout: float = 0.2, max_timeout: float = 5.0) -> None:
        deadline = time.monotonic() + max_timeout
        while time.monotonic() < deadline:
            try:
                self.lines.get(timeout=quiet_timeout)
            except queue.Empty:
                return

    def close(self) -> None:
        if self.process.poll() is None:
            try:
                self.send("quit")
            except (BrokenPipeError, OSError):
                pass
        try:
            self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=2)


def parse_kv_options(raw_options: Iterable[str]) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for raw in raw_options:
        assert "=" in raw, f"option override must be NAME=VALUE: {raw}"
        name, value = raw.split("=", 1)
        name = name.strip()
        value = value.strip()
        assert name, f"empty option name in {raw}"
        parsed[name] = value
    return parsed


def parse_csv_ints(raw: str) -> list[int]:
    values = [part.strip() for part in raw.split(",") if part.strip()]
    assert values, "at least one skill level is required"
    return [int(value) for value in values]


def parse_csv_names(raw: str) -> list[str]:
    names = [part.strip() for part in raw.split(",") if part.strip()]
    assert names, "at least one case is required"
    unknown = sorted(set(names) - set(CASES))
    assert not unknown, f"unknown case(s): {', '.join(unknown)}"
    return names


def executable_from_command(command: str) -> Path:
    args = shlex.split(command)
    assert args, "empty engine command"
    path = Path(args[0])
    if not path.is_absolute():
        path = REPO_ROOT / path
    return path


def maybe_build_current(command: str, build_current: bool) -> None:
    executable = executable_from_command(command)
    if executable.exists():
        return
    assert build_current, (
        f"current engine not found: {executable}. "
        "Run cargo build --release -p tgf-cli or pass --build-current."
    )
    subprocess.run(
        ["cargo", "build", "--release", "-p", "tgf-cli"],
        cwd=REPO_ROOT,
        check=True,
    )
    assert executable.exists(), f"current engine still missing after build: {executable}"


def set_options(engine: UciProcess, options: dict[str, str]) -> None:
    for name, value in options.items():
        engine.send(f"setoption name {name} value {value}")


def parse_bestmove_line(
    engine: str,
    case: str,
    skill: int,
    requested_depth: str,
    run: int,
    elapsed_ms: float,
    line: str,
) -> ProbeResult:
    bestmove = find_token(line, "bestmove")
    nodes = find_token(line, "nodes", default="")
    nps = find_token(line, "nps", default="")
    depth = parse_depth(line)
    score = parse_score(line)
    return ProbeResult(
        engine=engine,
        case=case,
        skill=skill,
        requested_depth=requested_depth,
        run=run,
        elapsed_ms=elapsed_ms,
        bestmove=bestmove,
        score=score,
        depth=depth,
        nodes=nodes,
        nps=nps,
        raw_bestmove_line=line,
    )


def find_token(line: str, token: str, default: str | None = None) -> str:
    parts = line.split()
    if token in parts:
        idx = parts.index(token) + 1
        if idx < len(parts):
            return parts[idx]
    assert default is not None, f"missing {token!r} in line: {line}"
    return default


def parse_score(line: str) -> str:
    match = re.search(r"\bscore\s+(cp|mate)\s+(-?\d+)", line)
    if match:
        return f"{match.group(1)}:{match.group(2)}"
    match = re.search(r"\bscore\s+(-?\d+)", line)
    if match:
        return match.group(1)
    match = re.search(r"\bvalue=(-?\d+)", line)
    if match:
        return match.group(1)
    return ""


def parse_depth(line: str) -> str:
    depth = find_token(line, "depth", default="")
    if depth:
        return depth
    match = re.search(r"\bdepth=(\d+)", line)
    if match:
        return match.group(1)
    return ""


def probe_once(
    label: str,
    command: str,
    go_command: str,
    case: Case,
    skill: int,
    run: int,
    requested_depth: str,
    overrides: dict[str, str],
    timeout: float,
) -> ProbeResult:
    engine = UciProcess(command)
    try:
        engine.send("uci")
        engine.read_until(re.compile(r"\buciok\b"), timeout=10)
        options = dict(BASE_OPTIONS)
        options.update(case.options)
        options.update(overrides)
        options["SkillLevel"] = str(skill)
        set_options(engine, options)
        engine.send("isready")
        engine.read_until(re.compile(r"\breadyok\b"), timeout=10)
        engine.send("ucinewgame")
        position = "position startpos"
        if case.moves:
            position += " moves " + " ".join(case.moves)
        engine.send(position)

        start = time.perf_counter()
        engine.send(go_command)
        line, _ = engine.read_until(re.compile(r"\bbestmove\s+\S+"), timeout=timeout)
        elapsed_ms = (time.perf_counter() - start) * 1000.0
        engine.drain_quiet()
        return parse_bestmove_line(
            label,
            case.name,
            skill,
            requested_depth,
            run,
            elapsed_ms,
            line,
        )
    finally:
        engine.close()


def format_optional(value: str) -> str:
    return value if value else "-"


def print_rows(rows: list[ProbeResult]) -> None:
    print_header()
    for row in rows:
        print_row(row)


def print_header() -> None:
    print(
        f"{'case':<24} {'skill':>5} {'req':>5} {'engine':<7} {'run':>3} "
        f"{'ms':>10} {'depth':>5} {'score':>9} {'nodes':>12} "
        f"{'nps':>10} bestmove",
        flush=True,
    )


def print_row(row: ProbeResult) -> None:
    print(
        f"{row.case:<24} {row.skill:>5} {format_optional(row.requested_depth):>5} "
        f"{row.engine:<7} {row.run:>3} "
        f"{row.elapsed_ms:>10.2f} {format_optional(row.depth):>5} "
        f"{format_optional(row.score):>9} {format_optional(row.nodes):>12} "
        f"{format_optional(row.nps):>10} {row.bestmove}",
        flush=True,
    )


def median(values: list[float]) -> float:
    assert values, "cannot compute median of empty list"
    ordered = sorted(values)
    mid = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[mid]
    return (ordered[mid - 1] + ordered[mid]) / 2.0


def print_summary(rows: list[ProbeResult]) -> None:
    print("\nsummary")
    print(
        f"{'case':<24} {'skill':>5} {'req':>5} {'cur_ms':>10} {'mas_ms':>10} "
        f"{'ratio':>9} {'same':>5} {'cur_nodes':>12} {'mas_nodes':>12}"
    )
    cases = sorted({row.case for row in rows})
    skills = sorted({row.skill for row in rows})
    requested_depths = sorted({row.requested_depth for row in rows})
    for case in cases:
        for skill in skills:
            for requested_depth in requested_depths:
                current = [
                    row
                    for row in rows
                    if row.case == case
                    and row.skill == skill
                    and row.requested_depth == requested_depth
                    and row.engine == "current"
                ]
                master = [
                    row
                    for row in rows
                    if row.case == case
                    and row.skill == skill
                    and row.requested_depth == requested_depth
                    and row.engine == "master"
                ]
                if not current or not master:
                    continue
                cur_ms = median([row.elapsed_ms for row in current])
                mas_ms = median([row.elapsed_ms for row in master])
                ratio = cur_ms / mas_ms if mas_ms > 0 else float("inf")
                same = {row.bestmove for row in current} == {
                    row.bestmove for row in master
                }
                cur_nodes = (
                    ",".join(sorted({row.nodes for row in current if row.nodes})) or "-"
                )
                mas_nodes = (
                    ",".join(sorted({row.nodes for row in master if row.nodes})) or "-"
                )
                print(
                    f"{case:<24} {skill:>5} {format_optional(requested_depth):>5} "
                    f"{cur_ms:>10.2f} {mas_ms:>10.2f} "
                    f"{ratio:>9.3f} {str(same):>5} {cur_nodes:>12} {mas_nodes:>12}"
                )


def write_csv(path: Path, rows: list[ProbeResult]) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=[field.name for field in dataclasses.fields(ProbeResult)])
        writer.writeheader()
        for row in rows:
            writer.writerow(dataclasses.asdict(row))


def list_cases() -> None:
    for name, case in CASES.items():
        print(f"{name:<24} plies={len(case.moves):>3} {case.note}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--current", default=DEFAULT_CURRENT, help="current engine command")
    parser.add_argument("--master", default=DEFAULT_MASTER, help="master engine command")
    parser.add_argument("--current-go", default="go depth 0", help="current engine go command")
    parser.add_argument("--master-go", default="go", help="master engine go command")
    parser.add_argument(
        "--depths",
        help=(
            "comma-separated fixed depths; when set, current/master go commands "
            "come from --current-depth-go/--master-depth-go"
        ),
    )
    parser.add_argument(
        "--current-depth-go",
        default="go depth {depth}",
        help="current fixed-depth go command template used with --depths",
    )
    parser.add_argument(
        "--master-depth-go",
        default="gomtdf {depth}",
        help="master fixed-depth go command template used with --depths",
    )
    parser.add_argument("--skills", default="1,5,10,15", help="comma-separated skill levels")
    parser.add_argument(
        "--cases",
        default=",".join(CASES.keys()),
        help="comma-separated case names; use --list-cases to inspect",
    )
    parser.add_argument("--repeat", type=int, default=1, help="measured runs per engine/case/skill")
    parser.add_argument("--timeout", type=float, default=600.0, help="seconds per search")
    parser.add_argument(
        "--option",
        action="append",
        default=[],
        help="override UCI option for both engines, as NAME=VALUE; repeatable",
    )
    parser.add_argument("--build-current", action="store_true", help="build target/release/tgf if missing")
    parser.add_argument("--csv", type=Path, help="optional CSV output path")
    parser.add_argument("--list-cases", action="store_true", help="print case names and exit")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.list_cases:
        list_cases()
        return 0

    assert args.repeat > 0, "--repeat must be positive"
    maybe_build_current(args.current, args.build_current)
    master_exe = executable_from_command(args.master)
    assert master_exe.exists(), f"master engine not found: {master_exe}"

    skills = parse_csv_ints(args.skills)
    case_names = parse_csv_names(args.cases)
    overrides = parse_kv_options(args.option)
    requested_depths = (
        [str(depth) for depth in parse_csv_ints(args.depths)]
        if args.depths
        else [""]
    )

    rows: list[ProbeResult] = []
    print_header()
    for case_name in case_names:
        case = CASES[case_name]
        for skill in skills:
            for requested_depth in requested_depths:
                current_go = (
                    args.current_depth_go.format(depth=requested_depth)
                    if requested_depth
                    else args.current_go
                )
                master_go = (
                    args.master_depth_go.format(depth=requested_depth)
                    if requested_depth
                    else args.master_go
                )
                for run in range(1, args.repeat + 1):
                    print(
                        f"# running current case={case.name} skill={skill} "
                        f"depth={format_optional(requested_depth)} run={run}",
                        file=sys.stderr,
                        flush=True,
                    )
                    current = probe_once(
                        "current",
                        args.current,
                        current_go,
                        case,
                        skill,
                        run,
                        requested_depth,
                        overrides,
                        args.timeout,
                    )
                    rows.append(current)
                    print_row(current)
                    print(
                        f"# running master case={case.name} skill={skill} "
                        f"depth={format_optional(requested_depth)} run={run}",
                        file=sys.stderr,
                        flush=True,
                    )
                    master = probe_once(
                        "master",
                        args.master,
                        master_go,
                        case,
                        skill,
                        run,
                        requested_depth,
                        overrides,
                        args.timeout,
                    )
                    rows.append(master)
                    print_row(master)

    print_summary(rows)
    if args.csv:
        write_csv(args.csv, rows)
        print(f"\nwrote {args.csv}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
