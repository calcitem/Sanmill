#!/usr/bin/env python3
"""
Script to check if ARB files match the template structure exactly.

This script validates:
1. Key order matches intl_en.arb
2. Metadata (@key) structure matches exactly
3. All fields in metadata are present and in correct order
4. Nested objects (like placeholders) match template structure
"""

import json
import os
from pathlib import Path
from typing import List, Dict, Any, Tuple, Optional
from collections import OrderedDict
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
            except Exception as e:
                print(f"Warning: Failed to parse {strings_file}: {e}")
                continue

    return None


def compare_structure(
    template_value: Any,
    file_value: Any,
    path: str = ""
) -> List[str]:
    """
    Recursively compare two values and return list of differences.

    Args:
        template_value: Value from template
        file_value: Value from file being checked
        path: Current path for error reporting

    Returns:
        List of difference messages
    """
    differences = []

    # Check if both are dictionaries
    if isinstance(template_value, dict) and isinstance(file_value, dict):
        template_keys = list(template_value.keys())
        file_keys = list(file_value.keys())

        # Check for missing keys
        missing_keys = set(template_keys) - set(file_keys)
        if missing_keys:
            differences.append(
                f"{path}: Missing keys: {', '.join(sorted(missing_keys))}"
            )

        # Check for extra keys
        extra_keys = set(file_keys) - set(template_keys)
        if extra_keys:
            differences.append(
                f"{path}: Extra keys: {', '.join(sorted(extra_keys))}"
            )

        # Check key order for common keys
        common_keys = [k for k in template_keys if k in file_keys]
        file_common_order = [k for k in file_keys if k in common_keys]

        if common_keys != file_common_order:
            differences.append(
                f"{path}: Key order mismatch. "
                f"Expected: {common_keys}, Got: {file_common_order}"
            )

        # Recursively check values for common keys
        for key in common_keys:
            new_path = f"{path}.{key}" if path else key
            differences.extend(
                compare_structure(template_value[key], file_value[key], new_path)
            )

    elif isinstance(template_value, list) and isinstance(file_value, list):
        # For lists, just check if they're equal
        # (ARB files don't typically have complex list structures to validate)
        if template_value != file_value:
            differences.append(f"{path}: List content mismatch")

    # For primitive values, we don't check them as they're language-specific
    # (translation strings, descriptions in target language, etc.)

    return differences


def check_entry_metadata(
    key: str,
    template_data: Dict[str, Any],
    file_data: Dict[str, Any],
    file_name: str
) -> List[str]:
    """
    Check if metadata for a key matches template structure.

    Args:
        key: The key to check (without @ prefix)
        template_data: Template ARB data
        file_data: File ARB data
        file_name: Name of file being checked

    Returns:
        List of issue messages
    """
    issues = []
    metadata_key = f"@{key}"

    # Skip @@locale as it's different for each file
    if key.startswith("@@"):
        return issues

    # Check if metadata exists in template
    if metadata_key not in template_data:
        return issues

    # Check if metadata exists in file
    if metadata_key not in file_data:
        issues.append(f"  ❌ {key}: Missing metadata entry '{metadata_key}'")
        return issues

    # Compare metadata structure
    template_metadata = template_data[metadata_key]
    file_metadata = file_data[metadata_key]

    differences = compare_structure(template_metadata, file_metadata, metadata_key)
    for diff in differences:
        issues.append(f"  ❌ {key}: {diff}")

    return issues


