#!/bin/bash
set -e

# ===== AI Usage ビルドスクリプト =====
# Mac: mac/build.sh に委譲（Sparkle 直接配布）

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 AI Usage — Mac 版をビルドします..."
exec ./mac/build.sh "$@"
