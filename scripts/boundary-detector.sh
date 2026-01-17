#!/bin/bash
# DevBooks Boundary Detector
# 代码边界检测工具，区分用户代码、库代码、生成代码
# 版本: 1.0
# Trace: AC-004

set -euo pipefail

# 加载共享函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==================== 配置 ====================
DEFAULT_CONFIG="${SCRIPT_DIR}/../config/boundaries.yaml"
DEFAULT_FORMAT="text"

# ==================== 功能开关检查 ====================
# Trace: AC-010
if ! is_feature_enabled "boundary_detector"; then
  log_warn "边界检测器功能已禁用 (features.boundary_detector: false)"
  echo '{"error": "Feature disabled", "message": "边界检测器功能已禁用"}'
  exit 0
fi

# ==================== 帮助信息 ====================
show_help() {
  cat <<'EOF'
Usage: boundary-detector.sh [OPTIONS] <file-or-pattern>

检测文件或目录的代码边界类型。

Options:
  --path FILE        要检测的文件路径（可选，也可以作为位置参数）
  --config FILE      自定义配置文件路径 (默认: config/boundaries.yaml)
  --format FORMAT    输出格式: text 或 json (默认: text)
  -h, --help         显示帮助信息

Output (text):
  FILE  TYPE  CONFIDENCE  MATCHED_RULE

Output (json):
  {"file": "...", "type": "...", "confidence": N, "matched_rule": "..."}

Types:
  user       - 用户代码 (可修改)
  library    - 库代码 (不建议修改)
  generated  - 生成代码 (不建议修改)
  vendor     - 第三方代码 (不建议修改)
  config     - 配置文件

Examples:
  boundary-detector.sh src/index.ts
  boundary-detector.sh --path node_modules/lodash/index.js --format json
  boundary-detector.sh --format json dist/bundle.js
  boundary-detector.sh --config ./my-boundaries.yaml src/
EOF
}

# ==================== 参数解析 ====================
CONFIG_FILE="$DEFAULT_CONFIG"
FORMAT="$DEFAULT_FORMAT"
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --path)
      TARGET="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -*)
      log_error "未知参数: $1"
      show_help
      exit 1
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

# 验证参数
if [[ -z "$TARGET" ]]; then
  log_error "请指定要检测的文件或目录"
  show_help
  exit 1
fi

if [[ "$FORMAT" != "text" && "$FORMAT" != "json" ]]; then
  log_error "无效的 --format 参数: $FORMAT (必须是 text 或 json)"
  exit 1
fi

# ==================== 配置加载 ====================
# 内置默认规则 (当配置文件不存在时使用)
declare -a BUILTIN_RULES
BUILTIN_RULES=(
  "dist/**|generated|0.95|构建输出目录"
  "build/**|generated|0.95|构建输出目录"
  "out/**|generated|0.90|常见构建输出目录"
  "**/*.d.ts|generated|0.85|TypeScript类型声明"
  "**/*.min.js|generated|0.95|压缩JavaScript"
  "**/*.min.css|generated|0.95|压缩CSS"
  "**/*.generated.*|generated|0.90|生成的文件"
  "node_modules/**|library|0.99|Node.js依赖"
  "**/node_modules/**|library|0.99|嵌套Node.js依赖"
  "**/vendor/**|library|0.95|vendor目录"
  "vendor/**|library|0.95|第三方代码"
  "third_party/**|vendor|0.95|第三方代码"
  ".venv/**|library|0.95|Python虚拟环境"
  "venv/**|library|0.95|Python虚拟环境"
  "__pycache__/**|generated|0.99|Python缓存"
  "*.pyc|generated|0.99|Python编译文件"
  "**/__snapshots__/**|generated|0.85|Jest快照"
  ".git/**|generated|0.99|Git内部目录"
  ".idea/**|generated|0.90|JetBrains配置"
  "config/**|config|0.90|配置目录"
  "**/*.config.js|config|0.85|配置文件"
  "**/*.config.ts|config|0.85|配置文件"
  "tsconfig.json|config|0.95|TypeScript配置"
  "package.json|config|0.95|NPM配置"
  "*.yaml|config|0.80|YAML配置文件"
  "*.yml|config|0.80|YAML配置文件"
  ".eslintrc*|config|0.90|ESLint配置"
  ".prettierrc*|config|0.90|Prettier配置"
  "src/**|user|0.85|用户代码目录"
  "lib/**|user|0.75|库代码目录"
  "app/**|user|0.85|应用代码目录"
)

