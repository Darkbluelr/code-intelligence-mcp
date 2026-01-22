#!/bin/bash
# 质量维度：热点 + 复杂度 + 漂移

set -euo pipefail

echo "== ci_hotspot =="
./scripts/hotspot-analyzer.sh --format json --top 5 --path . || true

echo ""
echo "== ci_complexity =="
./scripts/complexity.sh --format json --path src/ || true

echo ""
echo "== ci_drift_detect =="
./scripts/drift-detector.sh --snapshot . --output /tmp/ci-drift-snapshot.json >/dev/null 2>&1 || true
./scripts/drift-detector.sh --compare /tmp/ci-drift-snapshot.json /tmp/ci-drift-snapshot.json --format json || true
