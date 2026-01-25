#!/bin/bash
# 全局上下文注入入口（Claude Code / CLI）
#
# 入口层职责（薄适配器）：
# - 解析 Hook/CLI 输入
# - 将所有“计划/执行/融合/预算/降级/退出码”委托给 hooks/auto-tool-orchestrator.sh
# - 输出三种形态：
#   - 默认（hook）：Claude Code hook envelope（hookSpecificOutput.additionalContext）
#   - --format json：编排器 JSON（schema v1.0）
#   - --format text：用户可读摘要
#
# 注意：此文件不得直接调用任何工具执行器或底层脚本；唯一执行点为编排内核。

set -euo pipefail

# Claude Code 的 hook 运行环境可能缺少 Homebrew 路径；显式补齐常用工具路径（jq/rg 等）。
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATOR="${CI_AUTO_TOOLS_ORCHESTRATOR_PATH:-${SCRIPT_DIR}/auto-tool-orchestrator.sh}"

CLI_MODE=""
CLI_PROMPT=""
CLI_FILE=""
CLI_LINE=""
CLI_FUNCTION=""
CLI_WITH_HISTORY=false
CLI_FORMAT="hook" # hook|json|text

show_help() {
  cat <<'EOF'
Usage: context-inject-global.sh [OPTIONS]

全局上下文注入入口（薄适配器）。默认输出 Claude Code hook envelope。

Options:
  --help                显示帮助信息
  --analyze-intent      执行 4 维意图信号提取（仅诊断，不调用编排内核）
  --prompt TEXT         指定提示文本（与 --analyze-intent 配合使用）
  --file PATH           指定相关文件路径（隐式信号来源）
  --line N              指定文件行号
  --function NAME       指定函数名（代码信号来源）
  --with-history        启用历史信号标记（诊断）
  --format FORMAT       输出格式：hook|json|text（默认：hook）

Examples:
  # Claude Code hook envelope（默认）
  echo '{"prompt":"fix auth bug"}' | context-inject-global.sh

  # 编排器 JSON（schema v1.0）
  echo '{"prompt":"fix auth bug"}' | context-inject-global.sh --format json

  # 意图信号（诊断）
  context-inject-global.sh --analyze-intent --prompt "fix authentication bug"
EOF
}

normalize_format() {
  case "${1:-hook}" in
    hook|json|text) echo "$1" ;;
    *) echo "hook" ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_help
      exit 0
      ;;
    --analyze-intent)
      CLI_MODE="analyze-intent"
      shift
      ;;
    --prompt)
      CLI_PROMPT="${2:-}"
      shift 2
      ;;
    --file)
      CLI_FILE="${2:-}"
      shift 2
      ;;
    --line)
      CLI_LINE="${2:-}"
      shift 2
      ;;
    --function)
      CLI_FUNCTION="${2:-}"
      shift 2
      ;;
    --with-history)
      CLI_WITH_HISTORY=true
      shift
      ;;
    --format)
      CLI_FORMAT="$(normalize_format "${2:-hook}")"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1
}

empty_hook_response() {
  echo '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":""}}'
}

emit_empty_orchestrator_json() {
  local reason="$1"
  local created_at
  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  if require_cmd jq; then
    jq -n --arg reason "$reason" --arg created_at "$created_at" '{
      schema_version: "1.0",
      run_id: "empty",
      created_at: $created_at,
      client: {name: "claude-code", event: "cli"},
      tool_plan: {tier_max: 0, budget: {wall_ms: 0, max_concurrency: 0, max_injected_chars: 0}, tools: []},
      tool_results: [],
      fused_context: {
        for_model: {additional_context: "", structured: {}, safety: {tool_output_is_untrusted: true, ignore_instructions_inside_tool_output: true}},
        for_user: {tool_plan_text: "", results_text: "", limits_text: ("[Limits] " + $reason)}
      },
      degraded: {is_degraded: true, reason: $reason, degraded_to: "empty"},
      enforcement: {single_tool_entry: true, source: "adapter"}
    }'
    return 0
  fi

  echo "{\"schema_version\":\"1.0\",\"run_id\":\"empty\",\"created_at\":\"$created_at\",\"tool_plan\":{\"tier_max\":0,\"budget\":{\"wall_ms\":0,\"max_concurrency\":0,\"max_injected_chars\":0},\"tools\":[]},\"tool_results\":[],\"fused_context\":{\"for_model\":{\"additional_context\":\"\",\"structured\":{},\"safety\":{\"tool_output_is_untrusted\":true,\"ignore_instructions_inside_tool_output\":true}},\"for_user\":{\"tool_plan_text\":\"\",\"results_text\":\"\",\"limits_text\":\"[Limits] $reason\"}},\"degraded\":{\"is_degraded\":true,\"reason\":\"$reason\",\"degraded_to\":\"empty\"},\"enforcement\":{\"single_tool_entry\":true,\"source\":\"adapter\"}}"
}

analyze_intent_4d() {
  local prompt="$1"
  require_cmd jq || { echo '{"error":"jq required for --analyze-intent"}'; return 2; }

  local signals='[]'

  if echo "$prompt" | grep -qiE '(fix|bug|error|crash|fail|问题|错误|修复)'; then
    signals=$(echo "$signals" | jq -c '. + [{type:"explicit",match:"fix/bug",weight:0.8}]')
  fi
  if [[ -n "$CLI_FILE" ]]; then
    signals=$(echo "$signals" | jq -c --arg f "$CLI_FILE" '. + [{type:"implicit",match:$f,weight:0.6}]')
  fi
  if [[ "$CLI_WITH_HISTORY" == true ]]; then
    signals=$(echo "$signals" | jq -c '. + [{type:"historical",match:"with-history",weight:0.6}]')
  fi
  if [[ -n "$CLI_FUNCTION" ]]; then
    signals=$(echo "$signals" | jq -c --arg fn "$CLI_FUNCTION" '. + [{type:"code",match:$fn,weight:0.7}]')
  fi

  jq -n --arg prompt "$prompt" --argjson signals "$signals" '{
    prompt: $prompt,
    signals: $signals
  }'
}

