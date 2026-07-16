#!/usr/bin/env bash

# SPDX-License-Identifier: AGPL-3.0-or-later

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 path/to/app-fdroid-release.apk" >&2
  exit 2
fi

apk="$1"
if [[ ! -f "$apk" ]]; then
  echo "F-Droid APK not found: $apk" >&2
  exit 2
fi

contains_marker() {
  unzip -p "$apk" | strings | awk -v marker="$1" '
    index($0, marker) != 0 { found = 1 }
    END { exit found ? 0 : 1 }
  '
}

for forbidden in \
  '/v1/rooms' \
  'SANMILL_ONLINE_BASE_URL' \
  'online.friend_match.session.v1' \
  'sanmill-online.invalid'; do
  if contains_marker "$forbidden"; then
    echo "F-Droid APK contains forbidden online marker: $forbidden" >&2
    exit 1
  fi
done

# GameMode.humanVsCloud and its legacy shell route intentionally remain in
# shared code for persisted-state compatibility. They are not proof that the
# optional online contribution was linked; the service protocol and manifest
# invitation routes above/below are the executable boundaries.

if [[ -n "${SANMILL_ONLINE_HOST:-}" ]] &&
  contains_marker "$SANMILL_ONLINE_HOST"; then
  echo "F-Droid APK contains the production online hostname." >&2
  exit 1
fi

apkanalyzer_bin="$(command -v apkanalyzer || true)"
if [[ -z "$apkanalyzer_bin" ]]; then
  android_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  candidate="$android_sdk/cmdline-tools/latest/bin/apkanalyzer"
  if [[ -n "$android_sdk" && -x "$candidate" ]]; then
    apkanalyzer_bin="$candidate"
  fi
fi

if [[ -n "$apkanalyzer_bin" ]]; then
  manifest="$("$apkanalyzer_bin" manifest print "$apk")"
  if [[ "$manifest" == *'android:scheme="sanmill"'* ]] ||
    [[ "$manifest" == *'/invite/'* ]]; then
    echo "F-Droid manifest contains an online invitation route." >&2
    exit 1
  fi
else
  echo "apkanalyzer is required to verify F-Droid invitation routes." >&2
  exit 2
fi

echo "F-Droid APK contains no executable online-play markers."
