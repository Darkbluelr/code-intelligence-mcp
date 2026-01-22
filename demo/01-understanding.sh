#!/bin/bash
# 理解维度：语义检索 + Graph-RAG

set -euo pipefail

QUERY="graph store"

echo "== ci_search =="
./bin/ci-search "$QUERY" --limit 5 || true

echo ""
echo "== ci_graph_rag =="
./scripts/graph-rag.sh --query "$QUERY" --format text || true
