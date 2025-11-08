#!/usr/bin/env python3
"""
Script to normalize ARB files to match the template structure exactly.

This script:
1. Reorders all keys to match intl_en.arb
2. Syncs metadata (@key) structure with template
3. Copies missing metadata fields from template
4. Preserves correct field order in metadata
5. Handles nested objects (like placeholders) recursively
6. Keeps translated strings intact
"""

import json
import os
from pathlib import Path
from typing import Dict, Any, List, Optional
from collections import OrderedDict
import copy
import xml.etree.ElementTree as ET


def load_arb_file(file_path: Path) -> Dict[str, Any]:
    """
    Load ARB file and preserve key order.

    Args:
        file_path: Path to the ARB file

    Returns:
        Dictionary with preserved key order
    """
    with open(file_path, 'r', encoding='utf-8') as f:
        return json.load(f, object_pairs_hook=OrderedDict)


def save_arb_file(file_path: Path, data: Dict[str, Any]) -> None:
    """
    Save ARB file with proper formatting (4-space indentation).

    Args:
        file_path: Path to save the ARB file
        data: ARB data to save
    """
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
        # Add newline at end of file
        f.write('\n')


def get_android_app_name(locale: str, project_root: Path) -> Optional[str]:
    """
    Get app name from Android strings.xml for given locale.

    Tries multiple strategies to find the correct values directory:
    1. Direct match: values-{locale}
    2. Region code format: values-{locale with _ replaced by -r}
    3. Base language: values-{first part before _}
    4. Special mappings (e.g., nb -> nn)

    Args:
        locale: Locale string (e.g., 'zh', 'zh_Hant', 'de_ch')
        project_root: Project root directory

    Returns:
        App name string from strings.xml, or None if not found
    """
    res_dir = project_root / 'src' / 'ui' / 'flutter_app' / 'android' / 'app' / 'src' / 'main' / 'res'

    # Special locale mappings
    special_mappings = {
        'nb': 'nn',  # Norwegian Bokmål -> Norwegian Nynorsk
    }

    # Build list of possible values directory names to try
    possible_dirs = []

    # 1. Try direct match
    possible_dirs.append(f'values-{locale}')

    # 2. Try region code format (e.g., zh_Hant -> zh-rHant)
    if '_' in locale:
        locale_with_region = locale.replace('_', '-r')
        possible_dirs.append(f'values-{locale_with_region}')

    # 3. Try base language (e.g., zh_Hant -> zh, de_ch -> de)
    if '_' in locale:
        base_lang = locale.split('_')[0]
        possible_dirs.append(f'values-{base_lang}')

    # 4. Try special mappings
    if locale in special_mappings:
        mapped_locale = special_mappings[locale]
        possible_dirs.append(f'values-{mapped_locale}')

    # Try each possible directory
    for dir_name in possible_dirs:
        strings_file = res_dir / dir_name / 'strings.xml'
        if strings_file.exists():
            try:
                tree = ET.parse(strings_file)
                root = tree.getroot()
                # Find <string name="app_name">...</string>
                for string_elem in root.findall('string'):
                    if string_elem.get('name') == 'app_name':
                        return string_elem.text
            except Exception:
                # Silently skip parsing errors
                continue

    return None


def merge_metadata_structure(
    template_value: Any,
    file_value: Any,
    is_translatable: bool = False
) -> Any:
    """
    Recursively merge file value with template structure.

    This function ensures the result has:
    - Same structure and keys as template
    - Same order of keys as template
    - Values from file where they exist and are translatable
    - Values from template for structural/non-translatable fields

    Args:
        template_value: Value from template
        file_value: Value from file being normalized
        is_translatable: Whether this field contains translatable content

    Returns:
        Merged value with template structure and file translations
    """
    # If template is a dict, merge structures
    if isinstance(template_value, dict):
        result = OrderedDict()

        # Iterate through template keys in order
        for key in template_value.keys():
            template_sub = template_value[key]

            # Check if this field is translatable
            # Description fields in target language should be kept from file
            is_desc_field = (key == "description")

            if key in file_value:
                # Key exists in file, merge recursively
                result[key] = merge_metadata_structure(
                    template_sub,
                    file_value[key],
                    is_translatable=is_desc_field
                )
            else:
                # Key missing in file, copy from template
                result[key] = copy.deepcopy(template_sub)

        return result

    # If template is a list, prefer file value if exists, else use template
    elif isinstance(template_value, list):
        if isinstance(file_value, list):
            return file_value
        return copy.deepcopy(template_value)

    # For primitive values
    else:
        # If this is a translatable field and file has a value, use it
        # Otherwise, use template value (for type, example, etc.)
        if is_translatable and file_value is not None:
            return file_value
        return template_value


