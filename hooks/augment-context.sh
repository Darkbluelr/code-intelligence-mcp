#!/bin/bash
# Augment-style context injection hook v3.0 (Performance Optimized)
# 自动检测意图 + 注入相关代码片段
# 优化目标：3 秒内完成所有搜索

# 配置
MAX_SNIPPETS=3
MAX_LINES=20
SEARCH_TIMEOUT=2  # 搜索超时（秒）
CACHE_DIR="${TMPDIR:-/tmp}/.devbooks-cache"
CACHE_TTL=300  # 缓存有效期 5 分钟

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载共享缓存工具库
CACHE_UTILS="${SCRIPT_DIR}/../../tools/devbooks-cache-utils.sh"
if [ -f "$CACHE_UTILS" ]; then
  # shellcheck source=../../tools/devbooks-cache-utils.sh
  source "$CACHE_UTILS"
fi

# 加载共享工具库（意图检测等）
COMMON_UTILS="${SCRIPT_DIR}/../../tools/devbooks-common.sh"
if [ -f "$COMMON_UTILS" ]; then
  # shellcheck source=../../tools/devbooks-common.sh
  source "$COMMON_UTILS"
fi

# 如果共享库加载失败，直接退出（统一降级策略，保持 DRY）
# 同时检查 cache-utils 和 common 的关键函数
if ! declare -f is_code_intent &>/dev/null || ! declare -f get_cache_key &>/dev/null; then
  echo '{}'; exit 0
fi

# 读取输入
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
CWD="${WORKING_DIRECTORY:-$(pwd)}"

[ -z "$PROMPT" ] && { echo '{}'; exit 0; }

# 创建缓存目录
mkdir -p "$CACHE_DIR" 2>/dev/null

# 意图检测函数由 devbooks-common.sh 提供（CODE_INTENT_PATTERN, NON_CODE_PATTERN, is_code_intent, is_non_code）

# ==================== 符号提取（单次处理） ====================
extract_symbols() {
  local q="$1"

  # 检查缓存
  local cached=$(get_cached "symbols:$q")
  if [ -n "$cached" ]; then
    echo "$cached"
    return
  fi

  local result=$(
    {
      # camelCase (如 getUserById)
      echo "$q" | grep -oE '\b[a-z][a-zA-Z0-9]*[A-Z][a-zA-Z0-9]*\b'
      # PascalCase (如 UserService)
      echo "$q" | grep -oE '\b[A-Z][a-zA-Z0-9]*[a-z][a-zA-Z0-9]*\b'
      # 反引号内容
      echo "$q" | grep -oE '\`[^\`]+\`' | tr -d '\`'
      # 文件路径
      echo "$q" | grep -oE '[a-zA-Z0-9_/\-]+\.(ts|tsx|js|jsx|py|go|sh|md)'
    } | grep -v '^$' | awk '!seen[$0]++' | head -$MAX_SNIPPETS
  )

  # 缓存结果
  set_cache "symbols:$q" "$result"
  echo "$result"
}

# ==================== 代码搜索（并行 + 超时控制） ====================
search_symbol() {
  local sym="$1"
  [ -z "$sym" ] && return

  # 检查缓存
  local cached=$(get_cached "search:$CWD:$sym")
  if [ -n "$cached" ]; then
    echo "$cached"
    return
  fi

  local result=""

  if command -v rg &>/dev/null; then
    # 优化 ripgrep 参数：
    # --max-count=1: 每个文件只匹配一次
    # --max-filesize=500K: 跳过大文件
    # --type-add: 自定义文件类型（更快）
    # --smart-case: 智能大小写
    # -C 3: 减少上下文行数
    result=$(timeout "$SEARCH_TIMEOUT" rg \
      --max-count=1 \
      --max-filesize=500K \
      --smart-case \
      -n -C 3 \
      --type-add 'code:*.{ts,tsx,js,jsx,py,go,sh}' \
      -t code \
      -g '!node_modules' -g '!dist' -g '!build' -g '!.git' -g '!*.lock' -g '!coverage' \
      "$sym" "$CWD" 2>/dev/null | head -$MAX_LINES)
  else
    # fallback to grep with timeout
    result=$(timeout "$SEARCH_TIMEOUT" grep -rn \
      --include='*.ts' --include='*.js' --include='*.py' --include='*.go' \
      --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=build --exclude-dir=.git \
      -A 2 -B 1 "$sym" "$CWD" 2>/dev/null | head -$MAX_LINES)
  fi

  # 缓存结果
  [ -n "$result" ] && set_cache "search:$CWD:$sym" "$result"
  echo "$result"
}

