#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/scripts/ensure_flutter.sh"

ensure_flutter_on_path

"${SCRIPT_DIR}/flutter-init.sh"

flutter config --enable-windows-desktop
# flutter create --platforms=windows .
