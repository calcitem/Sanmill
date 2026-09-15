# Sanmill Agent Instructions

Sanmill is an AGPL v3 Mill game with a Flutter UI and a Rust/TGF rules and
search engine. Contributions must remain AGPL v3 compatible. Preserve support
for Android, iOS, Windows, macOS, and Linux, mobile-first usability, and the
correctness and performance constraints below.

## Scope and completion

- Follow the user's requested outcome and existing authorization. A request
  for an audit or recommendations is complete when the findings are delivered;
  do not implement changes in that mode.
- For implementation work, continue through the requested implementation,
  relevant validation, and repair of failures caused by the change. Routine
  local edits, diagnosis, and reruns within that scope do not need repeated
  confirmation. A first draft or a failed test is not a review gate by itself.
- Explain consequential choices and assumptions briefly. A progress update
  does not require waiting for approval.
- Ask when an unresolved business decision would materially change the result,
  or the next action needs authorization that has not been given. Continue
  independent work while that decision is pending.
- User instructions take precedence over workflow advice in project Skills,
  subject to higher-priority execution and safety requirements. If an
  instruction blocks work, identify the file and exact requirement and explain
  the remaining obstacle; do not silently stop or repeatedly ask to continue.
- Preserve unrelated work, user data, credentials, database assets, and
  historical evidence. Do not clean or reset a worktree to obtain a clean
  status. Scope any rollback to changes made for the current task.
- Local tests may run without repeated approval when their data and access
  are known to be isolated. Do not assume all device or integration tests use
  disposable data. Production changes, destructive data operations, privileged
  commands, and external publication must remain within explicit authorization
  and the environment's permission boundaries.

## Architecture and task-specific references

| Area | Source of truth / when to read |
| --- | --- |
| Framework and bridge contracts | [docs/FRAMEWORK_API.md](docs/FRAMEWORK_API.md), when changing framework or FRB boundaries |
| Mill rules, presets, and option mapping | [docs/guides/ADDING_NEW_GAME_RULES.md](docs/guides/ADDING_NEW_GAME_RULES.md), when adding or changing rules |
| Puzzle import/export | [docs/PUZZLE_FORMAT.md](docs/PUZZLE_FORMAT.md), when changing the puzzle format |
| Flutter dependencies and localization output | `src/ui/flutter_app/pubspec.yaml` and `src/ui/flutter_app/l10n.yaml` |
| Specialized agent workflows | [.agents/skills/README.md](.agents/skills/README.md), when a listed workflow fits the task |

Read the references needed for the task; this table is not a prerequisite
reading list for every edit.

- `crates/tgf-core` defines game-neutral traits and POD types;
  `crates/tgf-search` contains generic searchers. Keep both game-neutral.
- Concrete games belong in `crates/tgf-<game_id>/`. Mill rules, topology,
  evaluation, and presets live in `crates/tgf-mill`; `tgf-othello` exercises
  the framework with a second game.
- `crates/tgf-frb` exposes `rust_lib_sanmill` to Flutter. The app is under
  `src/ui/flutter_app`; CLI and benchmark tools are in `crates/tgf-cli`.
- Gameplay decisions and AI search belong in Rust/TGF. Flutter maps options,
  presents native state, and manages UI interactions; do not recreate the
  removed C++/Dart position-engine mirror.
- Remaining C/C++ includes platform Runner code and the optional Perfect DB
  oracle in `crates/perfect-db/csrc`, built with the `cpp-oracle` feature.
  Third-party native code is not a general formatting target.
- Checked-in `crates/tgf-mill/testdata/legacy_oracle/` snapshots are preserved
  regression evidence from the removed engine. Do not regenerate or rewrite
  them just to make a changed implementation pass, or describe replaying them
  as a fresh run of the legacy binary.
- Resolve reference and candidate revisions from the task and actual Git
  state. Branch names such as `master` and `next` do not identify an
  implementation language.

## Implementation constraints

### Rust and native code

