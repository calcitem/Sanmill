---
name: "arb-translation-updater"
description: "Update Flutter ARB translations after checking the final message keys in English, German, Hungarian, and Chinese; use when adding new i18n strings, limiting changes to English and Chinese when those reference tails differ and otherwise synchronizing all locales by default."
---

# ARB Translation Updater

## Purpose

This skill adds new ARB (Application Resource Bundle) entries with a scope chosen from the current synchronization state. It first compares the final message keys in English, German, Hungarian, and Chinese. If those keys differ, it updates only English and Chinese; if they match, it updates all locales unless the user explicitly requests another scope.

## Use Cases

- Add new translation keys to English and Chinese while locale tails are not synchronized
- Batch update all language files once the reference locale tails are synchronized
- Batch translate new UI strings for the Flutter app
- Avoid widening an existing locale synchronization gap

## **CRITICAL RULES** ⚠️

### Rule 1: Check Reference Tail Alignment Before Editing

**ALWAYS run the tail-alignment check before adding a new key. Do not infer
alignment from a git diff or from only English and Chinese.**

From the repository root, run:

```bash
python .agents/skills/arb-translation-updater/scripts/check_arb_tail_alignment.py
```

The script parses `intl_en.arb`, `intl_de.arb`, `intl_hu.arb`, and
`intl_zh.arb` in file order. For each file, it selects the last top-level key
that does not start with `@`; metadata keys such as `@messageKey` and ARB
attributes such as `@@locale` do not count as localization strings.

Use the reported result as a scope gate:

- `tail_alignment=mismatched`: The locale set is not currently unified. Add
  each new string only to the ends of `intl_en.arb` and `intl_zh.arb`. Do not
  create `new-items.txt`, run the batch updater, or modify any other ARB file.
- `tail_alignment=aligned`: Unless the user explicitly requests a different
  scope, follow the full synchronization workflow and add each new string to
  every `intl_*.arb` file.

Apply the gate before any edits so the newly added keys cannot change the
decision.

### Rule 2: New Strings MUST Be Added at the END of ARB Files

**ALWAYS add new translation entries at the very end of each ARB file, just before the closing `}`.**

- ✅ CORRECT: Add entries after the last existing entry in the file
- ❌ WRONG: Insert entries in the middle of the file
- This applies to BOTH manual additions (to `intl_en.arb` and `intl_zh.arb`) AND automated additions via the update script

**Example:**
```json
{
  "existingKey1": "...",
  "@existingKey1": {},
  "existingKey2": "...",
  "@existingKey2": {},
  // Add new entries HERE ↓
  "newKey": "...",
  "@newKey": {}
}
```

### Rule 3: Keep Metadata Descriptions in English

**When ARB metadata includes descriptions, write them in English in every
locale. Preserve required placeholder metadata; use an empty object only when
the entry does not need metadata.**

- ✅ CORRECT: `"@perfectDatabaseChallengeHint": {"description": "Hint to enable perfect database for greater challenge", ...}`
- ❌ WRONG: `"@perfectDatabaseChallengeHint": {"description": "启用完美数据库以获得更大挑战的提示", ...}` (in `intl_zh.arb`)

This applies to:
- The `description` field in `@key` metadata
- Placeholder descriptions within metadata
- ALL language files: `intl_en.arb`, `intl_zh.arb`, `intl_ja.arb`, etc.

**Rationale:** Flutter's ARB format specification requires metadata to be in English for tooling compatibility and consistency across all locales.

### Rule 4: ALWAYS Check for Existing Entries Before Adding

**Before adding new translations, ALWAYS check if the key already exists in the ARB files.**

**Check before adding:**
```bash
# Check if key exists in a specific file
grep -c "keyName" intl_en.arb

# Check all files
for file in intl_*.arb; do
  count=$(grep -c "keyName" "$file")
  echo "$file: $count occurrences"
done
```

