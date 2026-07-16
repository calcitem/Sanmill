#!/usr/bin/env bash

# SPDX-License-Identifier: AGPL-3.0-or-later

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wasm_input="$repo_root/target/wasm32-unknown-unknown/release/tgf_cloud_wasm.wasm"
wasm_output="$repo_root/services/online-worker/wasm"

if ! command -v wasm-bindgen >/dev/null 2>&1; then
  echo "wasm-bindgen is required; install it with:" >&2
  echo "  cargo install wasm-bindgen-cli --locked" >&2
  exit 1
fi

cargo build \
  --manifest-path "$repo_root/Cargo.toml" \
  -p tgf-cloud-wasm \
  --release \
  --target wasm32-unknown-unknown

wasm-bindgen \
  "$wasm_input" \
  --target web \
  --out-dir "$wasm_output" \
  --out-name tgf_cloud_wasm
