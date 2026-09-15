---
name: arb-translation-updater
description: Add Flutter ARB message keys or synchronize Sanmill translations using the four-locale tail gate. Do not use for isolated wording-only edits.
---

# ARB Translation Updater

Add message keys and genuine translations within the selected locale scope.
English is the semantic source; Chinese is the required second base
translation. Reuse established Mill terminology.

## Choose scope before adding keys

From the repository root, run:

```bash
python .agents/skills/arb-translation-updater/scripts/check_arb_tail_alignment.py
```

The script reads the final top-level message key in `intl_en.arb`,
`intl_de.arb`, `intl_hu.arb`, and `intl_zh.arb`. Keys beginning with
`@`, including metadata and `@@locale`, do not count.

An explicit locale scope from the user controls that task. Otherwise apply
the reported default:

- `tail_alignment=mismatched`: append each new message only to
  `intl_en.arb` and `intl_zh.arb`. Do not create `new-items.txt`, run the
  batch updater, or edit other locales.
- `tail_alignment=aligned`: synchronize each new message to every existing
  `intl_*.arb` file.

Record the result before editing. Do not rerun the gate after adding keys to
widen the same task. Tail equality chooses the update scope; it is not proof
that all translations or all earlier keys are complete.

For a task that only changes existing wording, preserve its requested locale
scope; do not add unrelated keys or initiate a full synchronization.

## Required content and data preservation

- Append new message entries at the end of each selected ARB, before the final
  closing brace. Use four-space indentation.
- Provide actual target-language translations. Do not fill missing locales
  with English placeholder prose to claim synchronization is complete.
  Preserve proper names, notation, and placeholders as required by meaning.
- Keep metadata descriptions in English as a project convention. Preserve
  required placeholder names, types, and formatting metadata. Use `{}` only
  when the entry needs no metadata; never blanket-clear `@key` objects.
- Check exact JSON keys before adding entries. Text occurrence counts do not
  detect duplicate JSON keys reliably. Missing optional metadata is not a
  duplicate message.
- If duplicates are found, compare their actual values and metadata, preserve
  valid translations, and repair only the affected entries. Do not delete all
  text matches and rebuild from guesses.
- Work from the task's keys and current diff. Do not infer the requested keys
  from the latest unrelated commit or broaden the diff to pre-existing edits.

## Apply and validate

For a small update, edit the selected entries directly. For all-locale batches,
read [Batch updates](references/batch-updates.md) before using the existing
append script. Read [Validation](references/validation.md) for exact-key and
duplicate-aware JSON checks; the tail helper alone is not that validation.

After editing:

1. Validate selected files as JSON with duplicate-key detection and verify
   the intended messages and required metadata.
2. Compare the task's changed files with the recorded locale scope. Preserve
   unrelated user changes; do not revert another locale merely because it
   already had changes before this task.
3. Run `flutter gen-l10n` from `src/ui/flutter_app`.
4. Check affected messages for rendering, overflow, placeholder/plural
   behavior, and RTL layout where relevant. In all-locale mode, spot-check
   at least five translated locales and report any remaining quality limits.

Continue authorized corrections without repeatedly requesting permission.
If genuine translations or required validation cannot be completed, state the
specific remaining work; do not substitute English placeholders or claim
completion. Follow [AGENTS.md](../../../AGENTS.md) for implementation checks
and the authorized commit workflow.