**Decision matrix:**
- **If count = 0 (no occurrences)**: ✅ Add the new entry
- **If count = 2 (one complete entry: key + metadata)**: ⚠️ Entry already complete, DO NOT add again
- **If count = 1 or count > 2**: ❌ Incomplete or duplicate entry - fix before proceeding

**If duplicates exist:**
1. Remove ALL occurrences of the duplicate key
2. Re-add only ONE complete entry (key + metadata) at the END of the file
3. Validate JSON format after fixing

**Prevention:**
- Always use version control to check what was actually added
- Don't assume keys need to be added just because the task mentions them
- Verify the current state of ARB files before running update scripts

### Rule 5: MUST Use 4-Space Indentation

**ALL ARB files MUST use 4-space indentation, NOT 2-space or tabs.**

**Indentation levels:**
- Top-level keys: 4 spaces
- Metadata object first level: 8 spaces (4+4)
- Placeholders object: 8 spaces
- Placeholder keys: 12 spaces (4+4+4)
- Placeholder properties: 16 spaces (4+4+4+4)

**Example with correct 4-space indentation:**
```json
{
    "myKey": "My value",
    "@myKey": {
        "description": "My description",
        "placeholders": {
            "param": {
                "description": "Parameter description",
                "type": "String"
            }
        }
    }
}
```

**❌ WRONG (2-space indentation):**
```json
{
  "myKey": "My value",
  "@myKey": {
    "description": "My description",
    "placeholders": {
      "param": {
        "description": "Parameter description",
        "type": "String"
      }
    }
  }
}
```

**Important:**
- When creating `new-items.txt`, use 4-space indentation
- The `update_arb_files.sh` script will copy indentation exactly as written
- Always verify indentation after running the update script

## Workflow Overview

```
1. Check the final message keys in intl_en/de/hu/zh.arb
2. Choose the update scope before editing:
   - mismatched tails: English and Chinese only
   - aligned tails: all locales by default
3. Use git to identify or verify the new English and Chinese entries
4. In all-locale mode, generate translations and run update_arb_files.sh
5. Validate JSON and verify that only the selected scope changed
```

## Step-by-Step Process

### Step 1: Check Tail Alignment and Lock the Scope

Run the preflight from the repository root:

```bash
python .agents/skills/arb-translation-updater/scripts/check_arb_tail_alignment.py
```

Record `default_scope` before editing:

- For `default_scope=en,zh`, append the new message and its metadata only to
  `intl_en.arb` and `intl_zh.arb`, then skip directly to validation.
- For `default_scope=all-locales`, use the existing batch translation flow
  unless the user explicitly requested another scope.

Do not re-run the check after adding the new keys to decide whether to widen
the same update.

### Step 2: Identify New Entries Using Git

**Use git to see what was recently added** (most reliable method):

```bash
cd src/ui/flutter_app/lib/l10n

# Check recent changes to English ARB file
git log -p --follow -1 intl_en.arb

# Or see diff from last commit
git diff HEAD~1 intl_en.arb

# See what was added (lines starting with +)
git diff HEAD~1 intl_en.arb | grep "^+"

# Check if Chinese file also has new entries
git diff HEAD~1 intl_zh.arb

# If no recent changes in git, check uncommitted changes
git diff intl_en.arb
git diff intl_zh.arb
```

**Extract the new keys:**
- Look for newly added key-value pairs
- Note both the key and its metadata (lines starting with `@`)
- Each translation typically has 2 lines: `"key": "value"` and `"@key": {}`
- Preserve any required descriptions and placeholder metadata. Descriptions
  must remain in English.

**Priority:**
1. Add or verify the new entry in both `intl_en.arb` and `intl_zh.arb`.
2. Use English as the primary semantic source and Chinese as a secondary
   translation reference.
3. Widen the update to other locales only when Step 1 selected all-locale
   mode.

### Step 3: Determine Which Languages Need Updates

Run this step only in all-locale mode.

Check if the new keys exist in other language files:

