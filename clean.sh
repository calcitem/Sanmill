#!/bin/bash

set -euo pipefail

FLUTTER_APP_DIR="src/ui/flutter_app"

cleanup_keys() {
    mv ../key.jks "${FLUTTER_APP_DIR}/android/" 2>/dev/null || true
    mv ../key.properties "${FLUTTER_APP_DIR}/android/" 2>/dev/null || true
}

mv "${FLUTTER_APP_DIR}/android/key.jks" ../
mv "${FLUTTER_APP_DIR}/android/key.properties" ../
trap cleanup_keys EXIT

if command -v flutter >/dev/null 2>&1; then
    echo "Running flutter clean..."
    (cd "${FLUTTER_APP_DIR}" && flutter clean)

    echo "Removing pubspec.lock to refresh dependency resolution..."
    rm -f "${FLUTTER_APP_DIR}/pubspec.lock"
else
    echo "Flutter is not available in PATH; skipping flutter clean and pubspec.lock removal."
fi

git clean -fdx

cleanup_keys
trap - EXIT

if [ "$(uname)" == "Darwin" ]; then
    echo "TODO: macOS"
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    echo "TODO: Linux"
else
    ./flutter-windows-init.sh
fi