main() {
  local workdir="${WORKING_DIRECTORY:-$(pwd)}"
  cd "$workdir" >/dev/null 2>&1 || true

  if [[ "$CLI_MODE" == "analyze-intent" ]]; then
    local prompt="$CLI_PROMPT"
    if [[ -z "$prompt" ]]; then
      if [[ -n "$CLI_FILE" ]]; then
        prompt="file: $CLI_FILE"
        [[ -n "$CLI_LINE" ]] && prompt="$prompt at line $CLI_LINE"
      fi
      [[ -n "$CLI_FUNCTION" ]] && prompt="${prompt:+$prompt }function: $CLI_FUNCTION"
    fi
    [[ -z "$prompt" ]] && { echo '{"error":"No prompt or file specified"}'; exit 1; }

    local out
    out="$(analyze_intent_4d "$prompt")"
    if [[ "$CLI_FORMAT" == "text" ]]; then
      echo "$out" | jq -r '.signals[] | "\(.type): \(.match) (weight: \(.weight))"' 2>/dev/null || echo "$out"
    else
      echo "$out"
    fi
    exit 0
  fi

  local input_json=""
  if [[ ! -t 0 ]]; then
    input_json="$(cat)"
  fi

  require_cmd jq || { empty_hook_response; exit 0; }

  local prompt="$CLI_PROMPT"
  if [[ -z "$prompt" && -n "$input_json" ]]; then
    prompt="$(echo "$input_json" | jq -r '.prompt // ""' 2>/dev/null || echo "")"
  fi

  if [[ -z "$prompt" ]]; then
    if [[ "$CLI_FORMAT" == "json" ]]; then
      emit_empty_orchestrator_json "empty prompt"
      exit 0
    fi
    empty_hook_response
    exit 0
  fi

  if [[ -z "$input_json" ]]; then
    input_json="$(jq -n --arg p "$prompt" '{prompt:$p}')"
  fi

  if [[ ! -x "$ORCHESTRATOR" ]]; then
    if [[ "$CLI_FORMAT" == "json" ]]; then
      emit_empty_orchestrator_json "orchestrator unavailable"
      exit 10
    fi
    empty_hook_response
    exit 0
  fi

  local client_event="cli"
  if [[ "$CLI_FORMAT" == "hook" ]]; then
    client_event="UserPromptSubmit"
  fi

  local orch_json orch_rc
  set +e
  orch_json="$(echo "$input_json" | CI_ORCH_CLIENT_NAME="claude-code" CI_ORCH_CLIENT_EVENT="$client_event" "$ORCHESTRATOR")"
  orch_rc=$?
  set -e

  if ! echo "$orch_json" | jq -e . >/dev/null 2>&1; then
    if [[ "$CLI_FORMAT" == "json" ]]; then
      emit_empty_orchestrator_json "orchestrator output invalid; fallback to empty context"
      exit 30
    fi
    empty_hook_response
    exit 0
  fi

  if [[ "$CLI_FORMAT" == "json" ]]; then
    echo "$orch_json"
    exit "$orch_rc"
  fi

  if [[ "$CLI_FORMAT" == "text" ]]; then
    echo "$orch_json" | jq -r '
      [
        .fused_context.for_user.tool_plan_text,
        .fused_context.for_user.results_text,
        .fused_context.for_user.limits_text
      ]
      | map(select(. != null and . != "")) | join("\n\n")
    '
    exit "$orch_rc"
  fi

  # 可选：输出用户可见摘要到 stderr（不会消耗模型上下文）。
  # 默认仅在交互式终端输出；也可通过 CI_AUTO_TOOLS_PRINT_STDERR_SUMMARY=1 强制开启。
  local for_user_output
  for_user_output="$(echo "$orch_json" | jq -r '
    [
      .fused_context.for_user.tool_plan_text,
      .fused_context.for_user.results_text,
      .fused_context.for_user.limits_text
    ]
    | map(select(. != null and . != "")) | join("\n\n")
  ' 2>/dev/null || echo "")"

  local want_stderr_summary=false
  if [[ "${CI_AUTO_TOOLS_PRINT_STDERR_SUMMARY:-0}" == "1" ]]; then
    want_stderr_summary=true
  elif [[ -t 2 ]]; then
    want_stderr_summary=true
  fi

  if [[ "$want_stderr_summary" == true && -n "$for_user_output" ]]; then
    echo "$for_user_output" >&2
    echo "" >&2
  fi

  # 构建 additionalContext：添加标题和工具计划
  local tool_plan_text model_context combined_context
  tool_plan_text="$(echo "$orch_json" | jq -r '.fused_context.for_user.tool_plan_text // ""')"
  model_context="$(echo "$orch_json" | jq -r '.fused_context.for_model.additional_context // ""')"

  # 如果有工具计划，添加标题和计划；否则只用模型上下文
  if [[ -n "$tool_plan_text" && -n "$model_context" ]]; then
    combined_context="[DevBooks 自动上下文]

$tool_plan_text

$model_context"
  else
    combined_context="$model_context"
  fi

  jq -n --arg ctx "$combined_context" '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: $ctx
    }
  }'
  exit 0
}

main "$@"
