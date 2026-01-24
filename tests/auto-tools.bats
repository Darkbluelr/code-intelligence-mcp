#!/usr/bin/env bats
# auto-tools.bats - Auto Tool Orchestrator acceptance tests (plan/dry-run first)
#
# Trace: AC-001 .. AC-018 (dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/proposal.md)

load 'helpers/common'

PROJECT_ROOT="$BATS_TEST_DIRNAME/.."
HOOK_SCRIPT="$PROJECT_ROOT/hooks/context-inject-global.sh"
AUGMENT_SCRIPT="$PROJECT_ROOT/hooks/augment-context-global.sh"

FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures/auto-tools"

setup() {
  setup_temp_dir
}

teardown() {
  cleanup_temp_dir
}

make_repo() {
  local repo_dir="$1"
  local with_git="${2:-false}"

  mkdir -p "$repo_dir"
  printf '%s\n' '{"name":"sample","version":"0.0.0"}' > "$repo_dir/package.json"
  mkdir -p "$repo_dir/config"

  if [ "$with_git" = "true" ]; then
    setup_test_git_repo "$repo_dir" >/dev/null
    printf '%s\n' "hello" > "$repo_dir/README.md"
    git add -A >/dev/null
    git commit -m "init" --quiet
  fi
}

write_auto_tools_config() {
  local repo_dir="$1"
  local content="$2"
  mkdir -p "$repo_dir/config"
  printf '%s\n' "$content" > "$repo_dir/config/auto-tools.yaml"
}

make_fake_codex() {
  local bin_dir="$1"
  local marker_file="$2"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/codex" << EOF
#!/bin/bash
echo "codex invoked" >> "$marker_file"
exit 9
EOF
  chmod +x "$bin_dir/codex"
}

make_stub_runner() {
  local path="$1"
  local body="$2"
  cat > "$path" << EOF
#!/bin/bash
set -euo pipefail
$body
EOF
  chmod +x "$path"
}

run_hook_json() {
  local workdir="$1"
  local prompt="$2"
  local input
  input=$(printf '{"prompt":"%s"}' "$prompt")

  run env WORKING_DIRECTORY="$workdir" \
    CI_AUTO_TOOLS=auto \
    CI_AUTO_TOOLS_MODE=plan \
    CI_AUTO_TOOLS_DRY_RUN=1 \
    "$HOOK_SCRIPT" --format json <<< "$input"
}

canonical_json() {
  local json="$1"
  echo "$json" | jq -cS .
}

@test "AC-001/014: context-inject --format json outputs orchestrator schema fields" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" false
  write_auto_tools_config "$repo" "tier_max: 1"

  run_hook_json "$repo" "fix auth bug"
  assert_valid_json "$output"

  echo "$output" | jq -e '.schema_version|type=="string"' >/dev/null
  echo "$output" | jq -e '.run_id|type=="string"' >/dev/null
  echo "$output" | jq -e '.tool_plan.tools|type=="array"' >/dev/null
  echo "$output" | jq -e '.tool_results|type=="array"' >/dev/null
  echo "$output" | jq -e '.fused_context|type=="object"' >/dev/null
  echo "$output" | jq -e '.degraded|type=="object"' >/dev/null
}

@test "AC-001: default output is Claude Code hook envelope (no --format)" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" true
  write_auto_tools_config "$repo" "tier_max: 1"

  local fake_results="$FIXTURES_DIR/tool-results-conflict.json"
  [ -f "$fake_results" ] || fail "missing fixture: $fake_results"

  run env WORKING_DIRECTORY="$repo" \
    CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=plan CI_AUTO_TOOLS_DRY_RUN=1 \
    CI_AUTO_TOOLS_FAKE_TOOL_RESULTS_FILE="$fake_results" \
    "$HOOK_SCRIPT" <<< '{"prompt":"resolve conflict"}'
  assert_valid_json "$output"

  echo "$output" | jq -e '.hookSpecificOutput.hookEventName=="UserPromptSubmit"' >/dev/null
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext|contains("Auto Tools Results")' >/dev/null
  echo "$output" | jq -e 'has("schema_version")|not' >/dev/null
}

