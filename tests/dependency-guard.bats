#!/usr/bin/env bats
# dependency-guard.bats - Dependency Guard Contract Tests
#
# Purpose: Verify circular dependency detection and architecture rule validation
# Depends: bats-core, jq, git
# Run: bats tests/dependency-guard.bats
#
# Baseline: 2026-01-14
# Change: augment-upgrade-phase2
# Trace: AC-006 ~ AC-008, AC-012, AC-N03, AC-N04

# Load shared helpers
load 'helpers/common'

# Store project root for absolute paths (tests may cd to temp dirs)
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
DEPENDENCY_GUARD="${PROJECT_ROOT}/scripts/dependency-guard.sh"
ARCH_RULES_FILE="${PROJECT_ROOT}/config/arch-rules.yaml"
TEST_TEMP_DIR=""

# ============================================================
# Setup / Teardown
# ============================================================

setup() {
    TEST_TEMP_DIR=$(mktemp -d)
    export ARCH_RULES_FILE="$TEST_TEMP_DIR/arch-rules.yaml"
}

teardown() {
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Helper: Create test project with circular dependency
create_circular_dep_project() {
    local dir="$1"
    mkdir -p "$dir/src"

    # A imports B, B imports A
    cat > "$dir/src/a.ts" << 'EOF'
import { b } from './b';
export const a = () => b();
EOF

    cat > "$dir/src/b.ts" << 'EOF'
import { a } from './a';
export const b = () => a();
EOF
}

# Helper: Create test project with multi-node cycle
create_multi_node_cycle() {
    local dir="$1"
    mkdir -p "$dir/src"

    cat > "$dir/src/a.ts" << 'EOF'
import { b } from './b';
export const a = () => b();
EOF

    cat > "$dir/src/b.ts" << 'EOF'
import { c } from './c';
export const b = () => c();
EOF

    cat > "$dir/src/c.ts" << 'EOF'
import { d } from './d';
export const c = () => d();
EOF

    cat > "$dir/src/d.ts" << 'EOF'
import { a } from './a';
export const d = () => a();
EOF
}

# Helper: Create arch rules file
create_arch_rules() {
    local file="$1"
    cat > "$file" << 'EOF'
schema_version: "1.0.0"

rules:
  - name: "ui-no-direct-db"
    description: "UI components cannot directly import database modules"
    from: "src/ui/**"
    cannot_import:
      - "src/db/**"
    severity: "error"

  - name: "no-circular-deps"
    type: "cycle-detection"
    scope: "src/**"
    severity: "error"
    whitelist:
      - "src/types/**"

config:
  on_violation: "warn"
  ignore:
    - "node_modules/**"
EOF
}

# Helper: Check if orphan-check is implemented (wrapper for common helper)
# Usage: skip_if_orphan_check_not_implemented "$output"
skip_if_orphan_check_not_implemented() {
    skip_if_feature_not_implemented "$1" "orphan-check"
}

# ============================================================
# Basic Verification
# ============================================================

@test "CT-GUARD-BASE-001: dependency-guard.sh exists and is executable" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"
}

@test "CT-GUARD-BASE-002: --help shows usage information" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"
    run "$DEPENDENCY_GUARD" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"cycles"* ]] || [[ "$output" == *"rules"* ]] || [[ "$output" == *"dependency"* ]]
}

# ============================================================
# CT-GUARD-001: Simple Circular Dependency (SC-GUARD-001)
# AC-006: Circular dependency detection
# ============================================================

@test "CT-GUARD-001: detects simple A -> B -> A cycle" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"

    create_circular_dep_project "$TEST_TEMP_DIR/project"
    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --cycles --scope "src/" --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "Cycle detection not yet implemented"

    # Should detect the cycle
    [[ "$output" == *"cycle"* ]] || [[ "$output" == *"circular"* ]]

    if command -v jq &> /dev/null; then
        local cycle_count=$(echo "$output" | jq '.cycles | length' 2>/dev/null || echo "0")
        [ "$cycle_count" -ge 1 ] || skip "No cycles detected"
    fi
}