- Preserve monomorphized `Searcher<G: Game>` and
  `Game / Workbench / Evaluator` search paths. Do not introduce `dyn
  GameRules` or unmeasured heap allocation into move-generation hot paths.
- Assert internal preconditions and invariants. Surface errors rather than
  masking impossible states with fallback results. External input still needs
  explicit validation and errors; assertions do not replace it.
- Modify the owning implementation directly. Avoid interception-only wrappers
  or `Enhanced` / `Extended` replacements for existing types.
- For performance work, use a declared baseline and comparable measurements.
  Preserve exact declared behavior for parity-preserving changes. Algorithmic
  changes require appropriate correctness and strength evidence.
- Introduce `unsafe` only for a measured need, with local invariants,
  `SAFETY:` comments, focused tests, and benchmark evidence. Keep optional
  diagnostics out of release hot paths.

When a Rust module grows beyond roughly 1,000 lines or needs sibling helpers:

- Convert `foo.rs` to `foo/mod.rs` when adding implementation siblings.
- A large test block for a still-flat module belongs in `foo_tests.rs`,
  referenced with `#[cfg(test)] #[path = "foo_tests.rs"] mod tests;`.
- A directory module uses `foo/tests.rs` with `#[cfg(test)] mod tests;`;
  no `#[path]` is needed.
- Prefer `pub(super)` for sibling helpers unless broader access is necessary.

### Flutter, persistence, and localization

- Use the existing state management approach and keep business logic out of
  widgets. Discuss introducing a new state management library unless that
  architectural choice is already authorized.
- Keep user-facing strings in ARB files and use `S.of(context)` from
  `lib/generated/intl/l10n.dart`. Use descriptive keys, plural forms where
  needed, and complete localized messages instead of concatenation.
- For new message keys or batch translation synchronization, follow
  [.agents/skills/arb-translation-updater/SKILL.md](.agents/skills/arb-translation-updater/SKILL.md).
  That Skill owns the en/de/hu/zh tail gate and translation quality rules.
  A wording-only edit does not imply adding keys to other locales.
- Preserve persisted preset identities, Hive type IDs, and existing field
  indices. Add new `@HiveField` indices sequentially; do not reuse old
  indices. Provide compatible defaults or a deliberate migration.
- Check relevant long translations, RTL layouts, and accessibility for UI
  changes. Keep spaces between Chinese and English in mixed text.

## Generated code and initialization

Run `./flutter-init.sh` from the repository root when setting up a checkout
or after dependency changes. For an already initialized checkout, regenerate
only the outputs affected by the change.

| Change / output | Required action |
| --- | --- |
| Hive, `@JsonSerializable`, or `@CopyWith` models | Run `dart run build_runner build` from `src/ui/flutter_app` |
| Asset declarations / FlutterGen | Regenerate `lib/generated/assets/assets.gen.dart` through build_runner |
| ARB messages | Run `flutter gen-l10n` from the Flutter app directory |
| Rust FRB API | Regenerate both bridge halves with `flutter_rust_bridge_codegen generate` from the Flutter app directory |

- Never hand-create or edit generated code, including Hive adapters.
  Keep the model's `part 'filename.g.dart';` directive.
- `*.g.dart` and FlutterGen/localization output are ignored. Do not commit
  them. If FlutterGen output is missing because of a stale build_runner cache,
  run `dart run build_runner clean` followed by `dart run build_runner build`.
- FRB is the intentional exception: commit the generated Dart bindings under
  `lib/src/rust/` and `crates/tgf-frb/src/frb_generated.rs` together with an
  API change. Both halves must agree on layouts and the native library stem
  `rust_lib_sanmill`.
- Native, dependency, asset, generated-code, or Rust/FRB changes need the
  relevant regeneration and platform rebuild. Hot reload is not sufficient.

For Dart-only iteration in an active debug session, use available Flutter/Dart
MCP or DTD tools for inspection and hot reload. Otherwise keep `flutter run`
alive and send `r` for reload or `R` for restart. Validate the final result
according to the next section.

