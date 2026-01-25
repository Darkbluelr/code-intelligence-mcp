#!/bin/bash
# drift-detector.sh - Architecture drift detector
#
# 输出:
#   JSON（compare/diff/report）或快照文件（snapshot）
#
# 依赖:
#   jq

set -euo pipefail

# RM-002: trap 清理机制，确保资源正确释放
_cleanup() {
  # 清理临时文件（如果有）
  if [[ -n "${_TEMP_FILES:-}" ]]; then
    for f in $_TEMP_FILES; do
      [[ -f "$f" ]] && rm -f "$f" 2>/dev/null || true
    done
  fi
  # 清理快照锁文件（如果有）
  if [[ -n "${_SNAPSHOT_LOCK:-}" ]] && [[ -f "$_SNAPSHOT_LOCK" ]]; then
    rm -f "$_SNAPSHOT_LOCK" 2>/dev/null || true
  fi
}
trap _cleanup EXIT INT TERM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/common.sh"
if [ -f "$COMMON_LIB" ]; then
  LOG_PREFIX="DriftDetector"
  # shellcheck source=common.sh
  source "$COMMON_LIB"
else
  log_info()  { echo "[DriftDetector] $1" >&2; }
  log_warn()  { echo "[DriftDetector] $1" >&2; }
  log_error() { echo "[DriftDetector] $1" >&2; }
fi

if declare -f check_dependencies &>/dev/null; then
  check_dependencies jq || exit 2
else
  command -v jq &>/dev/null || { log_error "缺少依赖: jq"; exit 2; }
fi

MODE=""
BASELINE=""
CURRENT=""
SNAPSHOT_DIR=""
SNAPSHOT_OUTPUT=""
RULES_FILE=""
RULES_TARGET=""
REPORT_DIR=""
REPORT_PERIOD="weekly"
C4_FILE=""
CODE_ROOT=""

show_help() {
  cat << 'EOF'
Architecture Drift Detector

用法:
  drift-detector.sh --compare <baseline.json> <current.json>
  drift-detector.sh --diff <baseline.json> <current.json>
  drift-detector.sh --snapshot <project-dir> --output <snapshot.json>
  drift-detector.sh --rules <arch-rules.yaml> <project-dir>
  drift-detector.sh --report <snapshots-dir> --period weekly
  drift-detector.sh --c4 <c4.md> --code <project-dir>
  drift-detector.sh --parse-c4 <c4.md>
  drift-detector.sh --scan-code <project-dir>
  drift-detector.sh --enable-all-features --compare <baseline.json> <current.json>
  drift-detector.sh --help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --compare)
        MODE="compare"
        if [[ $# -ge 3 ]]; then
          BASELINE="$2"
          CURRENT="$3"
          shift 3
        else
          BASELINE="${2:-}"
          CURRENT="${3:-}"
          shift $#
        fi
        ;;
      --diff)
        MODE="diff"
        if [[ $# -ge 3 ]]; then
          BASELINE="$2"
          CURRENT="$3"
          shift 3
        else
          BASELINE="${2:-}"
          CURRENT="${3:-}"
          shift $#
        fi
        ;;
      --snapshot)
        MODE="snapshot"
        SNAPSHOT_DIR="$2"
        shift 2
        ;;
      --output)
        SNAPSHOT_OUTPUT="$2"
        shift 2
        ;;
      --rules)
        MODE="rules"
        RULES_FILE="$2"
        RULES_TARGET="$3"
        shift 3
        ;;
      --report)
        MODE="report"
        REPORT_DIR="$2"
        shift 2
        ;;
      --c4)
        C4_FILE="$2"
        shift 2
        ;;
      --code)
        CODE_ROOT="$2"
        shift 2
        ;;
      --parse-c4)
        MODE="parse-c4"
        C4_FILE="$2"
        shift 2
        ;;
      --scan-code)
        MODE="scan-code"
        CODE_ROOT="$2"
        shift 2
        ;;
      --period)
        REPORT_PERIOD="$2"
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
        log_error "未知参数: $1"
        show_help
        exit 1
        ;;
    esac
  done

  if [ -z "$MODE" ] && [ -n "$C4_FILE" ] && [ -n "$CODE_ROOT" ]; then
    MODE="c4-drift"
  fi
}

trim_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  echo "$value"
}

clean_cell() {
  local value="$1"
  value=$(echo "$value" | sed -E 's/`//g; s/\\*//g')
  trim_value "$value"
}