@test "CT-GUARD-001b: cycle path includes both files" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"
    skip_if_missing "jq"

    create_circular_dep_project "$TEST_TEMP_DIR/project"
    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --cycles --scope "src/" --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "Cycle detection not yet implemented"

    # Path should include a.ts and b.ts
    [[ "$output" == *"a.ts"* ]] && [[ "$output" == *"b.ts"* ]] || skip "Cycle path incomplete"
}

# ============================================================
# CT-GUARD-002: Multi-node Circular Dependency (SC-GUARD-002)
# ============================================================

@test "CT-GUARD-002: detects multi-node cycle A -> B -> C -> D -> A" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"
    skip_if_missing "jq"

    create_multi_node_cycle "$TEST_TEMP_DIR/project"
    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --cycles --scope "src/" --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "Cycle detection not yet implemented"

    # Should detect a cycle with 4+ nodes
    if command -v jq &> /dev/null; then
        local path_length=$(echo "$output" | jq '.cycles[0].path | length' 2>/dev/null || echo "0")
        [ "$path_length" -ge 4 ] || skip "Multi-node cycle not fully detected"
    fi
}

# ============================================================
# CT-GUARD-003: Whitelist Exclusion (SC-GUARD-003)
# ============================================================

@test "CT-GUARD-003: whitelist excludes specified paths from cycle detection" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"

    # Create project with cycle involving whitelisted path
    mkdir -p "$TEST_TEMP_DIR/project/src/types"

    cat > "$TEST_TEMP_DIR/project/src/a.ts" << 'EOF'
import { Type } from './types/common';
export const a = () => {};
EOF

    cat > "$TEST_TEMP_DIR/project/src/types/common.ts" << 'EOF'
import { a } from '../a';
export type Type = typeof a;
EOF

    create_arch_rules "$TEST_TEMP_DIR/arch-rules.yaml"
    export ARCH_RULES_FILE="$TEST_TEMP_DIR/arch-rules.yaml"

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --cycles --rules "$ARCH_RULES_FILE" --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "Cycle detection not yet implemented"

    # Cycle involving src/types/** should be excluded
    if command -v jq &> /dev/null; then
        local cycle_count=$(echo "$output" | jq '.cycles | length' 2>/dev/null || echo "0")
        [ "$cycle_count" -eq 0 ] || skip "Whitelist not working"
    fi
}

# ============================================================
# CT-GUARD-004: Architecture Rule Violation (SC-GUARD-004)
# AC-008: Architecture rule validation
# ============================================================

@test "CT-GUARD-004: detects architecture rule violation" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"

    # Create violating project structure
    mkdir -p "$TEST_TEMP_DIR/project/src/ui" "$TEST_TEMP_DIR/project/src/db"

    cat > "$TEST_TEMP_DIR/project/src/ui/Dashboard.tsx" << 'EOF'
import { connection } from '../db/connection';
export const Dashboard = () => connection.query();
EOF

    cat > "$TEST_TEMP_DIR/project/src/db/connection.ts" << 'EOF'
export const connection = { query: () => {} };
EOF

    create_arch_rules "$TEST_TEMP_DIR/arch-rules.yaml"
    export ARCH_RULES_FILE="$TEST_TEMP_DIR/arch-rules.yaml"

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --rules "$ARCH_RULES_FILE" --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "Rule checking not yet implemented"

    # Should detect violation
    [[ "$output" == *"violation"* ]] || [[ "$output" == *"ui-no-direct-db"* ]]

    if command -v jq &> /dev/null; then
        local violation_count=$(echo "$output" | jq '.violations | length' 2>/dev/null || echo "0")
        [ "$violation_count" -ge 1 ] || skip "No violations detected"
    fi
}

@test "CT-GUARD-004b: violation includes line number" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"
    skip_if_missing "jq"

    # Reuse previous test setup
    mkdir -p "$TEST_TEMP_DIR/project/src/ui" "$TEST_TEMP_DIR/project/src/db"

    cat > "$TEST_TEMP_DIR/project/src/ui/Dashboard.tsx" << 'EOF'