def check_arb_file(
    arb_file_path: Path,
    template_data: Dict[str, Any],
    template_keys: List[str],
    project_root: Path
) -> Tuple[bool, List[str]]:
    """
    Check if ARB file matches template structure.

    Args:
        arb_file_path: Path to ARB file to check
        template_data: Template ARB data
        template_keys: List of keys in template order
        project_root: Project root directory

    Returns:
        Tuple of (is_valid, list of issues)
    """
    file_data = load_arb_file(arb_file_path)
    file_keys = list(file_data.keys())
    issues = []

    # Extract expected locale from filename: intl_<locale>.arb
    # Preserves original casing (e.g., de_CH, zh_Hant) as required by Flutter
    expected_locale = arb_file_path.stem.replace('intl_', '')

    # Check if @@locale exists and matches filename
    if "@@locale" not in file_data:
        issues.append(f"  ❌ Missing @@locale key")
    else:
        actual_locale = file_data["@@locale"]
        if actual_locale != expected_locale:
            issues.append(
                f"  ❌ @@locale mismatch: expected '{expected_locale}' "
                f"(from filename) but got '{actual_locale}'"
            )

    # Check if appName matches Android strings.xml
    android_app_name = get_android_app_name(expected_locale, project_root)
    if android_app_name is not None:
        arb_app_name = file_data.get('appName')
        if arb_app_name != android_app_name:
            issues.append(
                f"  ❌ appName mismatch with Android strings.xml: "
                f"expected '{android_app_name}' but got '{arb_app_name}'"
            )
    # If no Android strings.xml found, we don't report it as an error
    # (some locales might not have Android resources)

    # Check for missing entries from template
    missing_entries = []
    for key in template_keys:
        # Skip @@locale and metadata keys
        if key == "@@locale" or key.startswith("@"):
            continue

        if key not in file_keys:
            missing_entries.append(key)

    if missing_entries:
        issues.append(f"  ❌ Missing {len(missing_entries)} entries from template:")
        for entry in missing_entries[:5]:  # Show first 5
            issues.append(f"      - {entry}")
        if len(missing_entries) > 5:
            issues.append(f"      ... and {len(missing_entries) - 5} more")

    # Check top-level key order
    common_keys = [key for key in template_keys if key in file_keys]
    file_common_order = [key for key in file_keys if key in common_keys]

    if common_keys != file_common_order:
        issues.append("  ❌ Top-level key order doesn't match template")

    # Check metadata for each key
    for key in file_keys:
        if not key.startswith("@"):
            key_issues = check_entry_metadata(key, template_data, file_data, arb_file_path.name)
            issues.extend(key_issues)

    return (len(issues) == 0, issues)


def check_arb_order(l10n_dir: Path, project_root: Path, reference_file: str = 'intl_en.arb') -> None:
    """
    Check if all ARB files match the template structure exactly.

    Args:
        l10n_dir: Directory containing ARB files
        project_root: Project root directory
        reference_file: Name of the reference ARB file
    """
    # Load reference file
    reference_path = l10n_dir / reference_file
    if not reference_path.exists():
        print(f"❌ Error: Reference file {reference_file} not found!")
        return

    template_data = load_arb_file(reference_path)
    template_keys = list(template_data.keys())

    print(f"📋 Template file: {reference_file}")
    print(f"📊 Total keys in template: {len(template_keys)}\n")

    # Find all ARB files
    arb_files = sorted(l10n_dir.glob('intl_*.arb'))

    files_with_issues = []
    files_checked = 0

    for arb_file in arb_files:
        if arb_file.name == reference_file:
            continue  # Skip reference file

        files_checked += 1
        is_valid, issues = check_arb_file(arb_file, template_data, template_keys, project_root)

        if is_valid:
            print(f"✅ {arb_file.name}: Perfect match with template")
        else:
            files_with_issues.append(arb_file.name)
            print(f"❌ {arb_file.name}: Issues found")
            for issue in issues:
                print(issue)
            print()

    # Summary
    print(f"{'='*60}")
    print(f"Summary:")
    print(f"  Total files checked: {files_checked}")
    print(f"  Files matching template: {files_checked - len(files_with_issues)}")
    print(f"  Files with issues: {len(files_with_issues)}")

    if files_with_issues:
        print(f"\n📝 Files that need fixing:")
        for filename in files_with_issues:
            print(f"  - {filename}")
    else:
        print(f"\n🎉 All files match the template perfectly!")


def main():
    """Main entry point"""
    # Get the l10n directory path
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    l10n_dir = project_root / 'src' / 'ui' / 'flutter_app' / 'lib' / 'l10n'

    if not l10n_dir.exists():
        print(f"❌ Error: l10n directory not found at {l10n_dir}")
        return

    check_arb_order(l10n_dir, project_root)


if __name__ == '__main__':
    main()