```bash
# Check if a specific key exists in all files
grep -l "newKeyName" intl_*.arb

# Count how many files already have the key
grep -l "newKeyName" intl_*.arb | wc -l

# Find which files are missing the key
for file in intl_*.arb; do
  if ! grep -q "newKeyName" "$file"; then
    echo "Missing in: $file"
  fi
done
```

### Step 4: Generate Translations for All Languages

Run this step only in all-locale mode.

Create translations for all required languages. Each ARB file needs:
- Translation appropriate to the language
- NOT just English text copied across
- Context-aware for the Mill game domain

**Supported Languages (59+ total excluding en and zh):**
- European: de, de_ch, fr, es, it, pt, ru, pl, nl, sv, da, fi, nb, cs, sk, hu, ro, bg, hr, sr, sl, el, et, lv, lt, is, be, uk, mk, bs, sq, ca
- Asian: ja, ko, zh_Hant, hi, bn, ta, te, kn, gu, th, vi, id, ms, km, my, si, bo
- Middle Eastern: ar, fa, he, ur, hy, az, uz, tr
- African: am, sw, zu, af

### Step 5: Create new-items.txt

Run this step only in all-locale mode.

The `update_arb_files.sh` script reads from `new-items.txt` with this format:

```txt
// intl_<locale>.arb
  "keyName": "Translated text",
  "@keyName": {},
  "keyNameDetail": "Detailed translated text",
  "@keyNameDetail": {}

// intl_<another_locale>.arb
  "keyName": "其他语言的翻译",
  "@keyName": {},
  ...
```

**Format Rules:**
- Comment line: `// intl_<locale>.arb` (indicates which file to update)
- Entries: JSON key-value pairs with proper indentation (4 spaces)
- Blank line between different locale sections
- No trailing comma on last entry in each section
- **Do NOT include intl_en.arb or intl_zh.arb** in new-items.txt (these are already updated)
- **CRITICAL**: All `@key` metadata must be empty objects `{}` - NEVER include `description` or any other fields

**Example new-items.txt:**

```txt
// intl_ja.arb
    "stopPlacing": "配置を停止",
    "@stopPlacing": {},
    "stopPlacing_Detail": "ボード上に空きスペースが2つだけ残ったときに配置フェーズが終了します。",
    "@stopPlacing_Detail": {}

// intl_fr.arb
    "stopPlacing": "Arrêter le placement",
    "@stopPlacing": {},
    "stopPlacing_Detail": "La phase de placement se termine lorsque le plateau n'a plus que 2 espaces vides.",
    "@stopPlacing_Detail": {}

// intl_de.arb
    "stopPlacing": "Setzen beenden",
    "@stopPlacing": {},
    "stopPlacing_Detail": "Die Setzphase endet, wenn das Brett nur noch 2 freie Felder hat.",
    "@stopPlacing_Detail": {}
```

### Step 6: Run Update Script

Run this step only in all-locale mode.

Execute the update script to apply all translations:

```bash
cd src/ui/flutter_app/lib/l10n

# Run the update script
./update_arb_files.sh

# The script will:
# - Read new-items.txt
# - Parse each locale section
# - Append entries to corresponding .arb files
# - Maintain proper JSON formatting
```

### Step 7: Validate Results

Verify that all files were updated correctly:

```bash
# Validate JSON format of all files
for file in intl_*.arb; do
  if ! python3 -m json.tool "$file" > /dev/null 2>&1; then
    echo "❌ JSON Error in $file"
  fi
done
echo "✅ JSON validation complete"

# Verify which ARB files changed
git diff --name-only -- intl_*.arb
```

For `default_scope=en,zh`, the changed ARB list must contain only
`intl_en.arb` and `intl_zh.arb`, and the new key must appear in both.

For `default_scope=all-locales`, compare the key count with the ARB file
count:

```bash
grep -l "stopPlacing" intl_*.arb | wc -l
ls -1 intl_*.arb | wc -l

# Spot check several translated locales
tail -6 intl_ja.arb   # Japanese
tail -6 intl_fr.arb   # French
tail -6 intl_ru.arb   # Russian
tail -6 intl_ar.arb   # Arabic
```