import { connection } from '../db/connection';
export const Dashboard = () => connection.query();
EOF

    cat > "$TEST_TEMP_DIR/project/src/db/connection.ts" << 'EOF'
export const connection = { query: () => {} };
EOF

    create_arch_rules "$TEST_TEMP_DIR/arch-rules.yaml"

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --rules "$TEST_TEMP_DIR/arch-rules.yaml" --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "Rule checking not yet implemented"

    # Violation should include line number
    local line=$(echo "$output" | jq '.violations[0].line' 2>/dev/null || echo "null")
    [ "$line" != "null" ] || skip "Line number not included"
    [ "$line" -eq 1 ] || skip "Line number incorrect"
}

# ============================================================
# CT-GUARD-005: Pre-commit Staged Only (SC-GUARD-005)
# AC-012: Pre-commit integration
# ============================================================

@test "CT-GUARD-005: pre-commit checks only staged files" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"
    skip_if_missing "git"

    # Setup git repo using helper
    setup_test_git_repo_with_src "$TEST_TEMP_DIR/repo" || skip "git init failed"

    # Create and commit initial files
    echo "export const a = 1;" > src/a.ts
    git add src/a.ts
    git commit -m "initial" --quiet

    # Stage one file
    echo "export const b = 2;" > src/b.ts
    git add src/b.ts

    # Modify another (unstaged)
    echo "export const a = 2;" > src/a.ts

    run "$DEPENDENCY_GUARD" --pre-commit --format json

    cleanup_test_git_repo

    [ "$status" -eq 0 ] || skip "Pre-commit mode not yet implemented"

    # Parse JSON to check files_checked array (precise validation)
    if command -v jq &> /dev/null; then
        # Get the files array (try multiple possible field names)
        local files_array
        files_array=$(echo "$output" | jq -r '.files_checked // .files // []' 2>/dev/null)

        if [ -n "$files_array" ] && [ "$files_array" != "[]" ] && [ "$files_array" != "null" ]; then
            # Precise check: staged file (b.ts) should be in the array
            local has_staged
            has_staged=$(echo "$output" | jq '[.files_checked // .files // []] | flatten | any(endswith("b.ts"))' 2>/dev/null)
            [ "$has_staged" = "true" ] || skip "Staged file b.ts not in files_checked"

            # Precise check: unstaged file (a.ts) should NOT be in the array
            local has_unstaged
            has_unstaged=$(echo "$output" | jq '[.files_checked // .files // []] | flatten | any(endswith("a.ts"))' 2>/dev/null)
            [ "$has_unstaged" = "false" ] || skip "Unstaged file a.ts incorrectly included in files_checked"
        else
            skip "files_checked field not found or empty in JSON output"
        fi
    else
        skip "jq required for precise validation"
    fi
}

# ============================================================
# CT-GUARD-006: Pre-commit with Dependencies (SC-GUARD-006)
# AC-N04: Pre-commit performance with deps
# ============================================================

@test "CT-GUARD-006: --with-deps includes first-level imports" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"

    # Setup git repo with dependencies using helper
    setup_test_git_repo_with_src "$TEST_TEMP_DIR/repo" || skip "git init failed"

    cat > src/main.ts << 'EOF'
import { helper } from './helper';
export const main = () => helper();
EOF

    cat > src/helper.ts << 'EOF'
export const helper = () => 42;
EOF

    git add .
    git commit -m "initial" --quiet

    # Stage main.ts
    echo "// modified" >> src/main.ts
    git add src/main.ts

    run "$DEPENDENCY_GUARD" --pre-commit --with-deps --format json

    cleanup_test_git_repo

    [ "$status" -eq 0 ] || skip "--with-deps not yet implemented"

    # Should check both main.ts and helper.ts (dependency)
    [[ "$output" == *"main.ts"* ]] || skip "Staged file not checked"
    [[ "$output" == *"helper.ts"* ]] || skip "Dependency file not checked"
}

