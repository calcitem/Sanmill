#!/bin/bash

# When sourced, this script ensures the Rust toolchain pinned in
# rust-toolchain.toml is available on PATH. When executed directly it
# will install rustup if necessary and print the resolved cargo home.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
fi

SANMILL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANMILL_REPO_ROOT="$(cd "${SANMILL_SCRIPT_DIR}/.." && pwd)"
RUST_TOOLCHAIN_FILE="${SANMILL_REPO_ROOT}/rust-toolchain.toml"

: "${RUSTUP_HOME:=${HOME}/.rustup}"
: "${CARGO_HOME:=${HOME}/.cargo}"

REQUIRED_RUST_VERSION=""
RUST_COMPONENTS=()

rust__activate_cargo_home() {
  export RUSTUP_HOME
  export CARGO_HOME

  local cargo_bin_dir="${CARGO_HOME}/bin"
  case ":${PATH}:" in
    *:"${cargo_bin_dir}":*)
      ;;
    *)
      export PATH="${cargo_bin_dir}:${PATH}"
      echo "Added Rust to PATH: ${cargo_bin_dir}" >&2
      ;;
  esac
}

rust__read_toolchain_metadata() {
  if [[ ! -f "${RUST_TOOLCHAIN_FILE}" ]]; then
    echo "rust-toolchain.toml not found at ${RUST_TOOLCHAIN_FILE}." >&2
    return 1
  fi

  REQUIRED_RUST_VERSION="$(
    grep -E '^[[:space:]]*channel[[:space:]]*=' "${RUST_TOOLCHAIN_FILE}" \
      | head -n1 \
      | sed -E 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"?([^"]+)"?.*/\1/'
  )"
  if [[ -z "${REQUIRED_RUST_VERSION}" ]]; then
    echo "Could not parse channel from ${RUST_TOOLCHAIN_FILE}." >&2
    return 1
  fi

  local components_line
  components_line="$(
    grep -E '^[[:space:]]*components[[:space:]]*=' "${RUST_TOOLCHAIN_FILE}" \
      | head -n1 \
      || true
  )"
  RUST_COMPONENTS=()
  if [[ -n "${components_line}" ]]; then
    local components_csv
    components_csv="$(
      printf '%s' "${components_line}" \
        | sed -E 's/^[[:space:]]*components[[:space:]]*=[[:space:]]*\[(.*)\].*/\1/'
    )"
    local component
    local old_ifs="${IFS}"
    IFS=','
    for component in ${components_csv}; do
      component="${component//\"/}"
      component="${component//[[:space:]]/}"
      if [[ -n "${component}" ]]; then
        RUST_COMPONENTS+=("${component}")
      fi
    done
    IFS="${old_ifs}"
  fi
}

rust__rustc_matches_required_version() {
  local rustc_cmd="$1"
  local version_line
  local version

  version_line="$("${rustc_cmd}" --version 2>/dev/null || true)"
  version="$(printf '%s' "${version_line}" | awk '{print $2}')"
  [[ "${version}" == "${REQUIRED_RUST_VERSION}" ]]
}

rust__detect_system_rust() {
  if ! command -v cargo >/dev/null 2>&1; then
    return 1
  fi

  if ! command -v rustc >/dev/null 2>&1; then
    return 1
  fi

  rust__rustc_matches_required_version "$(command -v rustc)"
}

rust__install_rustup() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to install rustup." >&2
    return 1
  fi

  echo "Installing rustup with toolchain ${REQUIRED_RUST_VERSION}..." >&2
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --default-toolchain "${REQUIRED_RUST_VERSION}"
}

rust__ensure_toolchain_components() {
  if ! command -v rustup >/dev/null 2>&1; then
    return 0
  fi

  rustup toolchain install "${REQUIRED_RUST_VERSION}" >/dev/null || return 1

  local component
  for component in "${RUST_COMPONENTS[@]}"; do
    rustup component add --toolchain "${REQUIRED_RUST_VERSION}" "${component}" >/dev/null || return 1
  done
}

ensure_rust_toolchain() {
  rust__read_toolchain_metadata || return 1
  rust__activate_cargo_home

  if rust__detect_system_rust; then
    rust__ensure_toolchain_components || return 1
    return 0
  fi

  if command -v rustup >/dev/null 2>&1; then
    rust__ensure_toolchain_components || return 1
    if rust__detect_system_rust; then
      return 0
    fi
  fi

  rust__install_rustup || return 1
  rust__ensure_toolchain_components || return 1

  if ! rust__detect_system_rust; then
    echo "Rust ${REQUIRED_RUST_VERSION} is required but was not activated." >&2
    return 1
  fi
}

ensure_rust_on_path() {
  ensure_rust_toolchain || return 1
  rust__activate_cargo_home

  if ! command -v cargo >/dev/null 2>&1; then
    echo "Warning: cargo command still not available after adding to PATH." >&2
    return 1
  fi

  if ! command -v rustc >/dev/null 2>&1; then
    echo "Warning: rustc command still not available after adding to PATH." >&2
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ensure_rust_toolchain
  printf '%s\n' "${CARGO_HOME}"
fi
