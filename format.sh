#!/bin/bash
set -euo pipefail

# Prefer the Dart SDK binary inside an initialized Flutter SDK over the Flutter
# dart wrapper. The wrapper may try to refresh Flutter cache metadata, which
# fails in read-only SDK environments even when dart format itself can run.
DART_BIN="${DART_BIN:-}"
if [ -z "${DART_BIN}" ]; then
    DART_CMD="$(command -v dart)"
    DART_DIR="$(cd "$(dirname "${DART_CMD}")" && pwd)"
    FLUTTER_SDK_DART="${DART_DIR}/cache/dart-sdk/bin/dart"
    if [ -x "${FLUTTER_SDK_DART}" ]; then
        DART_BIN="${FLUTTER_SDK_DART}"
    else
        DART_BIN="${DART_CMD}"
    fi
fi

# Format only project source trees. Avoid build/ and rust_builder/ artifacts,
# which inherit analysis_options.yaml but lack flutter_lints resolution.
"${DART_BIN}" format \
    src/ui/flutter_app/lib \
    src/ui/flutter_app/test \
    src/ui/flutter_app/integration_test \
    src/ui/flutter_app/test_driver \
    scripts/find_keys

if [ -f Cargo.toml ]; then
    cargo fmt --all
    cargo clippy --workspace --all-targets --all-features -- -D warnings
fi

if [ "${1:-}" != "s" ]; then
    git add .
    git commit -m "Format"
fi
