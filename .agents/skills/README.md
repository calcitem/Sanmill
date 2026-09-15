# Sanmill Agent Skills

Project Skills live here and are selected by their name and description.
An explicit request can also invoke a Skill. Follow the user's task mode and
existing authorization; reading a Skill does not authorize unrelated changes.

## Catalog

| Skill directory / name | Use when |
| --- | --- |
| [arb-translation-updater](arb-translation-updater/SKILL.md) | Adding ARB message keys or synchronizing translations; applies the en/de/hu/zh tail gate |
| [cpp-formatter](cpp-formatter/SKILL.md) | Formatting or checking changed C/C++ files in this repository |
| [engine-performance-audit](engine-performance-audit/SKILL.md) | Diagnosing engine performance regressions or deterministic H2H anomalies |
| [flutter-test-runner](flutter-test-runner/SKILL.md) | Selecting, running, or diagnosing Sanmill Flutter tests or coverage |
| [game-rule-validator](game-rule-validator/SKILL.md) | Adding a Mill variant, changing mechanics or option structure, or reviewing those changes |
| [refactor-parity-audit](refactor-parity-audit/SKILL.md) | Comparing behavior against an identified implementation or revision during a port or refactor |

Descriptions identify the workflow, not every file type that might participate.
A generic test request does not imply Flutter; a wording-only rule or locale
change does not require a full rule audit or translation synchronization.

## Maintenance

Use lowercase hyphenated names matching the directory and YAML frontmatter
with `name` and `description`. Keep simple Skills self-contained. Larger
Skills link conditional procedures from `references/`; do not load every
reference when a single mode is sufficient.

Project-wide safety, validation, generated-code, and commit requirements live
in [AGENTS.md](../../AGENTS.md). Reference those requirements instead of
copying a second policy into every Skill. Translation scope is defined once in
the translation Skill.

Keep dated experiments as explicitly historical evidence, not current tasks
or acceptance rules. Update affected references and this catalog when paths,
commands, or architecture change. Do not maintain another copy of the Skills
under a tool-specific directory.
