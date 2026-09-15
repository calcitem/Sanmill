# All-Locale ARB Batch Updates

Use this workflow only when the pre-edit gate selected all locales or the
user explicitly requested that scope. English/Chinese-only mode does not use
the batch script.

## Prepare the batch

1. Add or verify the requested English and Chinese messages first.
2. Discover the existing `intl_*.arb` files in
   `src/ui/flutter_app/lib/l10n/`; do not use a hard-coded language count.
3. Prepare real, context-appropriate translations for the remaining selected
   locales. Reuse nearby terminology for placing, moving, flying, mills,
   captures, and game pieces.
4. Create `new-items.txt` in that directory with sections beginning
   `// intl_<locale>.arb`, followed by JSON members at four-space indentation.
   Separate locale sections with a blank line. The last member in a section
   has no trailing comma. English and Chinese are already handled separately.
5. Preserve required metadata in each block, including placeholders and their
   types. Descriptions remain in English; empty metadata objects are allowed
   only when no metadata is needed.

## Apply safely

The existing `update_arb_files.sh` appends text. It does not detect duplicate
message keys, enforce locale scope, validate translations, or make the whole
batch transactional. Re-running the same batch can append duplicate entries.

Before invoking it, inspect the selected files and incoming blocks. Use only
existing locale basenames from the selected set, reject paths outside the
locale directory, and ensure each incoming key is genuinely missing in that
target. Handle updates to existing keys directly instead of appending them.
Preserve any pre-existing `new-items.txt` content rather than overwriting a
user's batch.

Prefer validating a copy of the selected files and the batch in a temporary
directory before applying a large batch to the working files. Keep original
translations recoverable. If a run fails partway, inspect the diff and repair
only affected entries; do not blindly rerun the append operation.

From the repository root:

```bash
(cd src/ui/flutter_app/lib/l10n && ./update_arb_files.sh)
```

Afterwards run the [JSON and message checks](validation.md), regenerate
localization, inspect the selected diff, and spot-check at least five
translated locales. Do not copy English placeholders to complete a batch.