## Available Scripts

### update_arb_files.sh

**Location:** `src/ui/flutter_app/lib/l10n/update_arb_files.sh`

**What it does:**
- Reads `new-items.txt` from the same directory
- Parses locale-specific sections (marked with `// intl_<locale>.arb`)
- Appends new entries to corresponding ARB files
- Maintains proper JSON structure (removes trailing commas, adds closing braces)

**How it works:**
1. Detects comment lines with ARB filenames
2. Accumulates translation entries for each locale
3. Removes last `}` from target file
4. Appends new entries
5. Adds closing `}` back

### Other Helper Scripts

```bash
# append.sh - Appends content from append.txt to specified ARB file
./append.sh <arb_file>

# append-items.sh - Calls append.sh for all ARB files
./append-items.sh

# replace-locale.sh - Replace locale identifiers
./replace-locale.sh
```

## Translation Quality Guidelines

### Context Matters

When translating Mill game terms, consider:
- **Placing phase** - Initial piece placement on board
- **Moving phase** - Moving pieces already on board
- **Flying** - Special move when player has few pieces left
- **Mill** - Three pieces in a row
- **Pieces** - Game tokens (not chess pieces)

### Translation Source Priority

1. **Primary source**: English (`intl_en.arb`)
2. **Secondary reference**: Chinese (`intl_zh.arb`) - if available and recently updated
3. **Existing translations**: Check similar keys in the same file for consistency

### Language-Specific Considerations

**Right-to-Left Languages (ar, he, fa, ur):**
- Ensure proper RTL text direction
- Numbers and punctuation may need special handling

**Asian Languages (zh, ja, ko, th, vi):**
- May not need plural forms
- Consider formal vs informal register

**European Languages:**
- Watch for gender agreement (de, fr, es, it)
- Plural forms vary by language

## Best Practices

1. Run the tail check before edits and retain its selected scope.
2. Treat English as the primary semantic source and Chinese as the required
   secondary base translation.
3. Reuse established Mill terminology from nearby keys.
4. Review machine translations for context and cultural appropriateness.
5. Test changed locales for rendering, overflow, and localization generation.

## Verification Checklist

After running the update process:

- [ ] Ran the en/de/hu/zh tail check before editing
- [ ] Preserved the selected en/zh-only or all-locale scope
- [ ] Used git to identify what was actually added
- [ ] All required ARB files contain the new keys
- [ ] All JSON files validate successfully
- [ ] In all-locale mode, translations are not English placeholders
- [ ] In all-locale mode, spot-checked 5+ languages for quality
- [ ] No trailing commas or syntax errors
- [ ] Flutter app builds without i18n errors
- [ ] UI displays correctly in different locales

## Example: Complete Workflow

```bash
# 1. From the repository root, decide scope before editing
python .agents/skills/arb-translation-updater/scripts/check_arb_tail_alignment.py

# 2. Append the new entry to both base files
# src/ui/flutter_app/lib/l10n/intl_en.arb
# src/ui/flutter_app/lib/l10n/intl_zh.arb

# 3a. If default_scope=en,zh, do not touch another ARB file
git diff --name-only -- src/ui/flutter_app/lib/l10n/intl_*.arb

# 3b. If default_scope=all-locales, create new-items.txt and batch update
cd src/ui/flutter_app/lib/l10n
./update_arb_files.sh

# 4. Validate JSON and the selected scope
for file in intl_*.arb; do
  python3 -m json.tool "$file" > /dev/null 2>&1 || echo "Error: $file"
done
```

## Reference Resources

- **ARB Format Spec**: https://github.com/google/app-resource-bundle
- **Flutter i18n Guide**: https://docs.flutter.dev/development/accessibility-and-localization/internationalization
- **Mill Game Terminology**: Refer to existing translations in intl_en.arb
- **Update Script**: `src/ui/flutter_app/lib/l10n/update_arb_files.sh`
- **Git Workflow**: Use `git diff` to identify new entries reliably
