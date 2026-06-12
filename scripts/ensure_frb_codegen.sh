#!/bin/bash
# Ensure flutter_rust_bridge_codegen is on PATH at the version pinned in
# crates/tgf-frb/Cargo.toml and src/ui/flutter_app/pubspec.yaml.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
fi

: "${FRB_CODEGEN_VERSION:=2.12.0}"

ensure_frb_codegen_on_path() {
  if command -v flutter_rust_bridge_codegen &>/dev/null; then
    local version_line
    version_line="$(flutter_rust_bridge_codegen --version 2>&1 | head -n1 || true)"
    if [[ "${version_line}" == *"${FRB_CODEGEN_VERSION}"* ]]; then
      return 0
    fi
    echo "[ensure_frb_codegen] Reinstalling flutter_rust_bridge_codegen ${FRB_CODEGEN_VERSION} (was: ${version_line})."
  else
    echo "[ensure_frb_codegen] Installing flutter_rust_bridge_codegen ${FRB_CODEGEN_VERSION}..."
  fi

  if ! command -v cargo &>/dev/null; then
    echo "[ensure_frb_codegen] ERROR: cargo is required to install flutter_rust_bridge_codegen." >&2
    return 1
  fi

  cargo install flutter_rust_bridge_codegen \
    --version "${FRB_CODEGEN_VERSION}" \
    --locked \
    --force
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ensure_frb_codegen_on_path
fi