# 从 YAML 加载规则 (简单解析)
load_rules_from_yaml() {
  local yaml_file="$1"
  local rules=()

  if [[ ! -f "$yaml_file" ]]; then
    return
  fi

  # 简单的 YAML 解析: 提取 pattern, type, confidence, reason
  local in_rules=false
  local pattern="" type="" confidence="" reason=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    # 跳过注释和空行
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue

    # 检测 rules: 或 overrides: 开始
    if [[ "$line" =~ ^rules: ]] || [[ "$line" =~ ^overrides: ]]; then
      in_rules=true
      continue
    fi

    # 非缩进行表示新的顶级 key
    if [[ ! "$line" =~ ^[[:space:]] ]] && [[ "$in_rules" == "true" ]]; then
      in_rules=false
      continue
    fi

    if [[ "$in_rules" == "true" ]]; then
      # 解析规则字段
      if [[ "$line" =~ [[:space:]]*-[[:space:]]*pattern:[[:space:]]*\"(.*)\" ]]; then
        # 保存前一条规则
        if [[ -n "$pattern" && -n "$type" ]]; then
          echo "${pattern}|${type}|${confidence:-0.50}|${reason:-未知}"
          pattern="" type="" confidence="" reason=""
        fi
        pattern="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ [[:space:]]*pattern:[[:space:]]*\"(.*)\" ]]; then
        pattern="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ [[:space:]]*type:[[:space:]]*(.+) ]]; then
        type="${BASH_REMATCH[1]}"
        type="${type%%[[:space:]]*}"
      elif [[ "$line" =~ [[:space:]]*confidence:[[:space:]]*([0-9.]+) ]]; then
        confidence="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ [[:space:]]*reason:[[:space:]]*\"(.*)\" ]]; then
        reason="${BASH_REMATCH[1]}"
      fi
    fi
  done < "$yaml_file"

  # 输出最后一条规则
  if [[ -n "$pattern" && -n "$type" ]]; then
    echo "${pattern}|${type}|${confidence:-0.50}|${reason:-未知}"
  fi
}

# ==================== 模式匹配 ====================
# 检查文件是否匹配 glob 模式
# 支持 ** (任意目录) 和 * (任意字符)
match_pattern() {
  local file="$1"
  local pattern="$2"

  # 将 glob 模式转换为正则表达式
  local regex="$pattern"

  # 转义特殊字符 (除了 * 和 ?)
  regex="${regex//./\\.}"

  # ** 匹配任意目录层级 - 先用占位符
  regex="${regex//\*\*/__DOUBLESTAR__}"

  # * 匹配任意字符 (非目录分隔符)
  regex="${regex//\*/__SINGLESTAR__}"

  # 替换回正则表达式
  regex="${regex//__DOUBLESTAR__/.*}"
  regex="${regex//__SINGLESTAR__/[^/]*}"

  # 锚定开头和结尾
  regex="^${regex}$"

  # 执行匹配
  if [[ "$file" =~ $regex ]]; then
    return 0
  else
    return 1
  fi
}

# ==================== 边界检测 ====================
detect_boundary() {
  local file="$1"
  local config="$2"

  # 规范化路径 (移除前导 ./)
  file="${file#./}"

  # 使用内置规则（优先保证功能正确）
  # TODO: 后续增强 YAML 解析
  local rules=("${BUILTIN_RULES[@]}")

  # 遍历规则匹配
  for rule in "${rules[@]}"; do
    IFS='|' read -r pattern type confidence reason <<< "$rule"

    if match_pattern "$file" "$pattern"; then
      echo "$type|$confidence|$pattern|$reason"
      return 0
    fi
  done

  # 默认为用户代码
  echo "user|0.50|default|未匹配任何规则"
}

# ==================== 输出格式化 ====================
output_result() {
  local file="$1"
  local result="$2"
  local format="$3"

  IFS='|' read -r type confidence matched_rule reason <<< "$result"

  if [[ "$format" == "json" ]]; then
    printf '{"schema_version": "1.0", "file": "%s", "type": "%s", "confidence": %s, "matched_rule": "%s", "reason": "%s"}\n' \
      "$file" "$type" "$confidence" "$matched_rule" "$reason"
  else
    printf "%-40s  %-10s  %-10s  %s\n" "$file" "$type" "$confidence" "$matched_rule"
  fi
}

# ==================== 主逻辑 ====================
main() {
  # 检查配置文件
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_warn "配置文件不存在: $CONFIG_FILE (使用内置规则)"
  fi

  # 处理目标
  if [[ -f "$TARGET" ]]; then
    # 单个文件
    local result
    result=$(detect_boundary "$TARGET" "$CONFIG_FILE")
    output_result "$TARGET" "$result" "$FORMAT"
  elif [[ -d "$TARGET" ]]; then
    # 目录: 递归检测所有文件
    if [[ "$FORMAT" == "text" ]]; then
      printf "%-40s  %-10s  %-10s  %s\n" "FILE" "TYPE" "CONFIDENCE" "MATCHED_RULE"
      printf "%-40s  %-10s  %-10s  %s\n" "----" "----" "----------" "------------"
    fi

    find "$TARGET" -type f -not -path "*/.git/*" 2>/dev/null | while read -r file; do
      local result
      result=$(detect_boundary "$file" "$CONFIG_FILE")
      output_result "$file" "$result" "$FORMAT"
    done
  else
    # 可能是 glob 模式
    local result
    result=$(detect_boundary "$TARGET" "$CONFIG_FILE")
    output_result "$TARGET" "$result" "$FORMAT"
  fi
}

# 执行主逻辑
main
