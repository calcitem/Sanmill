# ARB Validation

Use these checks for the selected locale files when adding messages or
synchronizing translations. Commands start at the repository root in
Bash / Git Bash.

## Duplicate-aware JSON validation

The scope helper chooses locales by their last message keys. It does not
detect all duplicate keys or validate Flutter message semantics.
`python -m json.tool` alone is also insufficient for duplicate-key detection.

For example, validate the English and Chinese files with:

```bash
python - src/ui/flutter_app/lib/l10n/intl_en.arb src/ui/flutter_app/lib/l10n/intl_zh.arb <<'PY'
import json
import sys
from pathlib import Path

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result

for filename in sys.argv[1:]:
    path = Path(filename)
    data = json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=unique_object,
    )
    if not isinstance(data, dict):
        raise ValueError(f"{path}: expected a JSON object")
    print(f"{path}: valid JSON, no duplicate keys")
PY
```

In all-locale mode, pass the existing `intl_*.arb` files as the arguments
instead. The checker is read-only and fails on a duplicate at any object level.
It preserves the distinction between a message key and its `@key` metadata.

Inspect exact message membership and values after parsing. Do not use
`grep -c` as a completeness test: it counts matching lines, not JSON members,
and can match descriptions or unrelated keys.

## Message semantics and scope

- Check each requested key against the pre-edit state. Existing translations
  and metadata must survive unless their change was requested.
- Check placeholder names, types, plural/select branches, escaping, and
  formatting metadata against the English message. An absent optional
  `@key` is not by itself a duplicate or broken entry.
- Keep four-space indentation and append new messages without reordering
  unrelated entries.
- Compare the task's diff with the scope recorded before edits. Do not
  reinterpret tail alignment after the new keys have been appended.
- Generate localization code with
  `(cd src/ui/flutter_app && flutter gen-l10n)`. A JSON parse alone does not
  prove that ICU messages or their Dart accessors are valid.
- Verify affected UI text where applicable; report unverified locales rather
  than presenting spot checks as exhaustive linguistic review.
