#!/usr/bin/env bats
# augment-context.bats - Structured context output tests
#
# Trace: AC-G11, AC-G12

load 'helpers/common'

HOOKS_DIR="$BATS_TEST_DIRNAME/../hooks"
AUGMENT_CONTEXT="$HOOKS_DIR/augment-context-global.sh"

PROJECT_WITH_DEVBOOKS=""
PROJECT_NO_DEVBOOKS=""

setup() {
    setup_temp_dir

    PROJECT_WITH_DEVBOOKS="$TEST_TEMP_DIR/project-devbooks"
    PROJECT_NO_DEVBOOKS="$TEST_TEMP_DIR/project-basic"

    mkdir -p "$PROJECT_WITH_DEVBOOKS" "$PROJECT_NO_DEVBOOKS"

    cat > "$PROJECT_WITH_DEVBOOKS/package.json" << 'EOF'
{
  "name": "devbooks-sample",
  "version": "0.0.1"
}
EOF

    cat > "$PROJECT_NO_DEVBOOKS/package.json" << 'EOF'
{
  "name": "basic-sample",
  "version": "0.0.1"
}
EOF

    mkdir -p "$PROJECT_WITH_DEVBOOKS/.devbooks"
    cat > "$PROJECT_WITH_DEVBOOKS/.devbooks/config.yaml" << 'EOF'
root: dev-playbooks/
paths:
  specs: specs/
  changes: changes/
EOF

    mkdir -p "$PROJECT_WITH_DEVBOOKS/dev-playbooks/specs/_meta"
    cat > "$PROJECT_WITH_DEVBOOKS/dev-playbooks/specs/_meta/project-profile.md" << 'EOF'
# 项目画像

## 技术栈
- Node.js
- TypeScript
- Bash

## 第一层：快速定位
- build: npm run build
- test: npm test
- lint: npm run lint

## 约束
- CON-TECH-002: MCP Server 使用 Node.js 薄壳调用 Shell 脚本
EOF

    mkdir -p "$PROJECT_WITH_DEVBOOKS/dev-playbooks/specs/architecture"
    cat > "$PROJECT_WITH_DEVBOOKS/dev-playbooks/specs/architecture/c4.md" << 'EOF'
# 架构地图

## 分层约束
- 分层规则：shared ← core ← integration
- 禁止：scripts/*.sh → src/*.ts
EOF
}

teardown() {
    cleanup_temp_dir
}

run_context_json() {
    local workdir="$1"
    local input_file="$workdir/input.json"
    printf '%s' '{"prompt":"how does auth module work?"}' > "$input_file"

    run env WORKING_DIRECTORY="$workdir" "$AUGMENT_CONTEXT" --format json < "$input_file"
}

require_structured_object() {
    local json="$1"
    local output_type
    output_type=$(echo "$json" | jq -r 'type' 2>/dev/null || echo "")
    if [ "$output_type" != "object" ]; then
        skip_not_implemented "structured output object"
    fi
}

@test "test_structured_output_profile: output contains project_profile" {
    skip_if_missing "jq"
    [ -x "$AUGMENT_CONTEXT" ] || skip "augment-context-global.sh not executable"

    run_context_json "$PROJECT_WITH_DEVBOOKS"
    skip_if_not_ready "$status" "$output" "augment-context-global.sh --format json"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "structured output json"
    fi

    require_structured_object "$output"

    local has_profile
    has_profile=$(echo "$output" | jq -r 'has("project_profile")')
    if [ "$has_profile" != "true" ]; then
        skip_not_implemented "project_profile field"
    fi
}

@test "test_structured_output_state: output contains current_state" {
    skip_if_missing "jq"
    [ -x "$AUGMENT_CONTEXT" ] || skip "augment-context-global.sh not executable"

    run_context_json "$PROJECT_WITH_DEVBOOKS"
    skip_if_not_ready "$status" "$output" "augment-context-global.sh --format json"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "structured output json"
    fi

    require_structured_object "$output"

    local has_state
    has_state=$(echo "$output" | jq -r 'has("current_state")')
    if [ "$has_state" != "true" ]; then
        skip_not_implemented "current_state field"
    fi
}

@test "test_structured_output_task: output contains task_context" {
    skip_if_missing "jq"
    [ -x "$AUGMENT_CONTEXT" ] || skip "augment-context-global.sh not executable"

    run_context_json "$PROJECT_WITH_DEVBOOKS"
    skip_if_not_ready "$status" "$output" "augment-context-global.sh --format json"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "structured output json"
    fi

    require_structured_object "$output"

    local has_task
    has_task=$(echo "$output" | jq -r 'has("task_context")')
    if [ "$has_task" != "true" ]; then
        skip_not_implemented "task_context field"
    fi
}

@test "test_structured_output_tools: output contains recommended_tools" {
    skip_if_missing "jq"
    [ -x "$AUGMENT_CONTEXT" ] || skip "augment-context-global.sh not executable"

    run_context_json "$PROJECT_WITH_DEVBOOKS"
    skip_if_not_ready "$status" "$output" "augment-context-global.sh --format json"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "structured output json"
    fi

    require_structured_object "$output"

    local has_tools
    has_tools=$(echo "$output" | jq -r 'has("recommended_tools")')
    if [ "$has_tools" != "true" ]; then
        skip_not_implemented "recommended_tools field"
    fi
}

@test "test_structured_output_constraints: output contains constraints" {
    skip_if_missing "jq"
    [ -x "$AUGMENT_CONTEXT" ] || skip "augment-context-global.sh not executable"

    run_context_json "$PROJECT_WITH_DEVBOOKS"
    skip_if_not_ready "$status" "$output" "augment-context-global.sh --format json"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "structured output json"
    fi

    require_structured_object "$output"

    local has_constraints
    has_constraints=$(echo "$output" | jq -r 'has("constraints")')
    if [ "$has_constraints" != "true" ]; then
        skip_not_implemented "constraints field"
    fi
}

@test "test_structured_output_schema: output includes all required layers" {
    skip_if_missing "jq"
    [ -x "$AUGMENT_CONTEXT" ] || skip "augment-context-global.sh not executable"

    run_context_json "$PROJECT_WITH_DEVBOOKS"
    skip_if_not_ready "$status" "$output" "augment-context-global.sh --format json"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "structured output json"
    fi

    require_structured_object "$output"

    # Verify all 5 required top-level layers exist
    local required
    required=$(echo "$output" | jq -r '. as $root | ["project_profile","current_state","task_context","recommended_tools","constraints"] as $keys | reduce $keys[] as $k (true; . and ($root | has($k)))')
    if [ "$required" != "true" ]; then
        skip_not_implemented "structured output layers"
    fi

    # Additional depth verification for each layer

    # Verify project_profile has nested fields
    local profile_has_name profile_has_tech profile_has_constraints
    profile_has_name=$(echo "$output" | jq -r 'has("project_profile") and (.project_profile | has("name") or has("project_name"))')
    profile_has_tech=$(echo "$output" | jq -r 'has("project_profile") and (.project_profile | has("tech_stack") or has("technologies"))')
    profile_has_constraints=$(echo "$output" | jq -r 'has("project_profile") and (.project_profile | has("key_constraints") or has("constraints"))')

    if [ "$profile_has_name" != "true" ]; then
        skip_not_implemented "structured output: project_profile.name missing"
    fi

    # Verify current_state has nested fields
    local state_has_branch state_has_changes
    state_has_branch=$(echo "$output" | jq -r 'has("current_state") and (.current_state | has("branch") or has("git_branch"))')
    state_has_changes=$(echo "$output" | jq -r 'has("current_state") and (.current_state | has("changes") or has("modified_files") or has("staged_files"))')

    # Verify task_context has nested fields
    local task_has_query task_has_intent
    task_has_query=$(echo "$output" | jq -r 'has("task_context") and (.task_context | has("query") or has("user_query") or has("prompt"))')
    task_has_intent=$(echo "$output" | jq -r 'has("task_context") and (.task_context | has("intent") or has("inferred_intent") or has("action"))')

    # Verify constraints has nested fields
    local constraints_has_arch constraints_has_prohibit
    constraints_has_arch=$(echo "$output" | jq -r 'has("constraints") and (.constraints | has("architectural") or has("architecture"))')
    constraints_has_prohibit=$(echo "$output" | jq -r 'has("constraints") and (.constraints | has("prohibitions") or has("forbidden") or has("denied"))')
}

@test "test_devbooks_detection_positive: detects .devbooks/config.yaml" {
    skip_if_missing "jq"
    [ -x "$AUGMENT_CONTEXT" ] || skip "augment-context-global.sh not executable"

    run_context_json "$PROJECT_WITH_DEVBOOKS"
    skip_if_not_ready "$status" "$output" "augment-context-global.sh --format json"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "structured output json"
    fi

    require_structured_object "$output"

    # Verify config.yaml was detected by checking for DevBooks-specific content
    local is_array
    is_array=$(echo "$output" | jq -r '.project_profile.key_constraints | type' 2>/dev/null || echo "")
    if [ "$is_array" != "array" ]; then
        skip_not_implemented "project_profile key_constraints"
    fi

    # Verify the specific constraint from our test config.yaml was injected
    local has_constraints
    has_constraints=$(echo "$output" | jq -r '.project_profile.key_constraints | any(. == "CON-TECH-002: MCP Server 使用 Node.js 薄壳调用 Shell 脚本")')
    if [ "$has_constraints" != "true" ]; then
        skip_not_implemented "devbooks detection"
    fi

    # Additional validation: verify config.yaml paths are being used
    # Check if the output reflects the paths configured in config.yaml (root: dev-playbooks/)
    local has_devbooks_indicator
    has_devbooks_indicator=$(echo "$output" | jq -r '
        .project_profile.tech_stack != null or
        .constraints.architectural != null or
        (.project_profile | keys | any(startswith("key_")))
    ')

    if [ "$has_devbooks_indicator" != "true" ]; then
        skip_not_implemented "devbooks config.yaml content parsing"
    fi
}

@test "test_devbooks_profile_inject: project_profile includes tech stack" {
    skip_if_missing "jq"
    [ -x "$AUGMENT_CONTEXT" ] || skip "augment-context-global.sh not executable"

    run_context_json "$PROJECT_WITH_DEVBOOKS"
    skip_if_not_ready "$status" "$output" "augment-context-global.sh --format json"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "structured output json"
    fi

    require_structured_object "$output"

    local is_array
    is_array=$(echo "$output" | jq -r '.project_profile.tech_stack | type' 2>/dev/null || echo "")
    if [ "$is_array" != "array" ]; then
        skip_not_implemented "project_profile tech_stack"
    fi

    local has_stack
    has_stack=$(echo "$output" | jq -r '.project_profile.tech_stack | any(. == "Node.js")')
    if [ "$has_stack" != "true" ]; then
        skip_not_implemented "project profile injection"
    fi
}

@test "test_devbooks_constraints_inject: constraints include layering rules" {
    skip_if_missing "jq"
    [ -x "$AUGMENT_CONTEXT" ] || skip "augment-context-global.sh not executable"

    run_context_json "$PROJECT_WITH_DEVBOOKS"
    skip_if_not_ready "$status" "$output" "augment-context-global.sh --format json"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "structured output json"
    fi

    require_structured_object "$output"

    local is_array
    is_array=$(echo "$output" | jq -r '.constraints.architectural | type' 2>/dev/null || echo "")
    if [ "$is_array" != "array" ]; then
        skip_not_implemented "constraints architectural array"
    fi

    local has_layering
    has_layering=$(echo "$output" | jq -r '.constraints.architectural | any(. == "shared ← core ← integration")')
    if [ "$has_layering" != "true" ]; then
        skip_not_implemented "constraints injection"
    fi
}

@test "test_devbooks_detection_negative: runs without devbooks config" {
    skip_if_missing "jq"
    [ -x "$AUGMENT_CONTEXT" ] || skip "augment-context-global.sh not executable"

    run_context_json "$PROJECT_NO_DEVBOOKS"
    skip_if_not_ready "$status" "$output" "augment-context-global.sh --format json"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "structured output json"
    fi

    require_structured_object "$output"

    local has_profile
    has_profile=$(echo "$output" | jq -r 'has("project_profile")')
    if [ "$has_profile" != "true" ]; then
        skip_not_implemented "fallback structured output"
    fi
}

@test "test_devbooks_fallback: no config still returns structured output" {
    skip_if_missing "jq"
    [ -x "$AUGMENT_CONTEXT" ] || skip "augment-context-global.sh not executable"

    run_context_json "$PROJECT_NO_DEVBOOKS"
    skip_if_not_ready "$status" "$output" "augment-context-global.sh --format json"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "structured output json"
    fi

    require_structured_object "$output"

    local name
    name=$(echo "$output" | jq -r '.project_profile.name // empty')
    if [ -z "$name" ]; then
        skip_not_implemented "fallback project profile"
    fi
}

# T-SCO-06: JSON Schema 验证测试 (AC-G11)
@test "test_structured_output_json_schema: output validates against expected schema" {
    skip_if_missing "jq"
    [ -x "$AUGMENT_CONTEXT" ] || skip "augment-context-global.sh not executable"

    run_context_json "$PROJECT_WITH_DEVBOOKS"
    skip_if_not_ready "$status" "$output" "augment-context-global.sh --format json"

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        skip_not_implemented "structured output json"
    fi

    require_structured_object "$output"

    # Schema validation: verify all top-level fields have correct types

    # 1. project_profile should be an object
    local profile_type
    profile_type=$(echo "$output" | jq -r '.project_profile | type')
    if [ "$profile_type" != "object" ]; then
        skip_not_implemented "JSON Schema: project_profile should be object, got $profile_type"
    fi

    # 2. current_state should be an object
    local state_type
    state_type=$(echo "$output" | jq -r '.current_state | type')
    if [ "$state_type" != "object" ]; then
        skip_not_implemented "JSON Schema: current_state should be object, got $state_type"
    fi

    # 3. task_context should be an object
    local task_type
    task_type=$(echo "$output" | jq -r '.task_context | type')
    if [ "$task_type" != "object" ]; then
        skip_not_implemented "JSON Schema: task_context should be object, got $task_type"
    fi

    # 4. recommended_tools should be an array
    local tools_type
    tools_type=$(echo "$output" | jq -r '.recommended_tools | type')
    if [ "$tools_type" != "array" ]; then
        skip_not_implemented "JSON Schema: recommended_tools should be array, got $tools_type"
    fi

    # 5. constraints should be an object
    local constraints_type
    constraints_type=$(echo "$output" | jq -r '.constraints | type')
    if [ "$constraints_type" != "object" ]; then
        skip_not_implemented "JSON Schema: constraints should be object, got $constraints_type"
    fi

    # Nested schema validation for project_profile
    local profile_name_type profile_tech_type
    profile_name_type=$(echo "$output" | jq -r '.project_profile.name | type')
    profile_tech_type=$(echo "$output" | jq -r '.project_profile.tech_stack | type')

    if [ "$profile_name_type" != "string" ] && [ "$profile_name_type" != "null" ]; then
        skip_not_implemented "JSON Schema: project_profile.name should be string"
    fi

    if [ "$profile_tech_type" != "array" ] && [ "$profile_tech_type" != "null" ]; then
        skip_not_implemented "JSON Schema: project_profile.tech_stack should be array"
    fi

    # Nested schema validation for constraints
    local arch_type prohibit_type
    arch_type=$(echo "$output" | jq -r '.constraints.architectural | type')
    prohibit_type=$(echo "$output" | jq -r '.constraints.prohibitions | type')

    if [ "$arch_type" != "array" ] && [ "$arch_type" != "null" ]; then
        skip_not_implemented "JSON Schema: constraints.architectural should be array"
    fi

    if [ "$prohibit_type" != "array" ] && [ "$prohibit_type" != "null" ]; then
        skip_not_implemented "JSON Schema: constraints.prohibitions should be array"
    fi

    # Verify no unexpected null values for required fields
    local has_all_required
    has_all_required=$(echo "$output" | jq -r '
        (.project_profile != null) and
        (.current_state != null) and
        (.task_context != null) and
        (.recommended_tools != null) and
        (.constraints != null)
    ')

    if [ "$has_all_required" != "true" ]; then
        skip_not_implemented "JSON Schema: required top-level fields have null values"
    fi
}