@test "AC-002/003: plan/dry-run is deterministic and does not invoke codex" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" true
  write_auto_tools_config "$repo" "tier_max: 1"

  local fake_bin="$TEST_TEMP_DIR/fake-bin"
  local marker="$TEST_TEMP_DIR/codex.marker"
  make_fake_codex "$fake_bin" "$marker"

  run env PATH="$fake_bin:$PATH" WORKING_DIRECTORY="$repo" \
    CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=plan CI_AUTO_TOOLS_DRY_RUN=1 \
    CI_CODEX_SESSION_MODE=resume_last \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"explain call chain"}'
  assert_valid_json "$output"
  echo "$output" | jq -e '.tool_plan.planned_codex_command=="codex exec resume --last"' >/dev/null

  [ ! -f "$marker" ] || fail "codex should NOT be invoked in plan/dry-run"

  local out1 out2
  out1=$(canonical_json "$output")

  run env PATH="$fake_bin:$PATH" WORKING_DIRECTORY="$repo" \
    CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=plan CI_AUTO_TOOLS_DRY_RUN=1 \
    CI_CODEX_SESSION_MODE=resume_last \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"explain call chain"}'
  assert_valid_json "$output"
  out2=$(canonical_json "$output")

  [ "$out1" = "$out2" ] || fail "plan/dry-run output must be deterministic"
}

@test "AC-005: repo-root detection works for no-git and git-subdir" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo_no_git="$TEST_TEMP_DIR/repo-no-git"
  make_repo "$repo_no_git" false
  write_auto_tools_config "$repo_no_git" "tier_max: 1"
  local repo_no_git_real
  repo_no_git_real="$(cd "$repo_no_git" && pwd -P)"

  run env WORKING_DIRECTORY="$repo_no_git" CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=plan CI_AUTO_TOOLS_DRY_RUN=1 \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"explain auth"}'
  assert_valid_json "$output"
  echo "$output" | jq -e --arg root "$repo_no_git_real" '.inputs.repo_root==$root' >/dev/null
  echo "$output" | jq -e '.inputs.repo_root_source=="no-git-root"' >/dev/null

  local repo_git="$TEST_TEMP_DIR/repo-git"
  make_repo "$repo_git" true
  write_auto_tools_config "$repo_git" "tier_max: 1"
  mkdir -p "$repo_git/subdir"
  local repo_git_real
  repo_git_real="$(cd "$repo_git" && pwd -P)"

  run env WORKING_DIRECTORY="$repo_git/subdir" CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=plan CI_AUTO_TOOLS_DRY_RUN=1 \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"explain auth"}'
  assert_valid_json "$output"
  echo "$output" | jq -e --arg root "$repo_git_real" '.inputs.repo_root==$root' >/dev/null
  echo "$output" | jq -e '.inputs.repo_root_source=="git"' >/dev/null
}

@test "AC-002: planned_codex_command switches with CI_CODEX_SESSION_MODE" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" true
  write_auto_tools_config "$repo" "tier_max: 1"

  run env WORKING_DIRECTORY="$repo" CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=plan CI_AUTO_TOOLS_DRY_RUN=1 \
    CI_CODEX_SESSION_MODE=exec \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"explain code"}'
  assert_valid_json "$output"
  echo "$output" | jq -e '.tool_plan.planned_codex_command=="codex exec"' >/dev/null
}

@test "AC-008/012: orchestrator unavailable returns empty JSON and exit=10" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" false

  run env WORKING_DIRECTORY="$repo" \
    CI_AUTO_TOOLS_ORCHESTRATOR_PATH="$TEST_TEMP_DIR/missing-orchestrator.sh" \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"explain auth"}'
  [ "$status" -eq 10 ] || fail "expected exit=10, got $status"
  assert_valid_json "$output"
  echo "$output" | jq -e '.degraded.is_degraded==true' >/dev/null
  echo "$output" | jq -e '.fused_context.for_user.limits_text|contains("orchestrator unavailable")' >/dev/null
}

