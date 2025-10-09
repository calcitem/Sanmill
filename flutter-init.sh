#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/scripts/ensure_flutter.sh"

ensure_flutter_on_path

APP_DIR="${SCRIPT_DIR}/src/ui/flutter_app"
GEN_FILE_PATH="${APP_DIR}/lib/generated"
FLUTTER_VERSION_FILE="${GEN_FILE_PATH}/flutter_version.dart"
GIT_INFO_PATH="${APP_DIR}/assets/files"
GIT_BRANCH_FILE="${GIT_INFO_PATH}/git-branch.txt"
GIT_REVISION_FILE="${GIT_INFO_PATH}/git-revision.txt"

mkdir -p "${GIT_INFO_PATH}" "${GEN_FILE_PATH}" || true

# Handle both branch and tag/detached HEAD scenarios
if git -C "${SCRIPT_DIR}" symbolic-ref --short HEAD > "${GIT_BRANCH_FILE}" 2>/dev/null; then
    # Successfully got branch name
    :
else
    # In detached HEAD state (tag checkout), try to get tag name or commit hash
    if TAG_NAME=$(git -C "${SCRIPT_DIR}" describe --exact-match --tags HEAD 2>/dev/null); then
        echo "${TAG_NAME}" > "${GIT_BRANCH_FILE}"
    else
        # Fallback to commit hash
        git -C "${SCRIPT_DIR}" rev-parse --short HEAD > "${GIT_BRANCH_FILE}"
    fi
fi
git -C "${SCRIPT_DIR}" rev-parse HEAD > "${GIT_REVISION_FILE}"

flutter config --no-analytics

( cd "${APP_DIR}" && flutter pub get )

echo "const Map<String, String> flutterVersion =" > "${FLUTTER_VERSION_FILE}"
flutter --version --machine | tee -a "${FLUTTER_VERSION_FILE}"
sed -i.bak -e ':a' -e 'N' -e '$!ba' -e 's/}\([[:space:]]*\)$/};\1/' "${FLUTTER_VERSION_FILE}" && rm "${FLUTTER_VERSION_FILE}.bak"

( cd "${APP_DIR}" && dart run build_runner build --delete-conflicting-outputs )
( cd "${APP_DIR}" && flutter gen-l10n )
