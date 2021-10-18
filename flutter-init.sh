#!/bin/bash

ENV_FILE_PATH=assets/files
ENV_FILE=$ENV_FILE_PATH/environment_variables.txt

GEN_FILE_PATH=lib/generated
FLUTTER_VERSION_FILE=$GEN_FILE_PATH/flutter_version.dart

cd src/ui/flutter_app || exit

flutter config --no-analytics

flutter pub get

flutter gen-l10n

mkdir -p "$GEN_FILE_PATH" || true

echo "const Map<String, String> flutterVersion =" >"$FLUTTER_VERSION_FILE"
flutter --version --machine >>"$FLUTTER_VERSION_FILE"
echo ";" >>"$FLUTTER_VERSION_FILE"

mkdir -p "$ENV_FILE_PATH" || true
touch "$ENV_FILE"
export >"$ENV_FILE"

flutter pub global activate build_runner
flutter pub run build_runner build --delete-conflicting-outputs