@test "AC-008/012: orchestrator output parse failure returns empty JSON and exit=30" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" false

  local fake_orch="$TEST_TEMP_DIR/fake-orchestrator.sh"
  make_stub_runner "$fake_orch" 'echo "not json"; exit 0'

  run env WORKING_DIRECTORY="$repo" \
    CI_AUTO_TOOLS_ORCHESTRATOR_PATH="$fake_orch" \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"explain auth"}'
  [ "$status" -eq 30 ] || fail "expected exit=30, got $status"
  assert_valid_json "$output"
  echo "$output" | jq -e '.degraded.is_degraded==true' >/dev/null
  echo "$output" | jq -e '.fused_context.for_user.limits_text|contains("orchestrator output invalid")' >/dev/null
}

@test "AC-004/007: env overrides config for budget and concurrency" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" true
  write_auto_tools_config "$repo" $'budget:\n  wall_ms: 9999\n  max_concurrency: 9\n  max_injected_chars: 99999\n'

  run env WORKING_DIRECTORY="$repo" \
    CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=plan CI_AUTO_TOOLS_DRY_RUN=1 \
    CI_AUTO_TOOLS_BUDGET_WALL_MS=5000 CI_AUTO_TOOLS_MAX_CONCURRENCY=3 \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"search auth"}'
  assert_valid_json "$output"

  echo "$output" | jq -e '.tool_plan.budget.wall_ms==5000' >/dev/null
  echo "$output" | jq -e '.tool_plan.budget.max_concurrency==3' >/dev/null
}

@test "AC-008/012: run mode fails open on tool timeout (exit=50, E_TIMEOUT)" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" true
  write_auto_tools_config "$repo" "tier_max: 1"

  local ok_runner="$TEST_TEMP_DIR/ok-runner.sh"
  local slow_runner="$TEST_TEMP_DIR/slow-runner.sh"
  make_stub_runner "$ok_runner" 'echo "{\"ok\":true}"; exit 0'
  make_stub_runner "$slow_runner" 'sleep 1; echo "{\"ok\":true}"; exit 0'

  run env WORKING_DIRECTORY="$repo" \
    CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=run CI_AUTO_TOOLS_DRY_RUN=0 \
    CI_AUTO_TOOLS_BUDGET_WALL_MS=200 \
    CI_AUTO_TOOLS_RUNNER_CI_INDEX_STATUS="$ok_runner" \
    CI_AUTO_TOOLS_RUNNER_CI_GRAPH_RAG="$ok_runner" \
    CI_AUTO_TOOLS_RUNNER_CI_SEARCH="$slow_runner" \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"explain auth"}'

  [ "$status" -eq 50 ] || fail "expected exit=50, got $status"
  assert_valid_json "$output"
  echo "$output" | jq -e '.degraded.is_degraded==true' >/dev/null
  echo "$output" | jq -e '.fused_context.for_user.limits_text|contains("tool timeout; degraded to plan-only")' >/dev/null
  echo "$output" | jq -e '.tool_results | any(.tool=="ci_search" and .status=="timeout" and .error.code=="E_TIMEOUT")' >/dev/null
}