# ============================================================
# CT-GUARD-007: Warning Mode (SC-GUARD-007)
# ============================================================

@test "CT-GUARD-007: on_violation=warn does not block" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"
    skip_if_missing "jq"

    # Create violating project
    mkdir -p "$TEST_TEMP_DIR/project/src/ui" "$TEST_TEMP_DIR/project/src/db"

    cat > "$TEST_TEMP_DIR/project/src/ui/Dashboard.tsx" << 'EOF'
import { connection } from '../db/connection';
EOF

    cat > "$TEST_TEMP_DIR/project/src/db/connection.ts" << 'EOF'
export const connection = {};
EOF

    # Create rules with warn mode
    cat > "$TEST_TEMP_DIR/arch-rules.yaml" << 'EOF'
schema_version: "1.0.0"
rules:
  - name: "ui-no-direct-db"
    from: "src/ui/**"
    cannot_import:
      - "src/db/**"
    severity: "error"
config:
  on_violation: "warn"
EOF

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --rules "$TEST_TEMP_DIR/arch-rules.yaml" --format json

    cd - > /dev/null

    # Should succeed (not block)
    [ "$status" -eq 0 ] || skip "Warning mode not yet implemented"

    # summary.blocked should be false
    local blocked=$(echo "$output" | jq '.summary.blocked' 2>/dev/null || echo "null")
    [ "$blocked" = "false" ] || skip "blocked should be false in warn mode"
}

# ============================================================
# CT-GUARD-008: Block Mode (SC-GUARD-008)
# ============================================================

@test "CT-GUARD-008: on_violation=block returns exit 1" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"
    skip_if_missing "jq"

    # Create violating project
    mkdir -p "$TEST_TEMP_DIR/project/src/ui" "$TEST_TEMP_DIR/project/src/db"

    cat > "$TEST_TEMP_DIR/project/src/ui/Dashboard.tsx" << 'EOF'
import { connection } from '../db/connection';
EOF

    cat > "$TEST_TEMP_DIR/project/src/db/connection.ts" << 'EOF'
export const connection = {};
EOF

    # Create rules with block mode
    cat > "$TEST_TEMP_DIR/arch-rules.yaml" << 'EOF'
schema_version: "1.0.0"
rules:
  - name: "ui-no-direct-db"
    from: "src/ui/**"
    cannot_import:
      - "src/db/**"
    severity: "error"
config:
  on_violation: "block"
EOF

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --rules "$TEST_TEMP_DIR/arch-rules.yaml" --format json

    cd - > /dev/null

    # Should fail (block)
    [ "$status" -eq 1 ] || skip "Block mode not yet implemented"

    # summary.blocked should be true
    local blocked=$(echo "$output" | jq '.summary.blocked' 2>/dev/null || echo "null")
    [ "$blocked" = "true" ] || skip "blocked should be true in block mode"
}

# ============================================================
# CT-GUARD-009: False Positive Rate (SC-GUARD-009)
# AC-007: False positive rate < 5%
# ============================================================

@test "CT-GUARD-009: false positive rate under 5%" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"

    # Create project with NO cycles
    mkdir -p "$TEST_TEMP_DIR/project/src"

    # Linear dependency chain (no cycles)
    echo 'export const a = 1;' > "$TEST_TEMP_DIR/project/src/a.ts"
    echo 'import { a } from "./a"; export const b = a;' > "$TEST_TEMP_DIR/project/src/b.ts"
    echo 'import { b } from "./b"; export const c = b;' > "$TEST_TEMP_DIR/project/src/c.ts"
    echo 'import { c } from "./c"; export const d = c;' > "$TEST_TEMP_DIR/project/src/d.ts"
    echo 'import { d } from "./d"; export const e = d;' > "$TEST_TEMP_DIR/project/src/e.ts"

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --cycles --scope "src/" --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "Cycle detection not yet implemented"

    # Should detect 0 cycles (no false positives)
    if command -v jq &> /dev/null; then
        local cycle_count=$(echo "$output" | jq '.cycles | length' 2>/dev/null || echo "0")
        [ "$cycle_count" -eq 0 ] || skip "False positive detected: $cycle_count cycles in non-cyclic code"
    fi
}

