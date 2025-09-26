#!/bin/bash

# When sourced, this script provides helpers for ensuring that the
# required Flutter SDK version is available. When executed directly it
# will download the SDK if necessary and print the resolved SDK path.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
fi

SANMILL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANMILL_REPO_ROOT="$(cd "${SANMILL_SCRIPT_DIR}/.." && pwd)"

: "${REQUIRED_FLUTTER_VERSION:=3.35.4}"
: "${FLUTTER_CHANNEL:=stable}"
: "${FLUTTER_DOWNLOAD_BASE_URL:=https://storage.googleapis.com/flutter_infra_release/releases}"
: "${FLUTTER_TOOL_DIR:=${SANMILL_REPO_ROOT}/.tools/flutter}"

FLUTTER_SDK_PATH=""

flutter__detect_system_flutter() {
  # Check if both flutter and dart commands are available
  if ! command -v flutter >/dev/null 2>&1; then
    echo "Flutter command not found in system PATH." >&2
    return 1
  fi

  if ! command -v dart >/dev/null 2>&1; then
    echo "Dart command not found in system PATH." >&2
    return 1
  fi

  local flutter_cmd
  flutter_cmd="$(command -v flutter)"

  local version_line
  if ! version_line="$("${flutter_cmd}" --version 2>/dev/null | head -n 1)"; then
    echo "Failed to get Flutter version information." >&2
    return 1
  fi

  # Expected format: "Flutter 3.35.4 • channel stable • ..."
  local version
  version="$(printf '%s' "${version_line}" | awk '{print $2}')"
  if [[ "${version}" != "${REQUIRED_FLUTTER_VERSION}" ]]; then
    echo "Found Flutter ${version}, but ${REQUIRED_FLUTTER_VERSION} is required." >&2
    return 1
  fi

  local flutter_bin_dir
  flutter_bin_dir="$(cd "$(dirname "${flutter_cmd}")" && pwd)"
  FLUTTER_SDK_PATH="$(cd "${flutter_bin_dir}/.." && pwd)"
  return 0
}

flutter__is_windows() {
  # Check for Windows environment variables first
  if [[ -n "${WINDIR:-}" || -n "${windir:-}" ]]; then
    return 0
  fi

  # Check for Windows-specific paths
  if [[ -d "/c/Windows" || -d "/mnt/c/Windows" ]]; then
    return 0
  fi

  # Check uname output for Windows-like environments
  local uname_s
  uname_s="$(uname -s 2>/dev/null || echo unknown)"
  case "${uname_s}" in
    MINGW*|MSYS*|CYGWIN*)
      return 0
      ;;
    *)
      # If uname is not available and we're likely on Windows
      if ! command -v uname >/dev/null 2>&1; then
        # Check for common Windows indicators
        if command -v powershell.exe >/dev/null 2>&1 || command -v cmd.exe >/dev/null 2>&1; then
          return 0
        fi
      fi
      return 1
      ;;
  esac
}

flutter__resolve_archive() {
  local uname_s
  uname_s="$(uname -s 2>/dev/null || echo unknown)"
  case "${uname_s}" in
    Linux*)
      printf 'linux flutter_linux_%s-%s.tar.xz\n' "${REQUIRED_FLUTTER_VERSION}" "${FLUTTER_CHANNEL}"
      ;;
    Darwin*)
      printf 'macos flutter_macos_%s-%s.zip\n' "${REQUIRED_FLUTTER_VERSION}" "${FLUTTER_CHANNEL}"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      printf 'windows flutter_windows_%s-%s.zip\n' "${REQUIRED_FLUTTER_VERSION}" "${FLUTTER_CHANNEL}"
      ;;
    *)
      printf 'unsupported %s\n' "${uname_s}"
      return 1
      ;;
  esac
}