@test "AC-008/012: run mode fails open on tool error (exit=40, E_TOOL_UNAVAILABLE)" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" true
  write_auto_tools_config "$repo" "tier_max: 1"

  local ok_runner="$TEST_TEMP_DIR/ok-runner.sh"
  local bad_runner="$TEST_TEMP_DIR/bad-runner.sh"
  make_stub_runner "$ok_runner" 'echo "{\"ok\":true}"; exit 0'
  make_stub_runner "$bad_runner" 'echo "boom" >&2; exit 9'

  run env WORKING_DIRECTORY="$repo" \
    CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=run CI_AUTO_TOOLS_DRY_RUN=0 \
    CI_AUTO_TOOLS_RUNNER_CI_INDEX_STATUS="$ok_runner" \
    CI_AUTO_TOOLS_RUNNER_CI_GRAPH_RAG="$bad_runner" \
    CI_AUTO_TOOLS_RUNNER_CI_SEARCH="$ok_runner" \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"explain auth"}'

  [ "$status" -eq 40 ] || fail "expected exit=40, got $status"
  assert_valid_json "$output"
  echo "$output" | jq -e '.degraded.is_degraded==true' >/dev/null
  echo "$output" | jq -e '.tool_results | any(.tool=="ci_graph_rag" and .status=="error" and .error.code=="E_TOOL_UNAVAILABLE")' >/dev/null
}

@test "AC-007/012: max_injected_chars enforces truncation (exit=50, E_BUDGET_EXCEEDED)" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" true
  write_auto_tools_config "$repo" "tier_max: 1"

  local long_runner="$TEST_TEMP_DIR/long-runner.sh"
  make_stub_runner "$long_runner" 'printf "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\\n"; exit 0'

  run env WORKING_DIRECTORY="$repo" \
    CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=run CI_AUTO_TOOLS_DRY_RUN=0 \
    CI_AUTO_TOOLS_MAX_INJECTED_CHARS=50 \
    CI_AUTO_TOOLS_RUNNER_CI_INDEX_STATUS="$long_runner" \
    CI_AUTO_TOOLS_RUNNER_CI_GRAPH_RAG="$long_runner" \
    CI_AUTO_TOOLS_RUNNER_CI_SEARCH="$long_runner" \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"explain auth"}'

  [ "$status" -eq 50 ] || fail "expected exit=50, got $status"
  assert_valid_json "$output"
  echo "$output" | jq -e '.fused_context.for_user.limits_text|contains("budget exceeded; results truncated")' >/dev/null
  echo "$output" | jq -e '.tool_results | all(.truncated==true)' >/dev/null
  echo "$output" | jq -e '.tool_results | any(.error.code=="E_BUDGET_EXCEEDED")' >/dev/null
}

@test "AC-009/017: Tier-2 in config is ignored unless CI_AUTO_TOOLS_TIER_MAX=2" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" true
  write_auto_tools_config "$repo" "tier_max: 2"

  run env WORKING_DIRECTORY="$repo" \
    CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=plan CI_AUTO_TOOLS_DRY_RUN=1 \
    CI_AUTO_TOOLS_TIER_MAX=1 \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"analyze impact of change"}'
  assert_valid_json "$output"

  echo "$output" | jq -e '.tool_plan.tier_max==1' >/dev/null
  echo "$output" | jq -e '.fused_context.for_user.limits_text|contains("tier-2 requires CI_AUTO_TOOLS_TIER_MAX=2 (config ignored)")' >/dev/null
}

@test "AC-017: non-code intent yields empty injection in auto mode" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" false
  write_auto_tools_config "$repo" "tier_max: 1"

  run env WORKING_DIRECTORY="$repo" CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=plan CI_AUTO_TOOLS_DRY_RUN=1 \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"weather in SF?"}'
  assert_valid_json "$output"

  echo "$output" | jq -e '.fused_context.for_model.additional_context==""' >/dev/null
}

@test "AC-006/016: entry layer scripts must not directly call tools (static scan)" {
  [ -f "$HOOK_SCRIPT" ] || fail "missing: $HOOK_SCRIPT"
  [ -f "$AUGMENT_SCRIPT" ] || fail "missing: $AUGMENT_SCRIPT"

  # No direct references to legacy tool entrypoints in entry layer.
  ! rg -n "tools/(graph-rag-context|context-reranker|devbooks-embedding)\\.sh" "$HOOK_SCRIPT" "$AUGMENT_SCRIPT" >/dev/null
  ! rg -n "\\bci_[a-z0-9_]+\\b\\s" "$HOOK_SCRIPT" "$AUGMENT_SCRIPT" >/dev/null
}