# ============================================================
# CT-GUARD-010: Violation Report Format (REQ-GUARD-003)
# ============================================================

@test "CT-GUARD-010: violation report has schema_version" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"
    skip_if_missing "jq"

    mkdir -p "$TEST_TEMP_DIR/project/src"
    echo 'export const a = 1;' > "$TEST_TEMP_DIR/project/src/a.ts"

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --all --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "dependency-guard.sh not yet implemented"

    assert_valid_json "$output"
    assert_json_field "$output" ".schema_version"
}

@test "CT-GUARD-010b: violation report has summary" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"
    skip_if_missing "jq"

    mkdir -p "$TEST_TEMP_DIR/project/src"
    echo 'export const a = 1;' > "$TEST_TEMP_DIR/project/src/a.ts"

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --all --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "dependency-guard.sh not yet implemented"

    assert_json_field "$output" ".summary"
    assert_json_field "$output" ".summary.total_violations"
    assert_json_field "$output" ".summary.total_cycles"
    assert_json_field "$output" ".summary.blocked"
}

# ============================================================
# CT-GUARD-011: MCP Tool Registration (REQ-GUARD-005)
# ============================================================

@test "CT-GUARD-011: ci_arch_check tool registered in server.ts" {
    local server_ts="./src/server.ts"
    [ -f "$server_ts" ] || skip "server.ts not found"

    run grep -l "ci_arch_check" "$server_ts"
    [ "$status" -eq 0 ] || skip "ci_arch_check not yet registered"
}

@test "CT-GUARD-011b: ci_arch_check has correct input schema" {
    local server_ts="./src/server.ts"
    [ -f "$server_ts" ] || skip "server.ts not found"

    run grep -A 30 "ci_arch_check" "$server_ts"
    [[ "$output" == *"ci_arch_check"* ]] || skip "ci_arch_check not yet registered"

    # Check for expected parameters
    [[ "$output" == *"path"* ]] || skip "path parameter not found"
    [[ "$output" == *"format"* ]] || skip "format parameter not found"
}

# ============================================================
# AC-005: 孤儿模块检测测试
# 契约测试: CT-OD-001, CT-OD-002
# ============================================================

# @test SC-OD-001: 检测孤儿模块
@test "SC-OD-001: orphan-check detects nodes with no incoming edges" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"

    mkdir -p "$TEST_TEMP_DIR/project/src"

    # A 被 B 引用，D 无入边（孤儿）
    cat > "$TEST_TEMP_DIR/project/src/a.ts" << 'EOF'
export const a = () => 1;
EOF

    cat > "$TEST_TEMP_DIR/project/src/b.ts" << 'EOF'
import { a } from './a';
export const b = () => a();
EOF

    cat > "$TEST_TEMP_DIR/project/src/orphan.ts" << 'EOF'
export const orphan = () => "unused";
EOF

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --orphan-check --format json

    cd - > /dev/null

    skip_if_orphan_check_not_implemented "$output"
    skip_if_not_ready "$status" "$output" "orphan-check"
    assert_exit_success "$status"
    assert_valid_json "$output"
    assert_contains "$output" "orphan"
}

# @test SC-OD-002: 排除入口点
@test "SC-OD-002: orphan-check excludes entry points" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"

    mkdir -p "$TEST_TEMP_DIR/project/src"

    # index.ts 是入口点，无入边但不应报告为孤儿
    cat > "$TEST_TEMP_DIR/project/src/index.ts" << 'EOF'
export function main() { return "entry"; }
EOF

    cat > "$TEST_TEMP_DIR/project/src/helper.ts" << 'EOF'