def normalize_entry_metadata(
    key: str,
    template_data: Dict[str, Any],
    file_data: Dict[str, Any]
) -> Any:
    """
    Normalize metadata for a single entry to match template structure.

    Args:
        key: The key (without @ prefix)
        template_data: Template ARB data
        file_data: File ARB data

    Returns:
        Normalized metadata value
    """
    metadata_key = f"@{key}"

    # Skip @@locale as it's different for each file
    if key.startswith("@@"):
        return file_data.get(metadata_key)

    # If no metadata in template, keep file's metadata
    if metadata_key not in template_data:
        return file_data.get(metadata_key)

    template_metadata = template_data[metadata_key]

    # If no metadata in file, copy from template
    if metadata_key not in file_data:
        return copy.deepcopy(template_metadata)

    file_metadata = file_data[metadata_key]

    # Merge structures
    return merge_metadata_structure(template_metadata, file_metadata)


def normalize_bcp47_locale(locale: str) -> str:
    """
    Normalize locale code to follow BCP47 case conventions.

    BCP47 format rules:
    - Language subtag: lowercase (e.g., 'de', 'zh')
    - Script subtag: Title case (e.g., 'Hant', 'Latn')
    - Region subtag: UPPERCASE (e.g., 'CH', 'CN', 'US')

    Args:
        locale: Locale string to normalize (e.g., 'de_ch', 'zh_hant')

    Returns:
        Normalized locale string (e.g., 'de_CH', 'zh_Hant')
    """
    parts = locale.split('_')

    # Language code (first part) must be lowercase
    if len(parts) >= 1:
        parts[0] = parts[0].lower()

    # For locales with region or script codes
    if len(parts) == 2:
        second_part = parts[1]

        # Check if it's a region code (2 letters) or script code (4 letters)
        if len(second_part) == 2:
            # This is a region code, make UPPERCASE
            parts[1] = second_part.upper()
        elif len(second_part) == 4:
            # This is a script code, make Title case
            parts[1] = second_part.capitalize()

    return '_'.join(parts)