parse_c4_components() {
  local file="$1"
  local components='[]'
  local in_table=false
  local seen=false

  while IFS= read -r line; do
    if [[ "$line" =~ ^###\ Container\ Inventory ]]; then
      in_table=true
      continue
    fi

    if [ "$in_table" = true ]; then
      if [[ "$line" =~ ^\| ]]; then
        if [[ "$line" =~ ^\|[[:space:]]*Container[[:space:]]*\| ]] || [[ "$line" =~ ^\|[-[:space:]]*\| ]]; then
          continue
        fi

        seen=true
        IFS='|' read -r _ col1 col2 col3 col4 col5 _ <<< "$line"
        local name path type responsibility tech
        name=$(clean_cell "$col1")
        path=$(clean_cell "$col2")
        type=$(clean_cell "$col3")
        responsibility=$(clean_cell "$col4")
        tech=$(clean_cell "$col5")

        if [ -z "$name" ] || [ "$name" = "Container" ]; then
          continue
        fi

        components=$(echo "$components" | jq \
          --arg name "$name" \
          --arg path "$path" \
          --arg type "$type" \
          --arg responsibility "$responsibility" \
          --arg tech "$tech" \
          '. + [{name: $name, path: $path, type: $type, responsibility: $responsibility, tech: $tech}]')
      else
        if [ "$seen" = true ]; then
          break
        fi
      fi
    fi
  done < "$file"

  echo "$components"
}

parse_c4_dependencies() {
  local file="$1"
  local dependencies='[]'
  local in_table=false
  local seen=false

  while IFS= read -r line; do
    if [[ "$line" =~ ^\|[[:space:]]*Component[[:space:]]*\| ]] && [[ "$line" =~ \|[[:space:]]*依赖[[:space:]]*\| ]]; then
      in_table=true
      seen=false
      continue
    fi

    if [ "$in_table" = true ]; then
      if [[ "$line" =~ ^\| ]]; then
        if [[ "$line" =~ ^\|[-[:space:]]*\| ]]; then
          continue
        fi

        seen=true
        IFS='|' read -r _ col1 _ col3 _ <<< "$line"
        local component deps_raw
        component=$(clean_cell "$col1")
        deps_raw=$(clean_cell "$col3")

        if [ -z "$component" ] || [ "$component" = "Component" ]; then
          continue
        fi

        local dep_list
        dep_list=$(echo "$deps_raw" | sed -E 's/[，、;+]/,/g')

        IFS=',' read -r -a dep_items <<< "$dep_list"
        local dep
        for dep in "${dep_items[@]}"; do
          dep=$(clean_cell "$dep")
          case "$dep" in
            ""|"-"|"无"|"None"|"N/A")
              continue
              ;;
          esac

          dependencies=$(echo "$dependencies" | jq \
            --arg from "$component" \
            --arg to "$dep" \
            '. + [{from: $from, to: $to}]')
        done
      else
        if [ "$seen" = true ]; then
          in_table=false
        fi
      fi
    fi
  done < "$file"

  echo "$dependencies"
}

parse_c4() {
  local file="$1"
  local components
  local dependencies

  components=$(parse_c4_components "$file")
  dependencies=$(parse_c4_dependencies "$file")

  jq -n \
    --argjson components "$components" \
    --argjson dependencies "$dependencies" \
    '{components: $components, dependencies: $dependencies}'
}

resolve_path() {
  local base="$1"
  local rel="$2"

  if command -v realpath &>/dev/null; then
    realpath "${base}/${rel}" 2>/dev/null || echo "${base}/${rel}"
    return
  fi

  if command -v python3 &>/dev/null; then
    python3 - "$base" "$rel" << 'PY'
import os
import sys
print(os.path.normpath(os.path.join(sys.argv[1], sys.argv[2])))
PY
    return
  fi

  if command -v node &>/dev/null; then
    node -e 'const path=require("path"); console.log(path.resolve(process.argv[1], process.argv[2]));' "$base" "$rel"
    return
  fi

  echo "${base}/${rel}"
}

resolve_import_target() {
  local base_dir="$1"
  local import_path="$2"

  local resolved
  resolved=$(resolve_path "$base_dir" "$import_path")

  local candidates=(
    "$resolved"
    "${resolved}.ts"
    "${resolved}.tsx"
    "${resolved}.js"
    "${resolved}.jsx"
    "${resolved}.mjs"
    "${resolved}.cjs"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done

  if [ -d "$resolved" ]; then
    local index_candidate
    for index_candidate in \
      "${resolved}/index.ts" \
      "${resolved}/index.tsx" \
      "${resolved}/index.js" \
      "${resolved}/index.jsx" \
      "${resolved}/index.mjs" \
      "${resolved}/index.cjs"; do
      if [ -f "$index_candidate" ]; then
        echo "$index_candidate"
        return
      fi
    done
  fi

  echo "$resolved"
}

scan_code_components() {
  local root="$1"
  local components='[]'
  local dependencies='[]'

  local files=()
  local search_dirs=("$root/scripts" "$root/src" "$root/hooks")
  local dir

  for dir in "${search_dirs[@]}"; do
    if [ -d "$dir" ]; then
      while IFS= read -r -d '' file; do
        files+=("$file")
      done < <(find "$dir" -type f \( -name "*.sh" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.mjs" -o -name "*.cjs" \) -print0 2>/dev/null)
    fi
  done

  local file
  for file in "${files[@]}"; do
    local rel_path
    rel_path="${file#"$root"/}"

    local type="module"
    case "$file" in
      *.sh) type="script" ;;
      *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) type="module" ;;
    esac

    components=$(echo "$components" | jq \
      --arg path "$rel_path" \
      --arg name "$(basename "$rel_path")" \
      --arg type "$type" \
      '. + [{name: $name, path: $path, type: $type}]')

    local rg_cmd=""
    for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
      [ -x "$p" ] && { rg_cmd="$p"; break; }
    done
    [ -z "$rg_cmd" ] && rg_cmd=$(command -v rg 2>/dev/null || true)

    if [[ "$file" == *.sh ]]; then
      local source_lines
      if [ -n "$rg_cmd" ]; then
        source_lines=$("$rg_cmd" -n "(^|[[:space:]])(source|\\.)[[:space:]]+['\"][^'\"]+['\"]" "$file" 2>/dev/null || true)
      else
        source_lines=$(grep -nE "(^|[[:space:]])(source|\\.)[[:space:]]+['\"][^'\"]+['\"]" "$file" 2>/dev/null || true)
      fi

      local line
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local dep_path
        dep_path=$(echo "$line" | sed -E "s/.*(source|\\.)[[:space:]]+['\"]([^'\"]+)['\"].*/\\2/")
        if [[ "$dep_path" == /* ]]; then
          continue
        fi

        local resolved
        resolved=$(resolve_import_target "$(dirname "$file")" "$dep_path")
        local rel_dep="$dep_path"
        if [[ "$resolved" == "$root"* ]]; then
          rel_dep="${resolved#"$root"/}"
        fi

        dependencies=$(echo "$dependencies" | jq \
          --arg from "$rel_path" \
          --arg to "$rel_dep" \
          --arg dtype "source" \
          '. + [{from: $from, to: $to, type: $dtype}]')
      done <<< "$source_lines"
    else
      local import_lines
      if [ -n "$rg_cmd" ]; then
        import_lines=$("$rg_cmd" -n "from[[:space:]]+['\"][^'\"]+['\"]|require\\(['\"][^'\"]+['\"]\\)" "$file" 2>/dev/null || true)
      else
        import_lines=$(grep -nE "from[[:space:]]+['\"][^'\"]+['\"]|require\\(['\"][^'\"]+['\"]\\)" "$file" 2>/dev/null || true)
      fi

      local line
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local import_path
        import_path=$(echo "$line" | sed -E "s/.*from[[:space:]]+['\"]([^'\"]+)['\"].*/\\1/;s/.*require\\(['\"]([^'\"]+)['\"]\\).*/\\1/")

        if [[ "$import_path" != .* ]]; then
          continue
        fi

        local resolved
        resolved=$(resolve_import_target "$(dirname "$file")" "$import_path")
        local rel_dep="$import_path"
        if [[ "$resolved" == "$root"* ]]; then
          rel_dep="${resolved#"$root"/}"
        fi

        dependencies=$(echo "$dependencies" | jq \
          --arg from "$rel_path" \
          --arg to "$rel_dep" \
          --arg dtype "import" \
          '. + [{from: $from, to: $to, type: $dtype}]')
      done <<< "$import_lines"
    fi
  done

  jq -n \
    --argjson components "$components" \
    --argjson dependencies "$dependencies" \
    '{components: $components, dependencies: $dependencies}'
}

# R-003: 拆分辅助函数 - 比较组件集合差异
# 参数: $1=c4_components, $2=code_components
# 设置全局变量: _CMP_ADDED, _CMP_REMOVED, _CMP_SCORE, _CMP_CHANGES, _CMP_RECOMMENDATIONS
_compare_component_sets() {
  local c4_components="$1"
  local code_components="$2"
  local changes="$3"
  local recommendations="$4"
  local score="$5"

  local added removed
  added=$(jq -n --argjson code "$code_components" --argjson c4 "$c4_components" \
    '$code | map(select(. as $item | ($c4 | index($item) | not)))')
  removed=$(jq -n --argjson code "$code_components" --argjson c4 "$c4_components" \
    '$c4 | map(select(. as $item | ($code | index($item) | not)))')

  local add_count remove_count
  add_count=$(echo "$added" | jq 'length')
  remove_count=$(echo "$removed" | jq 'length')

  if [ "$add_count" -gt 0 ]; then
    local item
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      local change
      change=$(jq -n --arg type "component_added" --arg component "$item" '{type: $type, component: $component}')
      changes=$(add_change "$changes" "$change")
    done <<< "$(echo "$added" | jq -r '.[]')"
    score=$((score + add_count * 15))
    recommendations=$(add_recommendation "$recommendations" "补充 C4 中缺失的新增组件")
  fi

  if [ "$remove_count" -gt 0 ]; then
    local item
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      local change
      change=$(jq -n --arg type "component_removed" --arg component "$item" '{type: $type, component: $component}')
      changes=$(add_change "$changes" "$change")
    done <<< "$(echo "$removed" | jq -r '.[]')"
    score=$((score + remove_count * 20))
    recommendations=$(add_recommendation "$recommendations" "清理 C4 中已删除的组件记录")
  fi

  _CMP_CHANGES="$changes"
  _CMP_RECOMMENDATIONS="$recommendations"
  _CMP_SCORE="$score"
}

# R-003: 拆分辅助函数 - 比较组件职责变更
_compare_component_responsibilities() {
  local c4_json="$1"
  local code_json="$2"
  local changes="$3"
  local recommendations="$4"
  local score="$5"

  local c4_entries code_entries modified
  c4_entries=$(echo "$c4_json" | jq '[.components[]? | {name: (.name // ""), path: (.path // ""), base: ((.path // .name) | split("/") | last)}]')
  code_entries=$(echo "$code_json" | jq '[.components[]? | {path: .path, base: (.path | split("/") | last)}]')
  modified=$(jq -n --argjson c4 "$c4_entries" --argjson code "$code_entries" '
    $c4
    | map(select(.base != "" and (.base as $b | ($code | map(select(.base == $b)) | length) > 0) and (.path as $p | ($code | map(select(.base == $b) | .path) | index($p) | not))))
    | map({base: .base, expected: .path})')

  local mod_count
  mod_count=$(echo "$modified" | jq 'length')
  if [ "$mod_count" -gt 0 ]; then
    local item
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      local change
      change=$(jq -n \
        --arg type "component_responsibility_changed" \
        --arg base "$(echo "$item" | jq -r '.base')" \
        --arg expected "$(echo "$item" | jq -r '.expected')" \
        '{type: $type, component: $base, expected_path: $expected}')
      changes=$(add_change "$changes" "$change")
    done <<< "$(echo "$modified" | jq -c '.[]')"
    score=$((score + mod_count * 10))
    recommendations=$(add_recommendation "$recommendations" "同步组件职责与路径变更到 C4")
  fi

  _CMP_CHANGES="$changes"
  _CMP_RECOMMENDATIONS="$recommendations"
  _CMP_SCORE="$score"
}

# R-003: 拆分辅助函数 - 比较依赖关系变更
_compare_dependencies() {
  local c4_json="$1"
  local code_json="$2"
  local changes="$3"
  local recommendations="$4"
  local score="$5"

  local c4_deps code_deps new_deps
  c4_deps=$(echo "$c4_json" | jq '[.dependencies[]? | "\(.from)->\(.to)"] | unique')
  code_deps=$(echo "$code_json" | jq '[.dependencies[]? | "\(.from)->\(.to)"] | unique')
  new_deps=$(jq -n --argjson code "$code_deps" --argjson c4 "$c4_deps" \
    '$code | map(select(. as $item | ($c4 | index($item) | not)))')

  local dep_count
  dep_count=$(echo "$new_deps" | jq 'length')
  if [ "$dep_count" -gt 0 ]; then
    local item
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      local from to
      from="${item%%->*}"
      to="${item#*->}"
      local change
      change=$(jq -n --arg type "dependency_added" --arg from "$from" --arg to "$to" '{type: $type, from: $from, to: $to}')
      changes=$(add_change "$changes" "$change")
    done <<< "$(echo "$new_deps" | jq -r '.[]')"
    score=$((score + dep_count * 5))
    recommendations=$(add_recommendation "$recommendations" "补充 C4 中新增依赖关系")
  fi

  _CMP_CHANGES="$changes"
  _CMP_RECOMMENDATIONS="$recommendations"
  _CMP_SCORE="$score"
}

compare_c4_with_code() {
  local c4_json="$1"
  local code_json="$2"

  local changes='[]'
  local recommendations='[]'
  local score=0

  local c4_components code_components
  c4_components=$(echo "$c4_json" | jq '[.components[]? | (.path // .name) | select(. != "")] | unique')
  code_components=$(echo "$code_json" | jq '[.components[]? | .path | select(. != "")] | unique')

  # R-003: 使用辅助函数比较组件集合
  _compare_component_sets "$c4_components" "$code_components" "$changes" "$recommendations" "$score"
  changes="$_CMP_CHANGES"
  recommendations="$_CMP_RECOMMENDATIONS"
  score="$_CMP_SCORE"

  # R-003: 使用辅助函数比较组件职责
  _compare_component_responsibilities "$c4_json" "$code_json" "$changes" "$recommendations" "$score"
  changes="$_CMP_CHANGES"
  recommendations="$_CMP_RECOMMENDATIONS"
  score="$_CMP_SCORE"

  # R-003: 使用辅助函数比较依赖关系
  _compare_dependencies "$c4_json" "$code_json" "$changes" "$recommendations" "$score"
  changes="$_CMP_CHANGES"
  recommendations="$_CMP_RECOMMENDATIONS"
  score="$_CMP_SCORE"

  local severity="low"
  if [ "$score" -ge 50 ]; then
    severity="high"
  elif [ "$score" -ge 20 ]; then
    severity="medium"
  fi

  local drift_detected=false
  if [ "$score" -gt 0 ]; then
    drift_detected=true
  fi

  jq -n \
    --argjson drift_detected "$drift_detected" \
    --argjson score "$score" \
    --arg severity "$severity" \
    --argjson changes "$changes" \
    --argjson recommendations "$recommendations" \
    '{
      drift_detected: $drift_detected,
      score: $score,
      severity: $severity,
      changes: $changes,
      recommendations: $recommendations
    }'
}

read_metric() {
  local file="$1"
  local key="$2"
  jq -r ".metrics.${key} // 0" "$file" 2>/dev/null
}

calc_percent_change() {
  local base="$1"
  local current="$2"
  if [ "$base" -le 0 ]; then
    echo 0
    return
  fi
  awk -v b="$base" -v c="$current" 'BEGIN {printf "%.2f", ((c-b)/b)*100}'
}

add_change() {
  local changes="$1"
  local change="$2"
  echo "$changes" | jq --argjson c "$change" '. + [$c]'
}

add_recommendation() {
  local recs="$1"
  local rec="$2"
  echo "$recs" | jq --arg r "$rec" '. + [$r]'
}

# R-004: 拆分辅助函数 - 比较耦合度变化
# 参数: $1=baseline, $2=current, $3=changes, $4=recommendations, $5=score
# 设置全局变量: _SNAP_CHANGES, _SNAP_RECOMMENDATIONS, _SNAP_SCORE
_snap_compare_coupling() {
  local baseline="$1"
  local current="$2"
  local changes="$3"
  local recommendations="$4"
  local score="$5"

  local base_coupling current_coupling
  base_coupling=$(read_metric "$baseline" "total_coupling")
  current_coupling=$(read_metric "$current" "total_coupling")
  local coupling_change
  coupling_change=$(calc_percent_change "$base_coupling" "$current_coupling")

  if awk -v v="$coupling_change" 'BEGIN {exit !(v>=10)}'; then
    local change
    change=$(jq -n \
      --arg type "coupling_increase" \
      --argjson from "$base_coupling" \
      --argjson to "$current_coupling" \
      --argjson change_percent "$coupling_change" \
      '{type: $type, from: $from, to: $to, change_percent: $change_percent}')
    changes=$(add_change "$changes" "$change")
    recommendations=$(add_recommendation "$recommendations" "审查模块耦合增长来源")
    score=$((score + 15))
  fi

  _SNAP_CHANGES="$changes"
  _SNAP_RECOMMENDATIONS="$recommendations"
  _SNAP_SCORE="$score"
}

# R-004: 拆分辅助函数 - 比较依赖违规和边界清晰度
_snap_compare_violations_and_boundary() {
  local baseline="$1"
  local current="$2"
  local changes="$3"
  local recommendations="$4"
  local score="$5"

  # 依赖违规
  local base_violations current_violations
  base_violations=$(read_metric "$baseline" "dependency_violations")
  current_violations=$(read_metric "$current" "dependency_violations")
  if [ "$current_violations" -gt "$base_violations" ]; then
    local change
    change=$(jq -n \
      --arg type "dependency_violation_increase" \
      --argjson from "$base_violations" \
      --argjson to "$current_violations" \
      '{type: $type, from: $from, to: $to, delta: ($to - $from)}')
    changes=$(add_change "$changes" "$change")
    recommendations=$(add_recommendation "$recommendations" "检查跨层依赖与违规调用")
    score=$((score + 10))
  fi

  # 边界清晰度
  local base_boundary current_boundary
  base_boundary=$(read_metric "$baseline" "boundary_clarity")
  current_boundary=$(read_metric "$current" "boundary_clarity")
  if awk -v b="$base_boundary" -v c="$current_boundary" 'BEGIN {exit !((b-c)>=0.10)}'; then
    local change
    change=$(jq -n \
      --arg type "boundary_blur" \
      --argjson from "$base_boundary" \
      --argjson to "$current_boundary" \
      --argjson drop "$(awk -v b="$base_boundary" -v c="$current_boundary" 'BEGIN {printf "%.2f", (b-c)}')" \
      '{type: $type, from: $from, to: $to, drop: $drop}')
    changes=$(add_change "$changes" "$change")
    recommendations=$(add_recommendation "$recommendations" "强化模块边界与依赖方向")
    score=$((score + 10))
  fi

  _SNAP_CHANGES="$changes"
  _SNAP_RECOMMENDATIONS="$recommendations"
  _SNAP_SCORE="$score"
}

# R-004: 拆分辅助函数 - 比较循环依赖和热点文件
_snap_compare_cycles_and_hotspots() {
  local baseline="$1"
  local current="$2"
  local changes="$3"
  local recommendations="$4"
  local score="$5"

  # 循环依赖
  local base_cycles current_cycles
  base_cycles=$(read_metric "$baseline" "cyclic_dependencies")
  current_cycles=$(read_metric "$current" "cyclic_dependencies")
  if [ "$current_cycles" -gt "$base_cycles" ]; then
    local change
    change=$(jq -n \
      --arg type "cyclic_dependency_increase" \
      --argjson from "$base_cycles" \
      --argjson to "$current_cycles" \
      '{type: $type, from: $from, to: $to, delta: ($to - $from)}')
    changes=$(add_change "$changes" "$change")
    recommendations=$(add_recommendation "$recommendations" "移除新增循环依赖")
    score=$((score + 10))
  fi

  # 热点文件
  local hotspot_paths
  hotspot_paths=$(jq -r '.hotspot_files[]?.path' "$baseline" 2>/dev/null || true)
  if [ -n "$hotspot_paths" ]; then
    local path
    while IFS= read -r path; do
      [ -z "$path" ] && continue
      local base_value current_value
      base_value=$(jq -r --arg p "$path" '.hotspot_files[]? | select(.path==$p) | .coupling // 0' "$baseline" | head -1)
      current_value=$(jq -r --arg p "$path" '.hotspot_files[]? | select(.path==$p) | .coupling // 0' "$current" | head -1)
      if [ -z "$current_value" ]; then
        current_value=0
      fi
      if [ "$current_value" -gt "$base_value" ]; then
        local delta=$((current_value - base_value))
        if [ "$delta" -ge 10 ]; then
          local change
          change=$(jq -n \
            --arg type "hotspot_coupling_increase" \
            --arg file "$path" \
            --argjson from "$base_value" \
            --argjson to "$current_value" \
            '{type: $type, file: $file, from: $from, to: $to, delta: ($to - $from)}')
          changes=$(add_change "$changes" "$change")
          recommendations=$(add_recommendation "$recommendations" "聚焦热点文件的重构与隔离")
          score=$((score + 5))
        fi
      fi
    done <<< "$hotspot_paths"
  fi

  _SNAP_CHANGES="$changes"
  _SNAP_RECOMMENDATIONS="$recommendations"
  _SNAP_SCORE="$score"
}

compare_snapshots() {
  local baseline="$1"
  local current="$2"

  local changes='[]'
  local recommendations='[]'
  local score=0

  # R-004: 使用辅助函数比较耦合度
  _snap_compare_coupling "$baseline" "$current" "$changes" "$recommendations" "$score"
  changes="$_SNAP_CHANGES"
  recommendations="$_SNAP_RECOMMENDATIONS"
  score="$_SNAP_SCORE"

  # R-004: 使用辅助函数比较违规和边界
  _snap_compare_violations_and_boundary "$baseline" "$current" "$changes" "$recommendations" "$score"
  changes="$_SNAP_CHANGES"
  recommendations="$_SNAP_RECOMMENDATIONS"
  score="$_SNAP_SCORE"

  # R-004: 使用辅助函数比较循环依赖和热点
  _snap_compare_cycles_and_hotspots "$baseline" "$current" "$changes" "$recommendations" "$score"
  changes="$_SNAP_CHANGES"
  recommendations="$_SNAP_RECOMMENDATIONS"
  score="$_SNAP_SCORE"

  local severity="low"
  if [ "$score" -ge 40 ]; then
    severity="high"
  elif [ "$score" -ge 20 ]; then
    severity="medium"
  fi

  local drift_detected=false
  local change_count
  change_count=$(echo "$changes" | jq 'length')
  if [ "$change_count" -gt 0 ]; then
    drift_detected=true
  fi

  jq -n \
    --argjson drift_detected "$drift_detected" \
    --argjson score "$score" \
    --arg severity "$severity" \
    --argjson changes "$changes" \
    --argjson recommendations "$recommendations" \
    '{
      drift_detected: $drift_detected,
      score: $score,
      severity: $severity,
      changes: $changes,
      recommendations: $recommendations
    }'
}

detect_dependency_violations() {
  local rules_file="$1"
  local target="$2"

  local rules=()
  local from="" to="" allow="true" reason=""

  while IFS= read -r line; do
    case "$line" in
      *"- from:"*)
        if [ -n "$from" ] && [ -n "$to" ]; then
          rules+=("${from}|${to}|${allow}|${reason}")
        fi
        from=$(echo "$line" | sed -E 's/.*from:[[:space:]]*//;s/"//g')
        to=""
        allow="true"
        reason=""
        ;;
      *"- "*)
        if [ -n "$from" ] && [ -n "$to" ]; then
          rules+=("${from}|${to}|${allow}|${reason}")
        fi
        from=""
        to=""
        allow="true"
        reason=""
        ;;
      *"from:"*)
        from=$(echo "$line" | sed -E 's/.*from:[[:space:]]*//;s/"//g')
        ;;
      *"to:"*)
        to=$(echo "$line" | sed -E 's/.*to:[[:space:]]*//;s/"//g')
        ;;
      *"allow:"*)
        allow=$(echo "$line" | sed -E 's/.*allow:[[:space:]]*//;s/"//g')
        ;;
      *"reason:"*)
        reason=$(echo "$line" | sed -E 's/.*reason:[[:space:]]*//;s/"//g')
        ;;
    esac
  done < "$rules_file"

  if [ -n "$from" ] && [ -n "$to" ]; then
    rules+=("${from}|${to}|${allow}|${reason}")
  fi

  local violations='[]'
  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done
  [ -z "$rg_cmd" ] && rg_cmd=$(command -v rg 2>/dev/null || true)

  local files
  files=$(find "$target" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) 2>/dev/null)

  local file
  for file in $files; do
    local rel_file="${file#"$target"/}"
    local file_module
    file_module=$(echo "$rel_file" | cut -d'/' -f1)

    local imports=""
    if [ -n "$rg_cmd" ]; then
      imports=$("$rg_cmd" -n "from[[:space:]]+['\"][^'\"]+['\"]|require\\(['\"][^'\"]+['\"]\\)" "$file" 2>/dev/null || true)
    else
      imports=$(grep -nE "from[[:space:]]+['\"][^'\"]+['\"]|require\\(['\"][^'\"]+['\"]\\)" "$file" 2>/dev/null || true)
    fi

    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local import_path
      import_path=$(echo "$line" | sed -E "s/.*from[[:space:]]+['\"]([^'\"]+)['\"].*/\1/;s/.*require\\(['\"]([^'\"]+)['\"]\\).*/\1/")
      if [[ "$import_path" =~ ^\./ ]]; then
        continue
      fi
      if [[ "$import_path" =~ ^\.\./ ]]; then
        local cleaned
        cleaned=$(echo "$import_path" | sed -E 's#^\.\./+##')
        local import_module
        import_module=$(echo "$cleaned" | cut -d'/' -f1)

        local rule
        for rule in "${rules[@]}"; do
          IFS='|' read -r rule_from rule_to rule_allow rule_reason <<< "$rule"
          if [ "$rule_allow" = "false" ] && [ "$rule_from" = "$file_module" ] && [ "$rule_to" = "$import_module" ]; then
            local violation
            violation=$(jq -n \
              --arg type "dependency_violation" \
              --arg from "$rule_from" \
              --arg to "$rule_to" \
              --arg file "${file#"$target"/}" \
              --arg path "$import_path" \
              --arg reason "$rule_reason" \
              '{type: $type, from: $from, to: $to, file: $file, import: $path, reason: $reason}')
            violations=$(echo "$violations" | jq --argjson v "$violation" '. + [$v]')
          fi
        done
      fi
    done <<< "$imports"
  done

  jq -n --argjson violations "$violations" '{violations: $violations}'
}