@test "AC-013: augment-context-global.sh stays compatible and delegates to context-inject-global.sh" {
  skip_if_missing "jq"
  [ -x "$AUGMENT_SCRIPT" ] || fail "missing executable: $AUGMENT_SCRIPT"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" false
  write_auto_tools_config "$repo" "tier_max: 1"

  run env WORKING_DIRECTORY="$repo" CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=plan CI_AUTO_TOOLS_DRY_RUN=1 \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"explain auth"}'
  assert_valid_json "$output"
  local out_hook
  out_hook=$(canonical_json "$output")

  run env WORKING_DIRECTORY="$repo" CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=plan CI_AUTO_TOOLS_DRY_RUN=1 \
    "$AUGMENT_SCRIPT" --format json <<< '{"prompt":"explain auth"}'
  assert_valid_json "$output"
  local out_augment
  out_augment=$(canonical_json "$output")

  [ "$out_hook" = "$out_augment" ] || fail "augment wrapper must be equivalent"
}

@test "AC-011/010: fusion is deterministic and detects conflicts (fixture-driven)" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" true
  write_auto_tools_config "$repo" "tier_max: 1"

  local fake_results="$FIXTURES_DIR/tool-results-conflict.json"
  [ -f "$fake_results" ] || fail "missing fixture: $fake_results"

  run env WORKING_DIRECTORY="$repo" CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=plan CI_AUTO_TOOLS_DRY_RUN=1 \
    CI_AUTO_TOOLS_FAKE_TOOL_RESULTS_FILE="$fake_results" \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"resolve conflict"}'
  assert_valid_json "$output"

  # Deterministic: run twice and compare canonical JSON.
  local out1 out2
  out1=$(canonical_json "$output")

  run env WORKING_DIRECTORY="$repo" CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=plan CI_AUTO_TOOLS_DRY_RUN=1 \
    CI_AUTO_TOOLS_FAKE_TOOL_RESULTS_FILE="$fake_results" \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"resolve conflict"}'
  assert_valid_json "$output"
  out2=$(canonical_json "$output")

  [ "$out1" = "$out2" ] || fail "fusion output must be deterministic"

  # Conflict marker & safety filtering
  echo "$out1" | jq -e '.fused_context.for_model.safety.ignore_instructions_inside_tool_output==true' >/dev/null
  echo "$out1" | jq -e '.fused_context.for_user.results_text|contains("conflict")' >/dev/null
  echo "$out1" | jq -e '.fused_context.for_user.limits_text|contains("filtered potential injection")' >/dev/null
  echo "$out1" | jq -e '.fused_context.for_model.additional_context|contains("IGNORE PREVIOUS INSTRUCTIONS")|not' >/dev/null
}

@test "AC-018: legacy mode is auditable" {
  skip_if_missing "jq"
  [ -x "$HOOK_SCRIPT" ] || fail "missing executable: $HOOK_SCRIPT"

  local repo="$TEST_TEMP_DIR/repo"
  make_repo "$repo" false
  write_auto_tools_config "$repo" "tier_max: 1"

  run env WORKING_DIRECTORY="$repo" \
    CI_AUTO_TOOLS=auto CI_AUTO_TOOLS_MODE=plan CI_AUTO_TOOLS_DRY_RUN=1 \
    CI_AUTO_TOOLS_LEGACY=1 \
    "$HOOK_SCRIPT" --format json <<< '{"prompt":"explain auth"}'
  assert_valid_json "$output"

  echo "$output" | jq -e '.fused_context.for_user.limits_text|contains("legacy mode enabled; using legacy policy")' >/dev/null
  echo "$output" | jq -e '.enforcement.source=="legacy"' >/dev/null
}