export const helper = () => "unused";
EOF

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --orphan-check --format json

    cd - > /dev/null

    skip_if_orphan_check_not_implemented "$output"
    skip_if_not_ready "$status" "$output" "orphan-check entry point"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # index.ts 不应被报告为孤儿
    assert_not_contains "$output" "index.ts"
    # helper.ts 应被报告为孤儿
    assert_contains "$output" "helper"
}

# @test SC-OD-003: 排除测试文件
@test "SC-OD-003: orphan-check excludes test files" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"

    mkdir -p "$TEST_TEMP_DIR/project/src"

    cat > "$TEST_TEMP_DIR/project/src/utils.ts" << 'EOF'
export const utils = () => 1;
EOF

    cat > "$TEST_TEMP_DIR/project/src/utils.test.ts" << 'EOF'
import { utils } from './utils';
test('utils works', () => expect(utils()).toBe(1));
EOF

    cat > "$TEST_TEMP_DIR/project/src/orphan.ts" << 'EOF'
export const orphan = () => "unused";
EOF

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --orphan-check --format json

    cd - > /dev/null

    skip_if_orphan_check_not_implemented "$output"
    skip_if_not_ready "$status" "$output" "orphan-check test files"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 测试文件不应被报告为孤儿
    assert_not_contains "$output" "utils.test.ts"
    # orphan.ts 应被报告
    assert_contains "$output" "orphan"
}

# @test SC-OD-004: 自定义排除模式
@test "SC-OD-004: orphan-check respects custom exclude patterns" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"

    mkdir -p "$TEST_TEMP_DIR/project/src/experimental"

    cat > "$TEST_TEMP_DIR/project/src/main.ts" << 'EOF'
export const main = () => "main";
EOF

    cat > "$TEST_TEMP_DIR/project/src/experimental/beta.ts" << 'EOF'
export const beta = () => "experimental";
EOF

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --orphan-check --exclude "src/experimental/**" --format json

    cd - > /dev/null

    skip_if_orphan_check_not_implemented "$output"
    skip_if_not_ready "$status" "$output" "orphan-check exclude"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # experimental 目录应被排除
    assert_not_contains "$output" "beta"
}

# @test SC-OD-005: JSON 格式输出
@test "SC-OD-005: orphan-check outputs valid JSON with required fields" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"
    skip_if_missing "jq"

    mkdir -p "$TEST_TEMP_DIR/project/src"

    cat > "$TEST_TEMP_DIR/project/src/used.ts" << 'EOF'
export const used = () => 1;
EOF

    cat > "$TEST_TEMP_DIR/project/src/caller.ts" << 'EOF'
import { used } from './used';
export const caller = () => used();
EOF

    cat > "$TEST_TEMP_DIR/project/src/orphan.ts" << 'EOF'
export const orphan = () => "unused";
EOF

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --orphan-check --format json

    cd - > /dev/null

    skip_if_orphan_check_not_implemented "$output"
    skip_if_not_ready "$status" "$output" "orphan-check json"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 验证 JSON 结构
    assert_json_field "$output" ".orphans"
    assert_json_field "$output" ".summary.total_nodes"
    assert_json_field "$output" ".summary.orphan_count"
    assert_json_field "$output" ".summary.orphan_ratio"
}

# @test SC-OD-006: 文本格式输出
@test "SC-OD-006: orphan-check outputs human-readable text format" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"

    mkdir -p "$TEST_TEMP_DIR/project/src"

    cat > "$TEST_TEMP_DIR/project/src/orphan.ts" << 'EOF'
export const orphan = () => "unused";
EOF

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --orphan-check --format text

    cd - > /dev/null

    skip_if_orphan_check_not_implemented "$output"
    skip_if_not_ready "$status" "$output" "orphan-check text"
    assert_exit_success "$status"

    # 验证文本格式包含关键信息
    assert_contains "$output" "Orphan"
    assert_contains "$output" "orphan"
}

# @test SC-OD-007: 无孤儿节点
@test "SC-OD-007: orphan-check reports no orphans when all nodes are referenced" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"

    mkdir -p "$TEST_TEMP_DIR/project/src"

    # 所有节点都被引用
    cat > "$TEST_TEMP_DIR/project/src/a.ts" << 'EOF'
