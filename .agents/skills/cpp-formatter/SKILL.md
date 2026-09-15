---
name: cpp-formatter
description: Format or check changed C/C++ source files in Sanmill. Use for C/C++ formatting requests, not general Dart or Rust style checks.
---

# C++ Formatter

Format the requested C/C++ files using the repository's `.clang-format`.
Preserve the requested mode: a style check is read-only; a formatting request
may update the selected files.

## Scope

Current native sources include:

- `crates/perfect-db/csrc/`: the optional `cpp-oracle` reference code;
- `src/ui/flutter_app/windows/runner/` and `linux/`: platform Runner code;
- platform headers and other native files explicitly involved in the task.

The removed engine paths such as `src/position.cpp` are not current targets.
Do not recursively format generated files, bundled third-party code, or
unchanged oracle sources as part of a small edit.

## Commands

Run from the repository root with clang-format available:

```bash
# Check the selected file without modifying it.
clang-format --dry-run --Werror src/ui/flutter_app/windows/runner/main.cpp

# Format the selected file when edits are requested.
clang-format -i src/ui/flutter_app/windows/runner/main.cpp
```

For several files, pass their explicit, quoted paths. Preserve file boundaries
when deriving a list from Git; whitespace-splitting pipelines are not safe for
paths with spaces. Review the resulting diff for unrelated changes.

`format.sh` handles Dart and Rust, not C++. Follow the authorized commit
workflow in [AGENTS.md](../../../AGENTS.md) when a commit is requested; do not
invoke its bare auto-commit form for a formatting task.

If the formatter is unavailable, check installed toolchains before proposing
installation. Do not replace the project configuration or install system
packages merely to perform a read-only review.

Report the files checked or changed and any failures. Do not commit, push,
or contact teammates based on this Skill alone.
