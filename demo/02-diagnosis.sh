#!/bin/bash
# 诊断维度：Bug 定位 + 调用链

set -euo pipefail

ERROR_MSG="TypeError: Cannot read property 'user'"
SYMBOL="handleToolCall"

echo "== ci_bug_locate =="
./scripts/bug-locator.sh --error "$ERROR_MSG" --format json || true

echo ""
echo "== ci_call_chain =="
./scripts/call-chain.sh --symbol "$SYMBOL" --max-depth 2 --format json || true
