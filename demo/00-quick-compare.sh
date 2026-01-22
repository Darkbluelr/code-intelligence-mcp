#!/bin/bash
# 快速对比：有/无上下文注入

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/augment-context-global.sh"

if [ ! -x "$HOOK" ]; then
  echo "缺少 hook: $HOOK" >&2
  exit 1
fi

prompt="fix the bug in search function"

echo "=============================="
echo "❌ 没有上下文注入"
echo "用户提示: $prompt"
echo "=============================="
echo

echo "=============================="
echo "✅ 有上下文注入"
echo "用户提示: $prompt"
echo "=============================="
echo

echo "{\"prompt\":\"$prompt\"}" | "$HOOK" --format text
