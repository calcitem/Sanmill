#!/usr/bin/env python3
"""Regenerate hardcoded Mill self-play expectations.

This tool updates the expected move lists in:

    crates/tgf-mill/tests/ai_selfplay_master_parity.rs

Typical workflows:

    cargo build -p tgf-cli --release

    # Preserve legacy master parity expectations.
    python3 tools/update_selfplay_expectations.py --source master --write

    # Bless the current Rust engine after an intentional search change.
    python3 tools/update_selfplay_expectations.py --source current --write

    # Check whether selected expectations are stale without editing files.
    python3 tools/update_selfplay_expectations.py \\
        --source current --standard --skills 1-8 --check

The script is intentionally explicit about the source engine because these
tests can be used in two different ways: conservative master parity checks or
new baseline checks after a deliberate search-ordering change.
"""

from __future__ import annotations

import argparse
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TARGET = REPO_ROOT / "crates/tgf-mill/tests/ai_selfplay_master_parity.rs"
DEFAULT_CURRENT = "target/release/tgf uci"
DEFAULT_MASTER = str(Path.home() / "Sanmill-master" / "master_engine")
DEFAULT_MAX_PLIES = 400

BASE_OPTIONS = {
    "SkillLevel": "2",
    "MoveTime": "0",
    "AiIsLazy": "false",
    "IDSEnabled": "false",
    "DepthExtension": "true",
    "Shuffling": "false",
    "UseLazySmp": "false",
    "Algorithm": "2",
    "DrawOnHumanExperience": "true",
    "UsePerfectDatabase": "false",
    "DeveloperMode": "false",
    "MaxQuiescenceDepth": "0",
    "NMoveRule": "20",
    "EndgameNMoveRule": "20",
}

VARIANT_CASE_OPTIONS = {
    "removal_based_on_mill_counts": (
        ("MillFormationActionInPlacingPhase", "5"),
    ),
    "twelve_mens_board_full_first_second_remove": (
        ("PiecesCount", "12"),
        ("BoardFullAction", "1"),
    ),
    "custodian_capture": (("CustodianCaptureEnabled", "true"),),
    "intervention_capture": (("InterventionCaptureEnabled", "true"),),
    "leap_capture": (("LeapCaptureEnabled", "true"),),
    "hand_remove_opponent_turn": (
        ("MillFormationActionInPlacingPhase", "1"),
    ),
    "mark_delay_remove": (("MillFormationActionInPlacingPhase", "4"),),
    "twelve_mens_stop_two_empty": (
        ("PiecesCount", "12"),
        ("StopPlacingWhenTwoEmptySquares", "true"),
    ),
    "twelve_mens_mark_delay": (
        ("PiecesCount", "12"),
        ("MillFormationActionInPlacingPhase", "4"),
    ),
    "defender_first_removal_based": (
        ("IsDefenderMoveFirst", "true"),
        ("MillFormationActionInPlacingPhase", "5"),
    ),
    "diagonal_removal_based": (
        ("HasDiagonalLines", "true"),
        ("MillFormationActionInPlacingPhase", "5"),
    ),
    "custodian_intervention_multi": (
        ("CustodianCaptureEnabled", "true"),
        ("InterventionCaptureEnabled", "true"),
        ("MayRemoveMultiple", "true"),
    ),
    "capture_no_mill_removal_relax": (
        ("CustodianCaptureEnabled", "true"),
        ("InterventionCaptureEnabled", "true"),
        ("MayRemoveFromMillsAlways", "true"),
    ),
    "one_time_restrict_repeated": (
        ("OneTimeUseMill", "true"),
        ("RestrictRepeatedMillsFormation", "true"),
    ),
}

VARIANT_CALL_RE = re.compile(
    r"assert_selfplay_variant_prefix\(\s*"
    r"\n\s*\"(?P<label>[^\"]+)\",\s*"
    r"\n\s*(?P<skill>\d+),\s*"
    r"\n\s*(?P<plies>\d+),",
    re.MULTILINE,
)


