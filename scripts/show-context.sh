#!/bin/bash
# 显示 DevBooks 自动上下文注入的内容
# 用户可以随时运行此脚本查看 AI 看到的上下文信息

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== DevBooks 自动上下文 ===${NC}\n"

# 1. 检查语义索引
echo -e "${GREEN}📊 索引状态：${NC}"
EMBEDDING_INDEX="$PROJECT_ROOT/.devbooks/embeddings/index.tsv"
if [ -f "$EMBEDDING_INDEX" ] && [ -s "$EMBEDDING_INDEX" ]; then
  FILE_COUNT=$(wc -l < "$EMBEDDING_INDEX" | tr -d ' ')
  echo "  ✅ 语义索引可用 ($FILE_COUNT 文件)"
elif [ -f "$PROJECT_ROOT/index.scip" ]; then
  echo "  ✅ SCIP 索引可用"
elif [ -d "$PROJECT_ROOT/.git/ckb" ]; then
else
  echo "  ⚠️  无索引（可运行 /devbooks-index-bootstrap 生成）"
fi

# 2. 显示热点文件
echo -e "\n${RED}🔥 热点文件：${NC}"
if [ -d "$PROJECT_ROOT/.git" ]; then
  git -C "$PROJECT_ROOT" log --since="30 days ago" --name-only --pretty=format: 2>/dev/null | \
    grep -v '^$' | \
    grep -vE 'node_modules|dist|build|\.lock|\.md$|__pycache__|\.pyc$' | \
    sort | uniq -c | sort -rn | head -5 | \
    while read -r count file; do
      echo "  🔥 $file ($count changes)"
    done
else
  echo "  ⚠️  非 Git 仓库"
fi

# 3. 显示可用工具
echo -e "\n${YELLOW}💡 可用工具：${NC}"
echo "  - analyzeImpact: 分析符号变更的影响范围"
echo "  - findReferences: 查找符号引用"
echo "  - getCallGraph: 获取调用图"
echo "  - ci_graph_rag: 图RAG上下文检索"
echo "  - ci_search: 语义搜索"
echo "  - ci_impact: 影响分析"

# 4. 显示项目信息
echo -e "\n${BLUE}📦 项目信息：${NC}"
if [ -f "$PROJECT_ROOT/package.json" ]; then
  PROJECT_NAME=$(jq -r '.name // "未命名"' "$PROJECT_ROOT/package.json" 2>/dev/null)
  echo "  名称: $PROJECT_NAME"
  if [ -f "$PROJECT_ROOT/tsconfig.json" ]; then
    echo "  技术栈: Node.js, TypeScript"
  else
    echo "  技术栈: Node.js"
  fi
fi

# 5. 显示最近提交
if [ -d "$PROJECT_ROOT/.git" ]; then
  echo -e "\n${BLUE}📝 最近提交：${NC}"
  git -C "$PROJECT_ROOT" log --oneline -3 2>/dev/null | \
    while read -r line; do
      echo "  - $line"
    done
fi

echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}💡 这是 AI 在每次对话时自动看到的上下文信息${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
