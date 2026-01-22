#!/bin/bash
# 影响维度：影响范围

set -euo pipefail

FILE="src/server.ts"

echo "== ci_impact =="
./scripts/impact-analyzer.sh --file "$FILE" --format json || true