# 并行搜索所有符号
parallel_search() {
  local symbols="$1"
  local results=""
  local pids=()
  local temp_dir
  temp_dir=$(mktemp -d)

  # 设置 trap 确保临时目录被清理（即使异常退出）
  trap 'rm -rf "$temp_dir" 2>/dev/null' RETURN

  # 启动并行搜索（限制并发数为 3）
  local count=0
  while IFS= read -r symbol; do
    [ -z "$symbol" ] && continue

    (
      snippet=$(search_symbol "$symbol")
      if [ -n "$snippet" ]; then
        echo "$symbol" > "$temp_dir/$count.symbol"
        echo "$snippet" > "$temp_dir/$count.snippet"
      fi
    ) &
    pids+=($!)
    ((count++))

    # 限制并发数
    if [ ${#pids[@]} -ge 3 ]; then
      wait -n 2>/dev/null || true
      pids=($(jobs -p 2>/dev/null))
    fi
  done <<< "$symbols"

  # 等待所有后台任务（带超时 + 僵尸进程回收）
  for pid in "${pids[@]}"; do
    if ! timeout 1 wait "$pid" 2>/dev/null; then
      # 先尝试优雅终止
      kill -TERM "$pid" 2>/dev/null
      sleep 0.1
      # 如果还在运行，强制终止
      kill -9 "$pid" 2>/dev/null
      # 回收僵尸进程
      wait "$pid" 2>/dev/null || true
    fi
  done

  # 收集结果
  for i in $(seq 0 $((count - 1))); do
    if [ -f "$temp_dir/$i.symbol" ] && [ -f "$temp_dir/$i.snippet" ]; then
      local sym
      local snip
      sym=$(cat "$temp_dir/$i.symbol")
      snip=$(cat "$temp_dir/$i.snippet")
      results="${results}

🔍 $sym:
\`\`\`
$snip
\`\`\`"
    fi
  done

  # trap RETURN 会自动清理 temp_dir
  echo "$results"
}

# ==================== 热点文件（优化 git 查询） ====================
get_hotspots() {
  [ -d "$CWD/.git" ] || return

  # 检查缓存
  local cached=$(get_cached "hotspots:$CWD")
  if [ -n "$cached" ]; then
    echo "$cached"
    return
  fi

  # 优化 git log 查询：只取文件名，限制深度
  local result=$(timeout 1 git -C "$CWD" log \
    --since="30 days ago" \
    --name-only \
    --pretty=format: \
    --max-count=200 \
    2>/dev/null | \
    grep -v '^$' | \
    grep -vE 'node_modules|dist|build|\.lock|\.md$|\.json$' | \
    sort | uniq -c | sort -rn | head -5 | \
    awk '{printf "  🔥 %s (%d changes)\n", $2, $1}')

  # 缓存结果
  [ -n "$result" ] && set_cache "hotspots:$CWD" "$result"
  echo "$result"
}

check_index() {
  if [ -f "$CWD/index.scip" ]; then
    echo "✅ SCIP 索引可用"
  elif [ -d "$CWD/.git/ckb" ]; then
    echo "✅ CKB 索引可用"
  else
    echo "⚠️ 无索引（建议启用 CKB）"
  fi
}

# ==================== 主逻辑（带总超时控制） ====================
main() {
  # 快速退出条件
  is_non_code "$PROMPT" && { echo '{}'; exit 0; }
  is_code_intent "$PROMPT" || { echo '{}'; exit 0; }

  # 构建上下文
  local CONTEXT="[DevBooks 自动上下文注入 v3]

$(check_index)"

  # 提取符号（快速）
  local SYMBOLS=$(extract_symbols "$PROMPT")

  # 并行搜索代码片段
  local SNIPPETS=""
  if [ -n "$SYMBOLS" ]; then
    SNIPPETS=$(parallel_search "$SYMBOLS")
  fi

  if [ -n "$SNIPPETS" ]; then
    CONTEXT="${CONTEXT}

📦 相关代码：$SNIPPETS"
  fi

  # 热点文件（异步获取）
  local HOTSPOTS=$(get_hotspots)
  [ -n "$HOTSPOTS" ] && CONTEXT="${CONTEXT}

🔥 热点文件：
$HOTSPOTS"

  # 工具建议
  CONTEXT="${CONTEXT}

💡 可用工具：analyzeImpact / findReferences / getCallGraph"

  # 输出
  jq -n --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
}

# 带总超时执行 - 直接调用 main（内部搜索已有独立超时）
# 注意：移除了复杂的 declare -f 包装，因为：
# 1. 内部 search_symbol 已有 SEARCH_TIMEOUT 控制
# 2. 复杂变量传递容易因引号嵌套出错
# 3. 与 global 版本保持一致
main
