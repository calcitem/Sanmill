#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/scripts/ensure_flutter.sh"

ensure_flutter_on_path

"${SCRIPT_DIR}/flutter-init.sh"

flutter config --enable-linux-desktop

( cd "${SCRIPT_DIR}/src/ui/flutter_app" && flutter create --platforms=linux . )
