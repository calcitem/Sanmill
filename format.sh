#!/bin/bash
set -euo pipefail

# Format only project source trees. Avoid build/ and rust_builder/ artifacts,
# which inherit analysis_options.yaml but lack flutter_lints resolution.
dart format \
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