## Validation

Choose checks for the changed behavior and complete the required checks below.
Run focused checks after a coherent change; do not rerun broad suites after
each individual file edit. Once checks pass, repeat or broaden them only for
new changes, failures, or unresolved risks.

| Change | Required validation |
| --- | --- |
| Rust engine behavior | Add or update meaningful regression tests; run focused tests, then `cargo test --workspace` |
| New Flutter UI components | Widget tests plus relevant screen-reader and keyboard behavior checks |
| Flutter implementation | `flutter analyze`, focused tests, and the relevant platform build; hot reload alone is insufficient |
| Rule / state / bridge / persistence changes | Relevant round-trip, mapping, compatibility, and native integration checks |
| Search hot paths | Comparable correctness and performance evidence; use the appropriate audit workflow |
| Documentation / Skill / ignore-rule changes only | Validate references, commands, Skill metadata, and scope; application suites are not required solely for prose changes |

For Flutter tests, use
[.agents/skills/flutter-test-runner/SKILL.md](.agents/skills/flutter-test-runner/SKILL.md)
when selecting or diagnosing the appropriate runner. Device and cross-platform
checks depend on the affected path and release requirements. If an environment
is unavailable, report that coverage gap, continue other checks, and do not
claim full platform validation.

Report pass, fail, and skip counts separately. Fix regressions caused by this
task; distinguish unrelated existing failures without hiding them or expanding
the assignment into unrelated repairs. Never change expectations or a formal
baseline merely to make a failure disappear.

## Commit and push workflow

This section applies when committing is authorized. A formatting request alone
does not authorize a commit. Existing commit/push authorization persists across
routine fixes and validation reruns.

If unrelated Dart or Rust edits are present, run repository-wide formatting
and linting in an isolated checkout containing the task's changes and required
generated prerequisites. Preserve the original working files and do not copy
unrelated formatting changes back. This isolation does not waive the checks.
Inspect both the worktree and index before staging. If unrelated changes are
already staged, preserve those entries and use a scoped commit or isolated
index/checkout; a plain commit must not absorb them. Do not unstage the user's
work merely to simplify delivery, including when a file contains mixed changes.

1. Finish the scoped changes and relevant checks.
2. Run `./format.sh s` from the repository root and wait for completion.
   It runs Dart formatting, `cargo fmt --all`, and
   `cargo clippy --workspace --all-targets --all-features -- -D warnings`.
   It does not run clang-format. Use Git Bash on Windows.
3. Review the resulting diff; preserve unrelated work and stage only the
   intended files with explicit paths. Run `git diff --cached --check`.
4. Commit one logical change with the message format below.
5. When push is authorized, fetch the target remote, check divergence, handle
   related conflicts, push the intended branch, and verify the remote commit.
   Do not force-push or rewrite unrelated history without authorization.

Do not invoke bare `./format.sh`: its legacy default stages all changes and
auto-commits. After committing, compare remaining changes with the initial
worktree state; a user's unrelated edits may legitimately remain.

Commit messages use an English imperative subject, capitalized, at most
72 characters, without a final period. Include an English body explaining what
changed and why, wrapped at 72 characters. Include issue references when relevant.

## Maintaining instructions and documentation

- Write project instructions and documentation in English.
- Keep `.agents/skills/` as the single source of truth and synchronize its
  catalog when Skills change. Use concise, task-specific descriptions.
- Keep the Skill entrypoint focused. Put substantial conditional procedures
  in linked references and load them only when that mode is needed.
- Preserve dated experiment records as evidence, clearly separated from
  current requirements. Verify historical paths, defaults, and results before
  relying on them for current work.
- Update affected instructions when architecture, paths, or commands change.
  Do not create standalone Markdown files merely to summarize code changes or
  duplicate obvious code. Task-specific guides and Skill references should
  have an ongoing operational purpose.
