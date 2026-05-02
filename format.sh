#!/bin/bash
set -euo pipefail

dart format .

if [ -f Cargo.toml ]; then
    cargo fmt --all
    cargo clippy --workspace --all-targets --all-features -- -D warnings
fi

if [ "${1:-}" != "s" ]; then
    git add .
    git commit -m "Format"
fi
