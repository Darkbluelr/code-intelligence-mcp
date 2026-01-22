#!/bin/bash
# performance-regression.sh - 性能回退检测
#
# 用法:
#   performance-regression.sh --baseline <baseline.json> --current <current.json>
#
# 规则:
#   - MRR@10 >= baseline * 0.95
#   - P95 延迟 <= baseline * 1.10

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"
FEATURES_CONFIG_FILE="${FEATURES_CONFIG:-$PROJECT_ROOT/config/features.yaml}"

log_info() { echo "[INFO] $1" >&2; }
log_warn() { echo "[WARN] $1" >&2; }
log_fail() { echo "[FAIL] $1" >&2; }

feature_enabled() {
  local feature="$1"

  if [[ -n "${DEVBOOKS_ENABLE_ALL_FEATURES:-}" ]]; then
    return 0
  fi

  if [[ ! -f "$FEATURES_CONFIG_FILE" ]]; then
    return 0
  fi

  local value
  value=$(awk -v feature="$feature" '
    BEGIN { in_features = 0 }
    /^features:/ { in_features = 1; next }
    /^[a-zA-Z]/ && !/^features:/ { in_features = 0 }
    in_features && $0 ~ feature ":" {
      getline
      if ($0 ~ /enabled:/) {
        sub(/^[^:]+:[[:space:]]*/, "")
        gsub(/#.*/, "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        print
        exit
      }
    }
  ' "$FEATURES_CONFIG_FILE" 2>/dev/null)

  case "$value" in
    false|False|FALSE|no|No|NO|0) return 1 ;;
    *) return 0 ;;
  esac
}

show_help() {
  cat << 'EOF'
performance-regression.sh - 性能回退检测

用法:
  performance-regression.sh --baseline <baseline.json> --current <current.json>

选项:
  --baseline <file>          基线报告
  --current <file>           当前报告
  --enable-all-features      忽略功能开关配置，强制启用所有功能
  --help                     显示帮助
EOF
}

validate_json() {
  local file="$1"
  if [[ -z "$file" || ! -f "$file" ]]; then
    log_fail "file not found: $file"
    return 1
  fi
  if ! jq empty "$file" >/dev/null 2>&1; then
    log_fail "invalid json: $file"
    return 1
  fi
  return 0
}

main() {
  local baseline=""
  local current=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --baseline)
        baseline="$2"
        shift 2
        ;;
      --current)
        current="$2"
        shift 2
        ;;
      --enable-all-features)
        DEVBOOKS_ENABLE_ALL_FEATURES=1
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        shift
        ;;
    esac
  done

  if ! feature_enabled "performance_regression"; then
    log_warn "performance_regression disabled"
    exit 0
  fi

  if [[ -z "$baseline" || -z "$current" ]]; then
    log_fail "baseline/current required"
    exit 1
  fi

  validate_json "$baseline" || exit 1
  validate_json "$current" || exit 1

  local base_mrr base_p95 curr_mrr curr_p95
  base_mrr=$(jq -r '.mrr_at_10 // 0' "$baseline")
  base_p95=$(jq -r '.p95_latency_ms // 0' "$baseline")
  curr_mrr=$(jq -r '.mrr_at_10 // 0' "$current")
  curr_p95=$(jq -r '.p95_latency_ms // 0' "$current")

  local mrr_threshold p95_threshold
  mrr_threshold=$(awk -v base="$base_mrr" 'BEGIN {printf "%.6f", base * 0.95}')
  p95_threshold=$(awk -v base="$base_p95" 'BEGIN {printf "%.2f", base * 1.10}')

  local regression=false
  if awk -v curr="$curr_mrr" -v thr="$mrr_threshold" 'BEGIN {exit !(curr < thr)}'; then
    regression=true
  fi
  if awk -v curr="$curr_p95" -v thr="$p95_threshold" 'BEGIN {exit !(curr > thr)}'; then
    regression=true
  fi

  if [[ "$regression" == "true" ]]; then
    log_fail "performance regression detected"
    exit 1
  fi

  log_info "no regression detected"
}

main "$@"
