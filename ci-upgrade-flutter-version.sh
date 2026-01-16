#!/bin/bash
set -e

# This script upgrades the Flutter version used in this project.
# It automatically detects the current Flutter version, finds all
# version references in the codebase, and updates them.

# --- Version Detection ---

# Get the new Flutter version from the local flutter command.
echo "Fetching current Flutter version from your environment..."
FLUTTER_VERSION=$(flutter --version | awk 'NR==1{print $2}')
if [ -z "$FLUTTER_VERSION" ]; then
    echo "Error: Could not determine Flutter version. Make sure 'flutter' is in your PATH."
    exit 1
fi
echo "Detected Flutter version: ${FLUTTER_VERSION}"

# Get the old Flutter version from the project's bootstrap script.
# This script is considered the source of truth for the project's required version.
echo "Fetching old Flutter version from scripts/ensure_flutter.sh..."
OLD_FLUTTER_VERSION=$(grep 'REQUIRED_FLUTTER_VERSION:=' scripts/ensure_flutter.sh | head -n1 | sed 's/.*:=//' | tr -d '}"')
if [ -z "$OLD_FLUTTER_VERSION" ]; then
    echo "Error: Could not determine the old Flutter version from scripts/ensure_flutter.sh."
    exit 1
fi
echo "Old project Flutter version: ${OLD_FLUTTER_VERSION}"

# Exit if the version is already up-to-date.
if [ "$FLUTTER_VERSION" == "$OLD_FLUTTER_VERSION" ]; then
    echo "Flutter version is already up to date. Nothing to do."
    exit 0
fi

# --- File Updates ---

# Export variables to be available in subshells created by find -exec.
export FLUTTER_VERSION
export OLD_FLUTTER_VERSION

# Determine the operating system to use the correct sed syntax for in-place editing.
OS="$(uname)"
SED_CMD='sed -i'
if [ "$OS" = "Darwin" ]; then
    SED_CMD='sed -i ""'
fi

# Update GitHub Actions workflow files.
echo "Updating Flutter version in .github/workflows..."
# The subshell is used to ensure the sed command gets the exported FLUTTER_VERSION.
find .github/workflows -name '*.yml' -exec sh -c "${SED_CMD} \"s/flutter-version: .*/flutter-version: '${FLUTTER_VERSION}'/\" \"\$1\"" sh {} \;

# Update snap package configuration.
echo "Updating Flutter version in snap/snapcraft.yaml..."
find snap -name '*.yaml' -exec sh -c "${SED_CMD} \"s/flutter_linux_${OLD_FLUTTER_VERSION}-stable/flutter_linux_${FLUTTER_VERSION}-stable/\" \"\$1\"" sh {} \;

# Update the Flutter version in project scripts and documentation.
echo "Updating version in scripts/ensure_flutter.sh and documentation..."
FILES_TO_UPDATE=(
  "scripts/ensure_flutter.sh"
  "README.md"
  "README-zh_CN.md"
)

for file in "${FILES_TO_UPDATE[@]}"; do
  if [ -f "$file" ]; then
    echo " - Updating ${file}"
    eval "$SED_CMD 's/${OLD_FLUTTER_VERSION}/${FLUTTER_VERSION}/g' '$file'"
  else
    echo " - Warning: ${file} not found, skipping."
  fi
done

# --- Verification ---

# Verify that all expected files were updated.
echo "Verifying version updates..."
VERIFICATION_FAILED=0

# Check key files contain the new version.
KEY_FILES=(
  "scripts/ensure_flutter.sh"
  "README.md"
  "README-zh_CN.md"
  "snap/snapcraft.yaml"
)

for file in "${KEY_FILES[@]}"; do
  if [ -f "$file" ]; then
    if grep -q "${OLD_FLUTTER_VERSION}" "$file"; then
      echo " - Warning: ${file} still contains old version ${OLD_FLUTTER_VERSION}"
      VERIFICATION_FAILED=1
    else
      echo " - ✓ ${file} updated successfully"
    fi
  fi
done

# Check GitHub Actions workflow files.
WORKFLOW_FILES_WITH_OLD_VERSION=$(grep -l "${OLD_FLUTTER_VERSION}" .github/workflows/*.yml 2>/dev/null || true)
if [ -n "$WORKFLOW_FILES_WITH_OLD_VERSION" ]; then
  echo " - Warning: Some workflow files still contain old version:"
  echo "$WORKFLOW_FILES_WITH_OLD_VERSION" | sed 's/^/   /'
  VERIFICATION_FAILED=1
else
  echo " - ✓ All workflow files updated successfully"
fi

if [ $VERIFICATION_FAILED -eq 1 ]; then
  echo ""
  echo "Warning: Some files may not have been updated correctly."
  echo "Please review the changes before committing."
  exit 1
fi

# --- Git Operations ---

# Stage all changes and commit them.
echo ""
echo "Staging and committing changes..."
git add .
git commit -m "ci: Upgrade Flutter to v${FLUTTER_VERSION}"

echo ""
echo "Successfully upgraded Flutter version from ${OLD_FLUTTER_VERSION} to ${FLUTTER_VERSION}."
echo "Please review the changes and push to the remote repository when ready."
# Uncomment the line below to automatically push the changes.
# git push