def normalize_arb_file(
    arb_file_path: Path,
    template_data: Dict[str, Any],
    template_keys: List[str],
    project_root: Path,
    dry_run: bool = False
) -> bool:
    """
    Normalize an ARB file to match template structure exactly.

    Args:
        arb_file_path: Path to the ARB file to normalize
        template_data: Template ARB data
        template_keys: List of keys in template order
        project_root: Project root directory
        dry_run: If True, don't write changes to disk

    Returns:
        True if file was modified, False otherwise
    """
    # Load the ARB file
    file_data = load_arb_file(arb_file_path)
    original_json = json.dumps(file_data, ensure_ascii=False, indent=4)

    # Extract locale from filename: intl_<locale>.arb
    locale = arb_file_path.stem.replace('intl_', '')

    # Normalize locale to BCP47 format
    locale = normalize_bcp47_locale(locale)

    # Get app name from Android strings.xml if available
    android_app_name = get_android_app_name(locale, project_root)

    # Create a new ordered dictionary with template structure
    normalized_data = OrderedDict()

    # First, add all keys from template in correct order
    for key in template_keys:
        if key.startswith("@") and not key.startswith("@@"):
            # This is metadata for an entry, skip (will be added with its entry)
            continue

        if key == "@@locale":
            # Always use filename-derived locale to ensure consistency
            normalized_data[key] = locale
        elif key == "appName" and android_app_name is not None:
            # Sync appName from Android strings.xml
            normalized_data[key] = android_app_name

            # Add normalized metadata
            metadata_key = f"@{key}"
            if metadata_key in template_data or metadata_key in file_data:
                normalized_data[metadata_key] = normalize_entry_metadata(
                    key, template_data, file_data
                )
        elif key in file_data:
            # Entry exists in file, keep translated value
            normalized_data[key] = file_data[key]

            # Add normalized metadata
            metadata_key = f"@{key}"
            if metadata_key in template_data or metadata_key in file_data:
                normalized_data[metadata_key] = normalize_entry_metadata(
                    key, template_data, file_data
                )
        else:
            # Entry missing in file, copy from template (as placeholder)
            normalized_data[key] = template_data.get(key)

            # Add metadata from template
            metadata_key = f"@{key}"
            if metadata_key in template_data:
                normalized_data[metadata_key] = copy.deepcopy(template_data[metadata_key])

    # Then add any keys that exist in file but not in template
    # (append them at the end to avoid losing data)
    for key in file_data.keys():
        if key not in normalized_data:
            normalized_data[key] = file_data[key]

    # Check if anything changed
    normalized_json = json.dumps(normalized_data, ensure_ascii=False, indent=4)
    changed = (original_json != normalized_json)

    if changed and not dry_run:
        # Save the normalized file
        save_arb_file(arb_file_path, normalized_data)
        print(f"✅ Normalized: {arb_file_path.name}")
    elif not changed:
        print(f"⏭️  No change needed: {arb_file_path.name}")
    else:
        print(f"🔍 Would normalize: {arb_file_path.name}")

    return changed


def normalize_all_arb_files(
    l10n_dir: Path,
    project_root: Path,
    reference_file: str = 'intl_en.arb',
    dry_run: bool = False
) -> None:
    """
    Normalize all ARB files to match template structure exactly.

    Args:
        l10n_dir: Directory containing ARB files
        project_root: Project root directory
        reference_file: Name of the reference ARB file
        dry_run: If True, don't write changes to disk
    """
    # Load reference file
    reference_path = l10n_dir / reference_file
    if not reference_path.exists():
        print(f"❌ Error: Reference file {reference_file} not found!")
        return

    template_data = load_arb_file(reference_path)
    template_keys = list(template_data.keys())

    print(f"📋 Template file: {reference_file}")
    print(f"📊 Total keys in template: {len(template_keys)}")
    if dry_run:
        print(f"🔍 DRY RUN MODE - No files will be modified\n")
    else:
        print(f"✏️  WRITE MODE - Files will be modified\n")

    # Find all ARB files
    arb_files = sorted(l10n_dir.glob('intl_*.arb'))

    files_modified = 0
    files_unchanged = 0
    files_processed = 0

    for arb_file in arb_files:
        if arb_file.name == reference_file:
            print(f"⏭️  Skipping template file: {arb_file.name}")
            continue  # Skip template file

        files_processed += 1
        changed = normalize_arb_file(arb_file, template_data, template_keys, project_root, dry_run)

        if changed:
            files_modified += 1
        else:
            files_unchanged += 1

    # Summary
    print(f"\n{'='*60}")
    print(f"Summary:")
    print(f"  Total files processed: {files_processed}")
    print(f"  Files modified: {files_modified}")
    print(f"  Files unchanged: {files_unchanged}")

    if dry_run and files_modified > 0:
        print(f"\n💡 This was a dry run. Run without --dry-run to apply changes.")
    elif files_modified > 0:
        print(f"\n✨ Successfully normalized {files_modified} file(s)!")
    else:
        print(f"\n🎉 All files already match the template perfectly!")


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(
        description='Normalize ARB files to match intl_en.arb structure exactly'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Preview changes without modifying files'
    )

    args = parser.parse_args()

    # Get the l10n directory path
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    l10n_dir = project_root / 'src' / 'ui' / 'flutter_app' / 'lib' / 'l10n'

    if not l10n_dir.exists():
        print(f"❌ Error: l10n directory not found at {l10n_dir}")
        return

    normalize_all_arb_files(l10n_dir, project_root, dry_run=args.dry_run)


if __name__ == '__main__':
    main()
