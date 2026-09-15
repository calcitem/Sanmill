# H2H Anomaly Forensics

Use this mode when investigating deterministic H2H anomalies or reviewing
an associated baseline. Resolve `TGF`, `PY`, and `SCRATCH` from the current
environment; DB and approved-baseline paths are explicit inputs, not defaults.
The PR profile does not require a full local Perfect DB. Missing full-profile
data limits that mode; continue other applicable evidence collection.

Do not use aggregate win rate alone to decide whether a search change is safe.
For deterministic same-commit H2H, collect Trace v2 without adding work to the
live search, then analyze every game after the match:

```bash
bash scripts/run_head_to_head.sh --forensics \
  --analysis-out "$SCRATCH/h2h-forensics-pr"
```

The PR profile is fixed at self-current A/A, 32 paired openings (64 games),
Skill 30, MTD(f), one engine thread, four match jobs, `go nodes 100000`,
fixed opening/search seeds, and at most eight deep-search cases. For the local
full-DB profile:

```bash
FORENSICS_PROFILE=full \
  bash scripts/run_head_to_head.sh --forensics \
    --analysis-db /path/to/full-standard-nmm-db \
    --analysis-baseline /path/to/approved-full-db-baseline.json \
    --analysis-out "$SCRATCH/h2h-forensics-full"
```

That profile runs 500 paired openings (1000 games), 20 jobs, and at most 128
deep-search cases. It is intended for a local scheduled task; do not assume a
GitHub self-hosted runner is available.

To analyze an existing Trace v2 directly:

```bash
"$TGF" mill h2h-analyze \
  --log "$SCRATCH/h2h-trace/games.jsonl" \
  --manifest "$SCRATCH/h2h-trace/games.manifest.json" \
  --out-dir "$SCRATCH/h2h-report" \
  --db /path/to/perfect-db \
  --baseline /path/to/approved-baseline.json \
  --fail-on baseline
```

Accept a new baseline only after inspecting the report and confirming that
the update is within existing authorization. Producing a report is not
permission to replace an approved shared baseline. Preserve the previous
baseline and its evidence; never use acceptance to hide a failure.

```bash
"$TGF" mill h2h-baseline accept \
  --report "$SCRATCH/h2h-report/summary.json" \
  --out "$SCRATCH/approved-baseline.json"
```

Apply these evidence rules:

- `Hard` means a rule, state, replay, or search-contract contradiction. It
  always fails and can never be approved into a baseline.
- `Exact` means Perfect DB proved that a complete logical turn lowered WDL.
  This is a move error, not automatically an engineering defect.
- `Probable` requires PVS and MTD(f) to agree at both triage and confirmation
  node budgets on the same better complete logical turn.
- `Unresolved` is never silently treated as safe. Preserve the evidence bundle
  so a human or LLM can investigate it.

Baseline comparisons use paired openings as the statistical unit and a
deterministic 99.9% paired confidence interval. Block an ordinary move-error
metric only when the lower confidence bound of the regression is greater than
zero. Profile, database, or coverage mismatch is a configuration failure, not
a pass. Hard anomalies bypass statistical gating.

Retain the complete report artifact set:

```text
summary.json
findings.jsonl
losses.jsonl
clusters.json
report.md
cases/<case-id>.json
cases/<case-id>.md
SHA256SUMS
```

The sibling Trace v2 JSONL and manifest are also required. Never copy arbitrary
process environment values into artifacts: record variable names and SHA-256
value hashes unless a specific safe engine switch is explicitly allowlisted.
When the analyzer cannot prove a cause, the case Markdown must still contain
the exact root, state/history, atomic actions grouped into logical turns, UCI
output, DB result, deterministic search matrix, process replay comparison, and
a copyable reproduction command.

Generating an evidence bundle does not require stopping after the first
finding. Continue classification and authorized diagnosis or repair. Preserve
unresolved cases and state exactly what prevents further conclusions. Follow
[AGENTS.md](../../../../AGENTS.md) for task completion and commit boundaries.