flutter__download_sdk() {
  local archive_info
  archive_info="$(flutter__resolve_archive)" || {
    echo "Unsupported platform for Flutter SDK download." >&2
    return 1
  }

  local platform archive_name
  platform="${archive_info%% *}"
  archive_name="${archive_info#* }"
  local url
  url="${FLUTTER_DOWNLOAD_BASE_URL}/${FLUTTER_CHANNEL}/${platform}/${archive_name}"

  echo "Downloading Flutter SDK ${REQUIRED_FLUTTER_VERSION} (${platform})..." >&2

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' RETURN

  local archive_path
  archive_path="${tmp_dir}/${archive_name}"

  if command -v curl >/dev/null 2>&1; then
    curl -fL "${url}" -o "${archive_path}"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${archive_path}" "${url}"
  else
    echo "Neither curl nor wget is available to download Flutter SDK." >&2
    return 1
  fi

  rm -rf "${tmp_dir}/flutter"

  if [[ "${archive_name}" == *.tar.xz ]]; then
    tar -xf "${archive_path}" -C "${tmp_dir}"
  else
    if ! command -v unzip >/dev/null 2>&1; then
      echo "The unzip command is required to extract the Flutter SDK archive." >&2
      return 1
    fi
    unzip -q "${archive_path}" -d "${tmp_dir}"
  fi

  if [[ ! -d "${tmp_dir}/flutter" ]]; then
    echo "Unexpected Flutter SDK archive layout retrieved from ${url}." >&2
    return 1
  fi

  local target_dir
  target_dir="${FLUTTER_TOOL_DIR}/${REQUIRED_FLUTTER_VERSION}"
  mkdir -p "${FLUTTER_TOOL_DIR}"
  rm -rf "${target_dir}"
  mv "${tmp_dir}/flutter" "${target_dir}"
  FLUTTER_SDK_PATH="${target_dir}"

  rm -rf "${tmp_dir}"
  trap - RETURN
}

ensure_flutter_sdk() {
  # If FLUTTER_SDK_PATH is already set and valid, use it
  if [[ -n "${FLUTTER_SDK_PATH}" && -x "${FLUTTER_SDK_PATH}/bin/flutter" ]]; then
    return 0
  fi

  # Check for previously downloaded SDK first
  local target_dir
  target_dir="${FLUTTER_TOOL_DIR}/${REQUIRED_FLUTTER_VERSION}"
  if [[ -x "${target_dir}/bin/flutter" ]]; then
    FLUTTER_SDK_PATH="${target_dir}"
    return 0
  fi

  # Try to use system Flutter/Dart if available
  if flutter__detect_system_flutter; then
    return 0
  fi

  # Only download if Flutter/Dart commands are not available
  # and we're not on Windows (Git Bash, Cygwin, etc.)
  if flutter__is_windows; then
    echo "Flutter and Dart commands are not available in system PATH." >&2
    echo "On Windows, please install Flutter manually from https://flutter.dev/docs/get-started/install/windows" >&2
    echo "or use the official Flutter installer." >&2
    return 1
  fi

  # Download Flutter SDK for non-Windows platforms
  echo "Flutter and Dart commands not found. Downloading Flutter SDK..." >&2
  flutter__download_sdk
}

ensure_flutter_on_path() {
  ensure_flutter_sdk || return 1
  
  if [[ -z "${FLUTTER_SDK_PATH}" ]]; then
    echo "FLUTTER_SDK_PATH is not set. Cannot add Flutter to PATH." >&2
    return 1
  fi

  # Set FLUTTER_HOME environment variable
  export FLUTTER_HOME="${FLUTTER_SDK_PATH}"
  
  # Add Flutter bin directory to PATH if not already present
  local flutter_bin_dir="${FLUTTER_SDK_PATH}/bin"
  case ":${PATH}:" in
    *:"${flutter_bin_dir}":*) 
      # Already in PATH
      ;;
    *) 
      export PATH="${flutter_bin_dir}:${PATH}"
      echo "Added Flutter to PATH: ${flutter_bin_dir}" >&2
      ;;
  esac

  # Verify that flutter and dart commands are now available
  if ! command -v flutter >/dev/null 2>&1; then
    echo "Warning: Flutter command still not available after adding to PATH." >&2
    return 1
  fi
  
  if ! command -v dart >/dev/null 2>&1; then
    echo "Warning: Dart command still not available after adding to PATH." >&2
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ensure_flutter_sdk
  printf '%s\n' "${FLUTTER_SDK_PATH}"
fi