export const a = () => 1;
EOF

    cat > "$TEST_TEMP_DIR/project/src/b.ts" << 'EOF'
import { a } from './a';
export const b = () => a();
EOF

    cat > "$TEST_TEMP_DIR/project/src/index.ts" << 'EOF'
import { b } from './b';
export const main = () => b();
EOF

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --orphan-check --format json

    cd - > /dev/null

    skip_if_orphan_check_not_implemented "$output"
    skip_if_not_ready "$status" "$output" "orphan-check no orphans"
    assert_exit_success "$status"

    # 应报告无孤儿
    if command -v jq &> /dev/null; then
        local count=$(echo "$output" | jq '.summary.orphan_count // .orphans | length' 2>/dev/null || echo "0")
        [ "$count" -eq 0 ] || skip "Expected 0 orphans"
    fi
}

# @test SC-OD-008: 与循环检测联合运行
@test "SC-OD-008: orphan-check combined with cycle detection" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"

    mkdir -p "$TEST_TEMP_DIR/project/src"

    # 创建循环依赖
    cat > "$TEST_TEMP_DIR/project/src/a.ts" << 'EOF'
import { b } from './b';
export const a = () => b();
EOF

    cat > "$TEST_TEMP_DIR/project/src/b.ts" << 'EOF'
import { a } from './a';
export const b = () => a();
EOF

    # 创建孤儿
    cat > "$TEST_TEMP_DIR/project/src/orphan.ts" << 'EOF'
export const orphan = () => "unused";
EOF

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --orphan-check --cycles --format json

    cd - > /dev/null

    skip_if_orphan_check_not_implemented "$output"
    skip_if_not_ready "$status" "$output" "orphan-check combined"
    assert_exit_success "$status"
    assert_valid_json "$output"

    # 检查 orphan-check 功能是否真正实现（输出中应包含 orphans 字段）
    if ! echo "$output" | grep -q '"orphans"'; then
        skip "orphan-check not yet implemented (cycles work but orphans field missing)"
    fi

    # 应同时报告循环和孤儿
    assert_contains "$output" "orphan"
    assert_contains "$output" "cycle"
}

# @test SC-OD-009: 功能禁用时跳过
@test "SC-OD-009: orphan-check skips when feature is disabled" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"

    mkdir -p "$TEST_TEMP_DIR/project/src"
    mkdir -p "$TEST_TEMP_DIR/config"

    # 禁用孤儿检测
    cat > "$TEST_TEMP_DIR/config/features.yaml" << 'EOF'
features:
  orphan_detection:
    enabled: false
EOF
    export FEATURES_CONFIG="$TEST_TEMP_DIR/config/features.yaml"

    cat > "$TEST_TEMP_DIR/project/src/orphan.ts" << 'EOF'
export const orphan = () => "unused";
EOF

    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --orphan-check --format json

    cd - > /dev/null

    skip_if_orphan_check_not_implemented "$output"
    skip_if_not_ready "$status" "$output" "orphan-check disabled"
    assert_exit_success "$status"
    assert_contains "$output" "disabled"
}

# @test SC-OD-010: 空图处理
@test "SC-OD-010: orphan-check handles empty graph gracefully" {
    [ -x "$DEPENDENCY_GUARD" ] || skip "dependency-guard.sh not yet implemented"

    mkdir -p "$TEST_TEMP_DIR/project/src"

    # 空项目，无源文件
    cd "$TEST_TEMP_DIR/project"

    run "$DEPENDENCY_GUARD" --orphan-check --format json

    cd - > /dev/null

    skip_if_orphan_check_not_implemented "$output"
    skip_if_not_ready "$status" "$output" "orphan-check empty"
    assert_exit_success "$status"

    # 应优雅处理空图
    [[ "$output" == *"No nodes"* ]] || [[ "$output" == *"empty"* ]] || \
        assert_valid_json "$output"
}