create_snapshot() {
  local target="$1"
  local output="$2"

  local rg_cmd=""
  for p in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    [ -x "$p" ] && { rg_cmd="$p"; break; }
  done
  [ -z "$rg_cmd" ] && rg_cmd=$(command -v rg 2>/dev/null || true)

  local total_coupling=0
  if [ -n "$rg_cmd" ]; then
    local rg_output
    rg_output=$("$rg_cmd" -c "from[[:space:]]+['\"][^'\"]+['\"]|require\\(['\"][^'\"]+['\"]\\)" "$target" 2>/dev/null || true)
    total_coupling=$(echo "$rg_output" | awk -F: '{sum+=$2} END {print sum+0}')
  else
    local grep_output
    grep_output=$(grep -R -cE "from[[:space:]]+['\"][^'\"]+['\"]|require\\(['\"][^'\"]+['\"]\\)" "$target" 2>/dev/null || true)
    total_coupling=$(echo "$grep_output" | awk -F: '{sum+=$2} END {print sum+0}')
  fi

  local snapshot
  snapshot=$(jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg version "1.0.0" \
    --argjson total_coupling "$total_coupling" \
    '{
      timestamp: $timestamp,
      version: $version,
      metrics: {
        total_coupling: $total_coupling,
        dependency_violations: 0,
        boundary_clarity: 0.85
      },
      module_metrics: [],
      violations: []
    }')

  if [ -n "$output" ]; then
    mkdir -p "$(dirname "$output")"
    printf '%s\n' "$snapshot" > "$output"
  fi

  echo "$snapshot"
}