class UciEngine:
    def __init__(self, command: str, timeout: float, terminal_phase: int) -> None:
        self.command = command
        self.timeout = timeout
        self.terminal_phase = terminal_phase
        self.process = subprocess.Popen(
            shlex.split(command),
            cwd=REPO_ROOT,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

    def close(self) -> None:
        if self.process.poll() is None:
            try:
                self.send("quit")
            except BrokenPipeError:
                pass
            try:
                self.process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                self.process.kill()

    def send(self, line: str) -> None:
        assert self.process.stdin is not None, "UCI stdin closed"
        self.process.stdin.write(line + "\n")
        self.process.stdin.flush()

    def read_until(self, token: str) -> str:
        deadline = time.monotonic() + self.timeout
        last = ""
        while time.monotonic() < deadline:
            assert self.process.stdout is not None, "UCI stdout closed"
            line = self.process.stdout.readline()
            if line == "":
                raise RuntimeError(
                    f"{self.command!r} exited while waiting for {token!r}"
                )
            last = line.strip()
            if token in last:
                return last
        raise TimeoutError(
            f"{self.command!r} timed out waiting for {token!r}; last={last!r}"
        )

    def initialize(self, options: dict[str, str]) -> None:
        self.send("uci")
        self.read_until("uciok")
        for name, value in options.items():
            self.send(f"setoption name {name} value {value}")
        self.send("isready")
        self.read_until("readyok")
        self.send("ucinewgame")

    def bestmove(self, moves: list[str]) -> str:
        position = "position startpos"
        if moves:
            position += " moves " + " ".join(moves)
        self.send(position)
        self.send("go")
        raw = self.read_until("bestmove")
        tokens = raw.split()
        if "bestmove" not in tokens:
            return ""
        index = tokens.index("bestmove") + 1
        if index >= len(tokens):
            return ""
        move = tokens[index]
        if move in {"", "(none)", "none", "0000", "draw"}:
            return ""
        return move

    def terminal(self, moves: list[str]) -> bool:
        position = "position startpos"
        if moves:
            position += " moves " + " ".join(moves)
        self.send(position)
        self.send("evaldecomp")
        self.send("isready")
        lines: list[str] = []
        seen_evaldecomp = False
        while True:
            assert self.process.stdout is not None, "UCI stdout closed"
            line = self.process.stdout.readline()
            if line == "":
                raise RuntimeError(
                    f"{self.command!r} exited while waiting for evaldecomp phase"
                )
            last = line.strip()
            if "evaldecomp" in last:
                seen_evaldecomp = True
            if seen_evaldecomp:
                lines.append(last)
                match = re.search(r"\bphase=[^0-9]*(\d+)", last)
                if match:
                    return int(match.group(1)) == self.terminal_phase
            if "readyok" in last:
                break
        joined = " ".join(lines)
        match = re.search(r"\bphase=[^0-9]*(\d+)", joined)
        if match:
            return int(match.group(1)) == self.terminal_phase
        raise AssertionError(
            f"{self.command!r} evaldecomp did not report phase: {lines!r}"
        )


def parse_skill_list(value: str) -> list[int]:
    out: list[int] = []
    for part in value.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            start, end = part.split("-", 1)
            lo = int(start)
            hi = int(end)
            assert lo <= hi, f"invalid descending skill range: {part}"
            out.extend(range(lo, hi + 1))
        else:
            out.append(int(part))
    assert out, "--skills must name at least one skill"
    assert all(skill >= 0 for skill in out), "--skills values must be non-negative"
    return out


def parse_variant_labels(value: str) -> set[str] | None:
    if value == "all":
        return None
    labels = {part.strip() for part in value.split(",") if part.strip()}
    assert labels, "--variant-labels must be 'all' or a non-empty list"
    return labels


def normalize_variant_label(label: str) -> str:
    for suffix in ("_transition", "_deep"):
        if label.endswith(suffix):
            return label[: -len(suffix)]
    return label


def options_for(skill: int, overrides: tuple[tuple[str, str], ...]) -> dict[str, str]:
    options = dict(BASE_OPTIONS)
    options["SkillLevel"] = str(skill)
    options.update(overrides)
    return options


def run_selfplay(
    command: str,
    terminal_phase: int,
    skill: int,
    max_plies: int,
    option_overrides: tuple[tuple[str, str], ...],
    expected_stop: list[str] | None,
    allow_expected_terminal_stop: bool,
    timeout: float,
) -> list[str]:
    assert max_plies > 0, "max_plies must be positive"
    engine = UciEngine(command, timeout, terminal_phase)
    moves: list[str] = []
    try:
        engine.initialize(options_for(skill, option_overrides))
        for _ in range(max_plies):
            if (
                allow_expected_terminal_stop
                and expected_stop is not None
                and len(moves) == len(expected_stop)
                and moves == expected_stop
                and engine.terminal(moves)
            ):
                break
            move = engine.bestmove(moves)
            if not move:
                break
            moves.append(move)
    finally:
        engine.close()
    return moves


def format_array_literal(moves: list[str], indent: str) -> str:
    lines = ["&["]
    for start in range(0, len(moves), 8):
        chunk = moves[start : start + 8]
        quoted = ", ".join(f'"{move}"' for move in chunk)
        lines.append(f"{indent}    {quoted},")
    lines.append(f"{indent}]")
    return "\n".join(lines)


def format_const(name: str, moves: list[str]) -> str:
    return f"const {name}: &[&str] = {format_array_literal(moves, '')};"


def move_literals(text: str) -> list[str]:
    return re.findall(r'"([^"]+)"', text)


def const_block(text: str, name: str) -> str:
    pattern = re.compile(
        rf"const {re.escape(name)}: &\[&str\] = &\[\n.*?\n\];",
        re.DOTALL,
    )
    match = pattern.search(text)
    assert match is not None, f"could not find Rust const {name}"
    return match.group(0)


def const_moves(text: str, name: str) -> list[str]:
    return move_literals(const_block(text, name))


def replace_const(text: str, name: str, moves: list[str]) -> str:
    pattern = re.compile(
        rf"const {re.escape(name)}: &\[&str\] = &\[\n.*?\n\];",
        re.DOTALL,
    )
    updated, count = pattern.subn(format_const(name, moves), text, count=1)
    assert count == 1, f"could not find Rust const {name}"
    return updated


def find_matching_bracket(text: str, open_index: int) -> int:
    depth = 0
    in_string = False
    escaped = False
    for index in range(open_index, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                return index
    raise AssertionError("unterminated Rust array literal")


def variant_array_bounds(text: str, label: str) -> tuple[int, int]:
    label_pos = text.index(f'"{label}"')
    array_start = text.index("&[", label_pos)
    bracket_start = array_start + 1
    array_end = find_matching_bracket(text, bracket_start)
    return array_start, array_end


def variant_moves(text: str, label: str) -> list[str]:
    array_start, array_end = variant_array_bounds(text, label)
    return move_literals(text[array_start : array_end + 1])


def replace_variant_array(text: str, label: str, moves: list[str]) -> str:
    array_start, array_end = variant_array_bounds(text, label)
    replacement = format_array_literal(moves, "        ")
    return text[:array_start] + replacement + text[array_end + 1 :]


def update_standard_constants(
    text: str,
    command: str,
    terminal_phase: int,
    skills: list[int],
    timeout: float,
) -> tuple[str, list[str], bool]:
    summaries: list[str] = []
    changed = False
    for skill in skills:
        name = f"MASTER_GO_SKILL{skill}_FULL_GAME"
        expected = const_moves(text, name)
        moves = run_selfplay(
            command,
            terminal_phase,
            skill,
            DEFAULT_MAX_PLIES,
            (),
            expected,
            False,
            timeout,
        )
        item_changed = expected != moves
        changed |= item_changed
        text = replace_const(text, name, moves)
        status = "changed" if item_changed else "unchanged"
        summaries.append(f"{name}: {len(moves)} plies {status}")
    return text, summaries, changed


def update_n30_endgame20_constant(
    text: str,
    command: str,
    terminal_phase: int,
    timeout: float,
) -> tuple[str, str, bool]:
    name = "MASTER_GO_SKILL15_N30_ENDGAME20_FULL_GAME"
    expected = const_moves(text, name)
    moves = run_selfplay(
        command,
        terminal_phase,
        15,
        DEFAULT_MAX_PLIES,
        (("NMoveRule", "30"), ("EndgameNMoveRule", "20")),
        expected,
        False,
        timeout,
    )
    changed = expected != moves
    status = "changed" if changed else "unchanged"
    return replace_const(text, name, moves), f"{name}: {len(moves)} plies {status}", changed


def update_variant_prefixes(
    text: str,
    command: str,
    terminal_phase: int,
    timeout: float,
    requested_labels: set[str] | None,
) -> tuple[str, list[str], bool]:
    summaries: list[str] = []
    calls = list(VARIANT_CALL_RE.finditer(text))
    assert calls, "no assert_selfplay_variant_prefix calls found"
    known_labels = {call.group("label") for call in calls}
    exact_labels = requested_labels & known_labels if requested_labels else set()
    case_labels = requested_labels - known_labels if requested_labels else set()
    matched_labels: set[str] = set()
    changed = False
    for call in calls:
        label = call.group("label")
        skill = int(call.group("skill"))
        plies = int(call.group("plies"))
        case_name = normalize_variant_label(label)
        if requested_labels is not None:
            matched = set()
            if label in exact_labels:
                matched.add(label)
            if case_name in case_labels:
                matched.add(case_name)
            if not matched:
                continue
            matched_labels.update(matched)
        assert (
            case_name in VARIANT_CASE_OPTIONS
        ), f"no UCI option mapping for variant prefix {label!r}"
        expected = variant_moves(text, label)
        moves = run_selfplay(
            command,
            terminal_phase,
            skill,
            plies,
            VARIANT_CASE_OPTIONS[case_name],
            expected,
            len(expected) < plies,
            timeout,
        )
        item_changed = expected != moves
        changed |= item_changed
        text = replace_variant_array(text, label, moves)
        status = "changed" if item_changed else "unchanged"
        summaries.append(f"{label}: {len(moves)} plies {status}")
    if requested_labels is not None:
        missing = requested_labels - matched_labels
        assert not missing, f"unknown variant labels: {', '.join(sorted(missing))}"
    return text, summaries, changed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--source", choices=("current", "master"), required=True)
    parser.add_argument("--current", default=DEFAULT_CURRENT)
    parser.add_argument("--master", default=DEFAULT_MASTER)
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET)
    parser.add_argument("--skills", default="1-15")
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("--standard", action="store_true")
    parser.add_argument("--n30-endgame20", action="store_true")
    parser.add_argument("--variant-prefixes", action="store_true")
    parser.add_argument(
        "--variant-labels",
        default="all",
        help=(
            "comma-separated Rust labels to update; names without exact "
            "label matches fall back to normalized case labels"
        ),
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="return non-zero if regenerated expectations differ from target",
    )
    parser.add_argument("--write", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    target = args.target.resolve()
    assert target.is_file(), f"target file does not exist: {target}"
    assert not (args.check and args.write), "--check cannot be combined with --write"
    command = args.current if args.source == "current" else args.master
    terminal_phase = 3 if args.source == "current" else 4

    run_standard = args.standard
    run_n30 = args.n30_endgame20
    run_variants = args.variant_prefixes
    if not (run_standard or run_n30 or run_variants):
        run_standard = True
        run_n30 = True
        run_variants = True

    original_text = target.read_text()
    text = original_text
    summaries: list[str] = []
    semantic_changed = False
    if run_standard:
        text, standard_summaries, standard_changed = update_standard_constants(
            text,
            command,
            terminal_phase,
            parse_skill_list(args.skills),
            args.timeout,
        )
        summaries.extend(standard_summaries)
        semantic_changed |= standard_changed
    if run_n30:
        text, n30_summary, n30_changed = update_n30_endgame20_constant(
            text, command, terminal_phase, args.timeout
        )
        summaries.append(n30_summary)
        semantic_changed |= n30_changed
    if run_variants:
        text, variant_summaries, variants_changed = update_variant_prefixes(
            text,
            command,
            terminal_phase,
            args.timeout,
            parse_variant_labels(args.variant_labels),
        )
        summaries.extend(variant_summaries)
        semantic_changed |= variants_changed

    if args.check:
        print("target is stale" if semantic_changed else "target is up to date")
    elif args.write:
        if semantic_changed:
            target.write_text(text)
    else:
        print("dry-run only; pass --write to update the Rust test file")
    print(f"target_changed={semantic_changed}")
    print(f"source={args.source} command={command!r}")
    for summary in summaries:
        print(summary)
    return 1 if args.check and semantic_changed else 0


if __name__ == "__main__":
    sys.exit(main())
