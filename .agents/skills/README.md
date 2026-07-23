# Sanmill Agent Skills

Project-level Skills for Codex live in this directory. Each Skill packages a
focused repository workflow in a `SKILL.md` file and is selected from its YAML
frontmatter when a task matches its description.

## Available Skills

| Directory | Skill | Purpose |
| --- | --- | --- |
| `arb-translation-updater/` | ARB Translation Updater | Choose en/zh-only or all-locale ARB updates from en/de/hu/zh tail alignment. |
| `cpp-formatter/` | C++ Code Formatter | Format or check the remaining C++ code with the repository conventions. |
| `engine-performance-audit/` | engine-performance-audit | Find Rust/TGF engine performance regressions and hotspots. |
| `flutter-test-runner/` | Flutter Test Runner | Run Sanmill unit, widget, and integration tests. |
| `game-rule-validator/` | New Rule Completeness Validator | Check that a new game rule or variant updates every required layer. |
| `refactor-parity-audit/` | refactor-parity-audit | Audit Rust/TGF refactors and ports against a reference implementation. |

Codex selects a matching Skill automatically. A request can also name a Skill
explicitly when that workflow must be used.

## Creating or Updating a Skill

Use the following layout:

```text
.agents/skills/my-skill/
└── SKILL.md
```

Every `SKILL.md` starts with YAML frontmatter:

```markdown
---
name: "Skill Name"
description: "What the Skill does and when Codex should use it."
---
```

Keep each Skill focused on one workflow. Prefer repository commands and
authoritative project documentation over copied explanations. When paths,
commands, or architecture change, update the affected Skill in the same
change and keep the catalog above synchronized.

`.agents/skills/` is the canonical location. Do not maintain a second copy in
a tool-specific directory.