generate_report() {
  local dir="$1"
  local period="$2"

  local snapshots
  snapshots=$(ls "$dir"/*.json 2>/dev/null | sort)
  if [ -z "$snapshots" ]; then
    log_error "未找到快照文件"
    exit 1
  fi

  local first last
  first=$(echo "$snapshots" | head -1)
  last=$(echo "$snapshots" | tail -1)

  local first_coupling last_coupling
  first_coupling=$(read_metric "$first" "total_coupling")
  last_coupling=$(read_metric "$last" "total_coupling")

  local trend="stable"
  if [ "$last_coupling" -gt "$first_coupling" ]; then
    trend="increasing"
  elif [ "$last_coupling" -lt "$first_coupling" ]; then
    trend="decreasing"
  fi

  jq -n \
    --arg period "$period" \
    --arg trend "$trend" \
    --argjson first "$first_coupling" \
    --argjson last "$last_coupling" \
    '{
      period: $period,
      trend: {
        coupling: $trend,
        first: $first,
        last: $last
      },
      recommendations: [
        "保持边界清晰与依赖方向约束",
        "对热点模块进行重构评估"
      ]
    }'
}

main() {
  parse_args "$@"

  if declare -f is_feature_enabled &>/dev/null; then
    if ! is_feature_enabled "drift_detector"; then
      log_warn "架构漂移检测已禁用 (features.drift_detector: false)"
      echo '{"status":"disabled","message":"drift_detector disabled"}'
      exit 0
    fi
  fi

  case "$MODE" in
    compare)
      if [ -z "$BASELINE" ] || [ -z "$CURRENT" ]; then
        log_error "compare 需要 baseline 和 current"
        exit 1
      fi
      compare_snapshots "$BASELINE" "$CURRENT"
      ;;
    diff)
      if [ -z "$BASELINE" ] || [ -z "$CURRENT" ]; then
        log_error "diff 需要 baseline 和 current"
        exit 1
      fi
      local changes
      changes=$(compare_snapshots "$BASELINE" "$CURRENT")
      jq -n \
        --argjson before "$(cat "$BASELINE")" \
        --argjson after "$(cat "$CURRENT")" \
        --argjson changes "$(echo "$changes" | jq '.changes')" \
        '{
          before: $before,
          after: $after,
          changes: $changes
        }'
      ;;
    snapshot)
      if [ -z "$SNAPSHOT_DIR" ]; then
        log_error "snapshot 需要目录"
        exit 1
      fi
      if [ -z "$SNAPSHOT_OUTPUT" ]; then
        log_error "snapshot 需要 --output"
        exit 1
      fi
      create_snapshot "$SNAPSHOT_DIR" "$SNAPSHOT_OUTPUT" >/dev/null
      ;;
    rules)
      if [ -z "$RULES_FILE" ] || [ -z "$RULES_TARGET" ]; then
        log_error "rules 需要规则文件和目录"
        exit 1
      fi
      detect_dependency_violations "$RULES_FILE" "$RULES_TARGET"
      ;;
    report)
      if [ -z "$REPORT_DIR" ]; then
        log_error "report 需要目录"
        exit 1
      fi
      generate_report "$REPORT_DIR" "$REPORT_PERIOD"
      ;;
    parse-c4)
      if [ -z "$C4_FILE" ]; then
        log_error "parse-c4 需要 C4 文件路径"
        exit 1
      fi
      parse_c4 "$C4_FILE"
      ;;
    scan-code)
      if [ -z "$CODE_ROOT" ]; then
        log_error "scan-code 需要项目目录"
        exit 1
      fi
      scan_code_components "$CODE_ROOT"
      ;;
    c4-drift)
      if [ -z "$C4_FILE" ] || [ -z "$CODE_ROOT" ]; then
        log_error "c4-drift 需要 --c4 和 --code"
        exit 1
      fi
      local c4_json code_json
      c4_json=$(parse_c4 "$C4_FILE")
      code_json=$(scan_code_components "$CODE_ROOT")
      compare_c4_with_code "$c4_json" "$code_json"
      ;;
    *)
      log_error "未指定模式"
      show_help
      exit 1
      ;;
  esac
}

main "$@"
