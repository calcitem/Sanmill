#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/ensure_flutter.sh"

ensure_flutter_on_path

APP_DIR="${SCRIPT_DIR}/../src/ui/flutter_app"

( cd "${APP_DIR}" && flutter pub outdated )
( cd "${APP_DIR}" && flutter pub upgrade --major-versions )
