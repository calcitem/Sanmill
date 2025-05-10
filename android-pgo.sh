#!/usr/bin/env bash
# Android Profile-Guided Optimisation helper for Sanmill
# © 2025 – distributed under the GPLv3 licence.

set -euo pipefail   # stop on first error, undefined var, or failed pipe

#######################################################################
# Path setup – adapt only if you moved the project --------------------
#######################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_APP_DIR="$SCRIPT_DIR/src/ui/flutter_app"
ANDROID_DIR="$FLUTTER_APP_DIR/android"
FLUTTER_BUILD_OUTPUT_DIR="$FLUTTER_APP_DIR/build/app/outputs/apk"
PACKAGE_NAME="com.calcitem.sanmill"

PROFILE_DIR_NAME="pgo_profile_data"
PROFILE_DIR="$ANDROID_DIR/$PROFILE_DIR_NAME"
PROFILE_STEM="pgo_profile_base"      # basename without extension

#######################################################################
# Helper: show usage --------------------------------------------------
#######################################################################
show_help() {
  cat <<EOF
Android PGO Workflow
Usage: $(basename "$0") [generate | collect | optimize | clean | all]

  generate   Build an instrumented APK ready for collecting profiles
  collect    Pull *.profraw from device and merge into $PROFILE_STEM.profdata
  optimize   Build a release APK using the merged profile
  clean      Remove all PGO artefacts
  all        Run the full workflow (generate ➜ collect ➜ optimize)
EOF
}

#######################################################################
# Preconditions -------------------------------------------------------
#######################################################################
check_prerequisites() {
  command -v adb      >/dev/null || { echo "adb not in PATH"; exit 1; }
  command -v flutter  >/dev/null || { echo "flutter not in PATH"; exit 1; }
  command -v llvm-profdata >/dev/null || \
    echo "⚠ llvm-profdata not in PATH – only needed for Clang profiles."
}

#######################################################################
# Build instrumented APK ---------------------------------------------
#######################################################################
generate_profiles() {
  echo "▶ Building instrumented APK…"
  mkdir -p "$PROFILE_DIR"
  cd "$FLUTTER_APP_DIR"
  flutter clean
  flutter pub get

  # Expose the toggles as environment variables so CMake can read them.
  export USE_PGO=ON PGO_GENERATE=ON PGO_USE=OFF
  # let the native build know where to drop .profraw (same path we hard-coded above)
  export PGO_PROFILE_PATH="/data/data/${PACKAGE_NAME}/files/sanmill"

  cd "$ANDROID_DIR"
  ./gradlew assembleProfile

  local apk
  apk=$(find "$FLUTTER_BUILD_OUTPUT_DIR/profile" -name "*.apk" -print -quit)
  [ -f "$apk" ] || { echo "✗ Instrumented APK not found"; exit 1; }

  echo "✓ Built: $apk"
  read -rp "Install on connected device? [y/N] " yn
  [[ $yn =~ ^[Yy]$ ]] && adb install -r "$apk"
}

#######################################################################
# Pull & merge profiles ----------------------------------------------
#######################################################################
collect_profiles() {
  echo "▶ Collecting *.profraw from device…"
  local remote_dir="/data/data/$PACKAGE_NAME/files"
  adb shell am force-stop "$PACKAGE_NAME" || true

  # Are there any files at all?
  local count
  count=$(adb shell "run-as $PACKAGE_NAME sh -c 'ls $remote_dir/*.profraw 2>/dev/null | wc -l'")
  if [[ $count == 0 ]]; then
    echo "✗ No .profraw files found – did you actually exercise the app?" >&2
    exit 1
  fi

  mkdir -p "$PROFILE_DIR"
  # Stream the tarball directly to local extraction.
  adb exec-out "run-as $PACKAGE_NAME sh -c 'cd $remote_dir && tar -cf - *.profraw'" \
      | tar -xf - -C "$PROFILE_DIR"

  echo "✓ Pulled $count files; merging…"
  cd "$PROFILE_DIR"
  llvm-profdata merge --output="$PROFILE_STEM.profdata" *.profraw
  rm *.profraw
  echo "✓ Merged profile at $PROFILE_DIR/$PROFILE_STEM.profdata"
}

#######################################################################
# Build optimised APK -------------------------------------------------
#######################################################################
build_optimized() {
  [ -f "$PROFILE_DIR/$PROFILE_STEM.profdata" ] || {
    echo "✗ Profile $PROFILE_STEM.profdata not found. Run collect first."; exit 1; }

  cd "$FLUTTER_APP_DIR"
  flutter clean
  flutter pub get

  export USE_PGO=ON PGO_GENERATE=OFF PGO_USE=ON
  export PGO_PROFILE_PATH="$PROFILE_DIR/$PROFILE_STEM"

  cd "$ANDROID_DIR"
  ./gradlew assembleRelease

  local apk
  apk=$(find "$FLUTTER_BUILD_OUTPUT_DIR/release" -name "*.apk" -print -quit)
  [ -f "$apk" ] || { echo "✗ Optimised APK not found"; exit 1; }

  echo "✓ Built optimised APK at $apk"
  read -rp "Install on connected device? [y/N] " yn
  [[ $yn =~ ^[Yy]$ ]] && adb install -r "$apk"
}

#######################################################################
# Clean ---------------------------------------------------------------
#######################################################################
clean_artifacts() {
  echo "▶ Cleaning artefacts…"
  rm -rf "$PROFILE_DIR"
  (cd "$FLUTTER_APP_DIR" && flutter clean)
}

#######################################################################
# Main dispatcher -----------------------------------------------------
#######################################################################
cmd=${1:-help}
case "$cmd" in
  generate)  check_prerequisites; generate_profiles ;;
  collect)   check_prerequisites; collect_profiles   ;;
  optimize)  check_prerequisites; build_optimized    ;;
  clean)     clean_artifacts                         ;;
  all)
    check_prerequisites
    generate_profiles
    echo -e "\n→ Now run the app, drive ALL native code paths, then exit it."
    read -n1 -s -rp "Press any key to continue once done…"
    echo
    collect_profiles
    build_optimized
    ;;
  *) show_help; exit 1 ;;
esac
