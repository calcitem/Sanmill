# Perfect DB error-patch mining data

Working state for the `tgf mill mine` / `tgf mill mine-endgame` pipeline
that produces `src/ui/flutter_app/assets/patches/std.mill_patch` (see
`crates/perfect-db/src/patch.rs` and `crates/tgf-cli/src/mill_mine/`,
`mill_endgame/`, `mill_pack/`, `mill_arena/` for the code).

Everything under this directory is **gitignored** (see the root
`.gitignore`'s `/mining/*/` rule) except this file: `entries.jsonl` and
`checkpoint.json` are large, fully regenerable-from-the-database working
data, not source. They are kept on disk (not in git) purely so mining can
resume from where it left off instead of restarting from scratch.

All runs below used the external full Malom database (not the small
subset bundled under `src/ui/flutter_app/assets/databases/`) at
`D:/user/Documents/strong` and `D:/Repo/NMM_LLM/human_database/human_db.sqlite`
for human-seeded runs. Adjust `--db`/`--human-db` if those paths differ
on the machine that resumes this.

## Subdirectories

Each holds `entries.jsonl` (mined `MineEntry` records, one per line --
the actual training data), `checkpoint.json` (resumable frontier/visited
state), and `log*.txt` (`eprintln!` output from the run(s) that produced
them, for reference).

* **opening/** -- `mill mine` from the empty board, `--max-depth-plies 10
  --budget-engine-calls 20000`. Fast, low remaining value; only worth
  resuming if opening coverage regresses.
* **placing/** -- `mill mine --human-db ... --placing-only --root-mass 0
  --budget-engine-calls 15000`. Superseded in practice by
  **placing_expanded/** below (same seeding, much larger budget); kept
  as-is since it was one of the inputs to the currently-bundled patch.
* **placing_expanded/** -- same as `placing/` but
  `--seed-phase placing --budget-engine-calls 400000
  --budget-seconds 7200`. The highest-value resume target: placing-phase
  coverage is still thin relative to its ~54-61% blunder density, and
  `checkpoint.json`'s `remaining_frontier` was in the hundreds of
  thousands when this last stopped on the time budget, not exhaustion.
* **moving/** -- `mill mine --human-db ... --seed-phase moving
  --max-depth-plies 8 --root-mass 0`, run across several `--resume`
  passes with growing budgets. `checkpoint.json` is ~1.6GB; expect a
  `--resume` run to need a similar amount of free memory to load it.
* **endgame/** -- `mill mine-endgame --min-side-pieces 3
  --min-total-pieces 6`, exhaustive (not sampled). `checkpoint.json` here
  is just the list of fully-completed `(white_on_board, black_on_board)`
  sectors (see `mill_endgame`'s own checkpoint format), currently
  total-pieces 6 through 9. Resuming with a higher `--max-total-pieces`
  picks up new sectors only; already-completed ones are skipped.
  **Sector density collapses fast past 4v4-ish material** (measured
  ~0-1% at total=8/9 vs ~38-60% at total<=7) -- expanding this further is
  low priority; see `placing_expanded/` instead.
* **closed_loop/** -- `mill mine --seed-fen-file seeds.txt --root-mass 0
  --max-depth-plies 24`, seeded from `mill arena --out`'s
  `first_uncovered_blunder_fen` values (a prior run's actual, still-losing
  games). `seeds.txt` is the seed list used; regenerate a fresh one from a
  new `mill arena --out arena.jsonl` run (see that command's module docs)
  before resuming this if you want it to target *today's* remaining
  losses rather than the ones already fixed.

## Resuming a run

Same flags as the original invocation, plus `--resume` and the same
`--checkpoint`/`--out` paths, e.g.:

```bash
tgf mill mine \
  --db "D:/user/Documents/strong" \
  --human-db "D:/Repo/NMM_LLM/human_database/human_db.sqlite" \
  --seed-phase placing --placing-only --root-mass 0 \
  --out mining/placing_expanded/entries.jsonl \
  --checkpoint mining/placing_expanded/checkpoint.json \
  --resume \
  --workers 20 --budget-engine-calls 400000 --budget-seconds 7200
```

`mill mine-endgame` resumes automatically (it always skips sectors already
listed in `--checkpoint`); just raise `--max-total-pieces` and rerun.

## Repacking after mining more

```bash
tgf mill patch-pack \
  --in "mining/opening/entries.jsonl,mining/placing/entries.jsonl,\
mining/placing_expanded/entries.jsonl,mining/moving/entries.jsonl,\
mining/endgame/entries.jsonl,mining/closed_loop/entries.jsonl" \
  --db "D:/user/Documents/strong" \
  --out src/ui/flutter_app/assets/patches/std.mill_patch \
  --budget-bytes 60000000 \
  --recompute-from-fen \
  --audit-sample 10000
```

Then validate with `tgf mill arena --db "D:/user/Documents/strong" \
--patch src/ui/flutter_app/assets/patches/std.mill_patch --games 1 \
--max-plies 200 --out arena.jsonl` before committing the regenerated
asset -- compare losses/draws against the previous run, and check
`arena.jsonl`'s `first_uncovered_blunder_fen` for new `closed_loop/`
seeds.
