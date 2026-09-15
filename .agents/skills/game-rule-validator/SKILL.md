---
name: game-rule-validator
description: Check completeness when adding a Mill variant or changing rule mechanics or option structure. Use for those changes and their reviews, not wording-only UI edits.
---

# Mill Rule Completeness Validator

Validate the layers affected by a rule change. For a review-only request,
report gaps without implementing them; for an implementation request, complete
the affected layers and their validation.

Read [Adding New Mill Rule Variants](../../../docs/guides/ADDING_NEW_GAME_RULES.md)
for the current options, presets, mapping, and FEN contract. Do not require a
fixed file count or every layer below for a parameter-only change.

## Conditional checklist

| When the change affects | Check |
| --- | --- |
| Rule options | `crates/tgf-mill/src/rules/types.rs`: defaults, validation, and enabled/disabled behavior |
| Named presets | `crates/tgf-mill/src/presets.rs`: preset count and IDs; preserve existing order and persisted identities |
| Legal actions or transitions | Relevant modules under `crates/tgf-mill/src/rules/`: legal generation, apply, captures, terminal adjudication, and undo |
| Flutter-exposed options | `crates/tgf-frb/src/api/simple.rs`: typed DTO and Rust conversions; regenerate both FRB halves |
| Flutter settings | `lib/games/mill/mill_variant_options_mapper.dart` and `lib/rule_settings/` under the Flutter app: mappings, defaults, UI selection, save/restore |
| User-facing messages | Follow [arb-translation-updater](../arb-translation-updater/SKILL.md) for the four-locale tail gate and real translations |
| CLI options | Update `crates/tgf-cli/src/mill_uci/` when the option is exposed through UCI; Flutter itself uses typed FRB options |
| Dynamic persisted state | FEN/snapshot/session codecs, history, replay, and backward-compatible round trips |
| Evaluation or search behavior | Mill evaluation/move ordering and appropriate correctness, performance, and strength evidence |

Flutter paths in the table are relative to `src/ui/flutter_app`.
Gameplay implementation belongs in Rust; do not add a Dart position-engine
mirror or modify the removed `src/rule.cpp` / `src/position.cpp` paths.

## Rule and data invariants

- Express variants as data and parameters with conservative defaults.
  Existing variants must retain their behavior unless the requested change
  explicitly changes one.
- Keep `tgf-core` and `tgf-search` game-neutral. Gate Mill-specific
  mechanics so disabled features do not penalize existing hot paths.
- Legal generation and action application must agree. Pending captures or
  other mandatory continuation actions must complete before terminal
  adjudication when required by the rule.
- Preserve apply/undo, repetition/history, and serialization semantics.
- Extend FEN only for dynamic state that cannot be reconstructed from the board
  and rule options. Do not add static rule parameters to FEN. Append compatible
  extensions, define missing-field defaults, and test round trips.
- Preserve Hive type IDs and field indices, preset identities, old saves, and
  imports. Use an explicit migration when a compatible representation is not
  possible; do not silently reset user settings.
- Do not overwrite oracle snapshots or weaken tests to conceal a regression.

## Validation and result

Run focused tests after a coherent change, then the required checks in
[AGENTS.md](../../../AGENTS.md). In particular, Rust engine changes require
`cargo test --workspace`; relevant Flutter mappings, save/restore behavior,
new UI components, and native paths need their own tests.

Measure hot-path changes, including behavior with a new feature disabled.
Device builds depend on the affected path and available targets; record
unavailable coverage instead of requiring every platform on one host.

Report affected layers, completed checks, missing or untested conditions, and
any intentional compatibility change. For implementation work, continue fixing
task-caused failures until the requested result is complete or a specific
external dependency prevents further progress.
