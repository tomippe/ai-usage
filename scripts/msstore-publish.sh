#!/bin/bash
# プロジェクト用ラッパー — 実体は build-common/msstore-publish.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_COMMON="$(cd "$PROJECT_ROOT/../build-common" && pwd)"
exec "$BUILD_COMMON/msstore-publish.sh" "$@"
