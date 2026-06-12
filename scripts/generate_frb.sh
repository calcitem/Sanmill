#!/bin/bash
# Install flutter_rust_bridge_codegen (if needed) and regenerate FRB bindings.
# Produces crates/tgf-frb/src/frb_generated.rs (gitignored) and updates Dart
# files under src/ui/flutter_app/lib/src/rust/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${REPO_ROOT}/src/ui/flutter_app"
FRB_RUST_OUTPUT="${REPO_ROOT}/crates/tgf-frb/src/frb_generated.rs"

# shellcheck source=ensure_frb_codegen.sh
source "${SCRIPT_DIR}/ensure_frb_codegen.sh"
ensure_frb_codegen_on_path

if ! command -v flutter &>/dev/null; then
  echo "[generate_frb] ERROR: flutter is required (run from an environment with Flutter on PATH)." >&2
  exit 1
fi

echo "[generate_frb] Resolving Flutter dependencies..."
( cd "${APP_DIR}" && flutter pub get )

echo "[generate_frb] Running flutter_rust_bridge_codegen generate..."
( cd "${APP_DIR}" && flutter_rust_bridge_codegen generate )

if [[ ! -f "${FRB_RUST_OUTPUT}" ]]; then
  echo "[generate_frb] ERROR: ${FRB_RUST_OUTPUT} was not produced." >&2
  exit 1
fi

echo "[generate_frb] OK: ${FRB_RUST_OUTPUT}"
