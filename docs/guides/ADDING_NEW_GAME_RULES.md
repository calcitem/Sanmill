# Adding New Mill Rule Variants

Sanmill's active rules engine is the Rust/TGF implementation.  New Mill rule
variants are represented as data in `MillVariantOptions`, mapped from Flutter
`RuleSettings`, and passed to Rust through the FRB API.

## Quick Start

**Typical change:** add or adjust Rust Mill options, map them from Flutter,
update UI strings, and add Rust/Flutter tests.

**Main steps**

1. Add or update fields in `crates/tgf-mill/src/rules/types.rs`.
2. Implement the behavior in `crates/tgf-mill/src/rules/`.
3. Expose the option through `crates/tgf-frb/src/api/simple.rs`.
4. Map Flutter `RuleSettings` in
   `src/ui/flutter_app/lib/games/mill/mill_variant_options_mapper.dart`.
5. Update Flutter rule settings models, UI, and localization if the variant is
   user-visible.
6. Add focused tests and run the Rust/Flutter validation commands.

## Architecture

```
Mill rule flow:
├── Flutter settings
│   ├── lib/rule_settings/models/rule_settings.dart
│   ├── lib/rule_settings/widgets/...
│   └── lib/games/mill/mill_variant_options_mapper.dart
│
├── FRB API
│   ├── crates/tgf-frb/src/api/simple.rs
│   ├── crates/tgf-frb/src/api/mill_kernel.rs
│   └── src/ui/flutter_app/lib/src/rust/api/*.dart (generated)
│
├── Rust rules and search
│   ├── crates/tgf-mill/src/rules/types.rs
│   ├── crates/tgf-mill/src/rules/legal_actions.rs
│   ├── crates/tgf-mill/src/rules/legal_apply.rs
│   ├── crates/tgf-mill/src/rules/transitions.rs
│   ├── crates/tgf-mill/src/rules/fen.rs
│   └── crates/tgf-search/src/
│
└── Tests
    ├── crates/tgf-mill/src/rules/tests.rs
    ├── crates/tgf-mill/tests/
    ├── crates/tgf-frb/src/api/simple_tests.rs
    └── src/ui/flutter_app/test/
```

## Rust Rule Options

Rule options live in `MillVariantOptions`:

```rust
pub struct MillVariantOptions {
    pub piece_count: u8,
    pub fly_piece_count: u8,
    pub pieces_at_least_count: u8,
    pub may_fly: bool,
    pub has_diagonal_lines: bool,
    pub mill_formation_action_in_placing_phase:
        MillFormationActionInPlacingPhase,
    pub may_remove_from_mills_always: bool,
    pub may_remove_multiple: bool,
    pub n_move_rule: u32,
    pub endgame_n_move_rule: u32,
    pub may_move_in_placing_phase: bool,
    pub is_defender_move_first: bool,
    pub restrict_repeated_mills_formation: bool,
    pub one_time_use_mill: bool,
    pub stop_placing_when_two_empty_squares: bool,
    pub board_full_action: MillBoardFullAction,
    pub threefold_repetition_rule: bool,
    pub custodian_capture: CaptureRuleConfig,
    pub intervention_capture: CaptureRuleConfig,
    pub leap_capture: CaptureRuleConfig,
    pub stalemate_action: StalemateAction,
    pub consider_mobility: bool,
    pub focus_on_blocking_paths: bool,
}
```

When adding a field:

- Give it a conservative default in `Default for MillVariantOptions`.
- Add assertions in `MillVariantOptions::assert_valid` when the field has a
  constrained range.
- Keep hot-path checks cheap.  Prefer an early return when the feature is off.
- Add tests for both enabled and disabled behavior.

## Rule Presets

Named presets live in `crates/tgf-mill/src/presets.rs`.  Update them when the
new option changes a canonical variant or when a new named variant is added.
Keep `N_PRESETS`, preset ids, Flutter `RuleSet` values, and localization in
sync.

Preset order is an app-level compatibility contract.  Do not reorder existing
entries unless you also migrate persisted settings.

## Gameplay Logic

Use the existing module split:

- `legal_actions.rs` for legal move generation.
- `legal_apply.rs` for applying an action and adjudicating terminal outcomes.
- `transitions.rs` for shared state transitions and small rule helpers.
- `captures.rs` for custodian, intervention, and leap capture helpers.
- `fen.rs` for FEN import/export and position hashing helpers.
- `evaluation.rs` and `game_impls.rs` when search evaluation or move ordering
  must change.

Keep `tgf-core` and `tgf-search` game-neutral.  Mill-specific behavior belongs
in `crates/tgf-mill`.

## Flutter and FRB Mapping

Flutter sends typed options through FRB, not UCI strings.

When adding a Rust option:

1. Add the field to `MillVariantOptions` in
   `crates/tgf-frb/src/api/simple.rs`.
2. Update conversions between the FRB DTO and
   `tgf_mill::MillVariantOptions`.
3. Regenerate FRB bindings:

   ```bash
   cd src/ui/flutter_app
   flutter_rust_bridge_codegen generate
   ```

4. Map the field in
   `lib/games/mill/mill_variant_options_mapper.dart`.
5. Add or update Flutter rule settings UI and localization when the field is
   user-facing.

## FEN Extensions

Extend FEN only for dynamic state that cannot be recomputed from the board and
rule options.  Examples include active capture targets, delayed marked pieces,
or multi-step removal state.

Do not extend FEN for static rule parameters such as piece count, diagonal
lines, or draw-rule toggles.

Current extension tokens are appended after the legacy-compatible base fields:

```text
...STANDARD_FEN... [c:...] [i:...] [l:...] [p:...] [s:...]
```

Update `crates/tgf-mill/src/rules/fen.rs` and add round-trip tests whenever a
new token is introduced.  Missing extension tokens must parse to explicit
backward-compatible defaults.

## Testing

Use focused tests first:

```bash
cargo test -p tgf-mill <test_name>
cargo test -p rust_lib_sanmill <test_name>
cd src/ui/flutter_app && flutter test <test_path>
```

Before committing Rust rule changes, run:

```bash
cargo test -p tgf-mill
cargo test -p tgf-cli mill_uci
cargo test -p rust_lib_sanmill mill_kernel
./format.sh s
```

For search-sensitive changes, also run:

```bash
cargo run --release -p tgf-cli -- bench
python scripts/check_perf_baseline.py \
  --baseline tests/perf_baseline.toml \
  --result target/tgf_perf_result.toml
```

Use `scripts/run_head_to_head.sh` when the change may affect engine strength
or parity with the master reference engine.

## Review Checklist

- [ ] Option defaults preserve existing variants.
- [ ] `assert_valid` catches invalid combinations.
- [ ] Legal generation and apply paths agree.
- [ ] Search evaluation or move ordering changes have targeted tests.
- [ ] FEN changes round-trip and remain backward-compatible.
- [ ] Flutter settings map every new FRB field.
- [ ] User-facing strings are localized through ARB files.
- [ ] `./format.sh s` passes.
