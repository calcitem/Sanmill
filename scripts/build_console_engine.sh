#!/usr/bin/env bash
#
# Build a minimal, GUI-free UCI console engine from the master C++ sources.
#
# The resulting executable speaks standard UCI (position / go / setoption /
# bestmove) and is intended to be pitted against the Rust/TGF engine of the
# Sanmill `next` branch via that repo's head-to-head harness
# (scripts/run_head_to_head.sh).
#
# Supported hosts:
#   * Linux   (g++ or clang++)
#   * macOS   (g++ or clang++; links dynamically)
#   * Windows (MinGW-w64 g++ via Git Bash / MSYS2 / Strawberry Perl)
#
# Design notes:
#   * The Perfect Database tree is NOT compiled.  Its few entry-point symbols
#     are satisfied by perfect_stub.cpp (repo root); they are never called
#     because the harness keeps UsePerfectDatabase disabled.
#   * benchmark.cpp is excluded (it only pulls in unused perfect symbols).
#   * Static linking is attempted on MinGW/Linux when NO_STATIC is unset;
#     macOS always links dynamically (Apple does not support portable static
#     binaries the same way).
#
# Usage:
#   scripts/build_console_engine.sh [output_name]
#
# Environment overrides:
#   CXX        C++ compiler (default: g++, else clang++)
#   NO_STATIC  set to 1 to skip static libgcc/libstdc++ (and -static on MinGW)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

STUB="perfect_stub.cpp"

detect_platform() {
    local uname_s
    uname_s="$(uname -s 2>/dev/null || echo unknown)"
    case "${uname_s}" in
    MINGW* | MSYS* | CYGWIN*)
        echo mingw
        ;;
    Darwin)
        echo macos
        ;;
    Linux)
        echo linux
        ;;
    *)
        echo unix
        ;;
    esac
}

detect_cxx() {
    if [[ -n "${CXX:-}" ]]; then
        echo "${CXX}"
        return
    fi
    if command -v g++ >/dev/null 2>&1; then
        echo g++
        return
    fi
    if command -v clang++ >/dev/null 2>&1; then
        echo clang++
        return
    fi
    echo ""
}

default_output_name() {
    case "$1" in
    mingw) echo master_engine.exe ;;
    *) echo master_engine ;;
    esac
}

collect_core_sources() {
    shopt -s nullglob
    local -a all=(src/*.cpp)
    shopt -u nullglob
    if ((${#all[@]} == 0)); then
        echo "error: no src/*.cpp files found under ${ROOT_DIR}/src" >&2
        exit 1
    fi
    CORE_SRCS=()
    local f base
    for f in "${all[@]}"; do
        base="$(basename "${f}")"
        [[ "${base}" == benchmark.cpp ]] && continue
        CORE_SRCS+=("${f}")
    done
    if ((${#CORE_SRCS[@]} == 0)); then
        echo "error: no core sources left after excluding benchmark.cpp" >&2
        exit 1
    fi
}

append_link_flags() {
    local platform="$1"
    LINK_FLAGS=()
    case "${platform}" in
    mingw)
        if [[ "${NO_STATIC:-0}" != "1" ]]; then
            LINK_FLAGS+=(-static -static-libgcc -static-libstdc++)
        fi
        ;;
    linux | unix)
        LINK_FLAGS+=(-pthread)
        if [[ "${NO_STATIC:-0}" != "1" ]]; then
            LINK_FLAGS+=(-static-libgcc -static-libstdc++)
        fi
        ;;
    macos)
        LINK_FLAGS+=(-pthread)
        ;;
    esac
}

PLATFORM="$(detect_platform)"
CXX="$(detect_cxx)"
if [[ -z "${CXX}" ]]; then
    echo "error: no C++ compiler found. Install g++ or clang++, or set CXX." >&2
    case "${PLATFORM}" in
    mingw)
        echo "       Windows: MinGW-w64 (MSYS2, Strawberry Perl, etc.)." >&2
        ;;
    macos)
        echo "       macOS: xcode-select --install, or brew install gcc." >&2
        ;;
    linux)
        echo "       Linux: e.g. apt install build-essential / dnf install gcc-c++." >&2
        ;;
    esac
    exit 1
fi

if [[ ! -f "${STUB}" ]]; then
    echo "error: ${STUB} not found in repo root (${ROOT_DIR})." >&2
    echo "       It provides link-time stubs for the disabled perfect DB." >&2
    exit 1
fi

OUT="${1:-$(default_output_name "${PLATFORM}")}"
collect_core_sources
append_link_flags "${PLATFORM}"

echo "Platform : ${PLATFORM}"
echo "Compiler : $("${CXX}" --version | head -1)"
echo "Output   : ${OUT}"
echo "Static   : $(
    case "${PLATFORM}" in
    macos) echo n/a ;;
    *)
        if [[ "${NO_STATIC:-0}" == "1" ]]; then echo no; else echo yes; fi
        ;;
    esac
)"
echo "Building ${#CORE_SRCS[@]} core sources + perfect_errors.cpp + ${STUB} ..."

set -x
"${CXX}" -std=c++17 -O2 -w -DNDEBUG \
    -Isrc -Iinclude -Isrc/perfect \
    "${CORE_SRCS[@]}" \
    src/perfect/perfect_errors.cpp \
    "${STUB}" \
    "${LINK_FLAGS[@]}" \
    -o "${OUT}"
set +x

echo "Done: ${ROOT_DIR}/${OUT}"
