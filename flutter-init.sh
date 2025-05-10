#!/bin/bash

# Navigate to the Flutter app directory
cd src/ui/flutter_app || exit

# Paths for generated files
GEN_FILE_PATH=lib/generated
FLUTTER_VERSION_FILE=$GEN_FILE_PATH/flutter_version.dart
GIT_INFO_PATH=assets/files
GIT_BRANCH_FILE=$GIT_INFO_PATH/git-branch.txt
GIT_REVISION_FILE=$GIT_INFO_PATH/git-revision.txt

# Create necessary directories
mkdir -p "$GIT_INFO_PATH" "$GEN_FILE_PATH" || true

# Generate Git branch and revision files
git symbolic-ref --short HEAD > "$GIT_BRANCH_FILE"
git rev-parse HEAD > "$GIT_REVISION_FILE"

# Disable analytics
flutter config --no-analytics

# Get Flutter packages
flutter pub get

# Generate Flutter version file
echo "const Map<String, String> flutterVersion =" > "$FLUTTER_VERSION_FILE"
flutter --version --machine | tee -a "$FLUTTER_VERSION_FILE"
sed -i.bak -e ':a' -e 'N' -e '$!ba' -e 's/}\([[:space:]]*\)$/};\1/' "$FLUTTER_VERSION_FILE" && rm "${FLUTTER_VERSION_FILE}.bak"

# Run code generation
dart run build_runner build --delete-conflicting-outputs

# Run gen-l10n
flutter gen-l10n
