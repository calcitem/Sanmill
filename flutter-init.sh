#!/bin/bash

GEN_FILE_PATH=lib/generated
FLUTTER_VERSION_FILE=$GEN_FILE_PATH/flutter_version.dart
GIT_INFO_PATH=src/ui/flutter_app/assets/files
GIT_BRANCH_FILE=$GIT_INFO_PATH/git-branch.txt
GIT_REVISION_FILE=$GIT_INFO_PATH/git-revision.txt

mkdir -p "$GIT_INFO_PATH" || true
git symbolic-ref --short HEAD > "$GIT_BRANCH_FILE"
git rev-parse HEAD > "$GIT_REVISION_FILE"

cd src/ui/flutter_app || exit

flutter config --no-analytics

flutter pub get

flutter gen-l10n

mkdir -p "$GEN_FILE_PATH" || true

echo "const Map<String, String> flutterVersion =" >"$FLUTTER_VERSION_FILE"
flutter --version --machine >>"$FLUTTER_VERSION_FILE"
echo ";" >>"$FLUTTER_VERSION_FILE"

flutter pub global deactivate build_runner
flutter pub global activate build_runner
flutter pub run build_runner build --delete-conflicting-outputs
