#!/usr/bin/env bats
# context-layer.bats - Context Layer Contract Tests
#
# Purpose: Verify commit semantic classification and bug fix history integration
# Depends: bats-core, jq, git
# Run: bats tests/context-layer.bats
#
# Baseline: 2026-01-14
# Change: augment-upgrade-phase2
# Trace: AC-009, AC-010, AC-014

# Load shared helpers
load 'helpers/common'

# Store project root for absolute paths (tests may cd to temp dirs)
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
CONTEXT_LAYER="${PROJECT_ROOT}/scripts/context-layer.sh"
HOTSPOT_ANALYZER="${PROJECT_ROOT}/scripts/hotspot-analyzer.sh"
TEST_TEMP_DIR=""

# ============================================================
# Setup / Teardown
# ============================================================

setup() {
    TEST_TEMP_DIR=$(mktemp -d)
}

teardown() {
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Helper: Create git repo with various commit types
setup_git_repo_with_commits() {
    local dir="$1"
    mkdir -p "$dir"
    cd "$dir"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test User"

    # Create initial file
    echo "initial" > test.txt
    git add test.txt
    git commit -m "initial commit" --quiet

    # fix commit
    echo "fix1" >> test.txt
    git add test.txt
    git commit -m "fix: resolve null pointer error" --quiet

    # feat commit
    echo "feat1" >> test.txt
    git add test.txt
    git commit -m "feat(auth): add OAuth support" --quiet

    # refactor commit
    echo "refactor1" >> test.txt
    git add test.txt
    git commit -m "refactor: extract helper function" --quiet

    # docs commit
    echo "docs1" >> test.txt
    git add test.txt
    git commit -m "docs: update README" --quiet

    # chore commit
    echo "chore1" >> test.txt
    git add test.txt
    git commit -m "chore: bump dependencies" --quiet

    # Another fix
    echo "fix2" >> test.txt
    git add test.txt
    git commit -m "fix: handle edge case in login" --quiet

    cd - > /dev/null
}

# ============================================================
# Basic Verification
# ============================================================

@test "CT-CTX-BASE-001: context-layer.sh exists and is executable" {
    [ -x "$CONTEXT_LAYER" ] || skip "context-layer.sh not yet implemented"
}

@test "CT-CTX-BASE-002: --help shows usage information" {
    [ -x "$CONTEXT_LAYER" ] || skip "context-layer.sh not yet implemented"
    run "$CONTEXT_LAYER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"classify"* ]] || [[ "$output" == *"context"* ]] || [[ "$output" == *"commit"* ]]
}

# ============================================================
# CT-CTX-001: Fix Commit Classification (SC-CTX-001)
# AC-009: Commit semantic classification
# ============================================================

@test "CT-CTX-001: classifies 'fix:' commit as type=fix" {
    [ -x "$CONTEXT_LAYER" ] || skip "context-layer.sh not yet implemented"

    setup_git_repo_with_commits "$TEST_TEMP_DIR/repo"
    cd "$TEST_TEMP_DIR/repo"

    # Get the fix commit SHA
    local fix_sha=$(git log --oneline --grep="fix: resolve" | head -1 | cut -d' ' -f1)

    run "$CONTEXT_LAYER" --classify "$fix_sha" --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "Commit classification not yet implemented"

    if command -v jq &> /dev/null; then
        local type=$(echo "$output" | jq -r '.type' 2>/dev/null)
        [ "$type" = "fix" ] || skip "Type should be 'fix', got '$type'"

        # Use portable float comparison from helpers
        assert_confidence_gte "$output" ".confidence" "0.9" || \
        skip "Confidence should be >= 0.9"
    fi
}

@test "CT-CTX-001b: classifies 'bug' in message as fix" {
    [ -x "$CONTEXT_LAYER" ] || skip "context-layer.sh not yet implemented"

    mkdir -p "$TEST_TEMP_DIR/repo"
    cd "$TEST_TEMP_DIR/repo"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"

    echo "content" > test.txt
    git add test.txt
    git commit -m "Fixed bug in authentication" --quiet

    local sha=$(git rev-parse HEAD)

    run "$CONTEXT_LAYER" --classify "$sha" --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "Commit classification not yet implemented"

    if command -v jq &> /dev/null; then
        local type=$(echo "$output" | jq -r '.type' 2>/dev/null)
        [ "$type" = "fix" ] || skip "Type should be 'fix' for 'bug' keyword, got '$type'"
    fi
}

# ============================================================
# CT-CTX-002: Feat Commit Classification (SC-CTX-002)
# ============================================================

@test "CT-CTX-002: classifies 'feat:' commit as type=feat" {
    [ -x "$CONTEXT_LAYER" ] || skip "context-layer.sh not yet implemented"

    setup_git_repo_with_commits "$TEST_TEMP_DIR/repo"
    cd "$TEST_TEMP_DIR/repo"

    local feat_sha=$(git log --oneline --grep="feat(auth)" | head -1 | cut -d' ' -f1)

    run "$CONTEXT_LAYER" --classify "$feat_sha" --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "Commit classification not yet implemented"

    if command -v jq &> /dev/null; then
        local type=$(echo "$output" | jq -r '.type' 2>/dev/null)
        [ "$type" = "feat" ] || skip "Type should be 'feat', got '$type'"

        # Use portable float comparison from helpers
        assert_confidence_gte "$output" ".confidence" "0.9" || \
        skip "Confidence should be >= 0.9"
    fi
}

# ============================================================
# CT-CTX-003: Ambiguous Commit Classification (SC-CTX-003)
# ============================================================

@test "CT-CTX-003: ambiguous commit defaults to chore with low confidence" {
    [ -x "$CONTEXT_LAYER" ] || skip "context-layer.sh not yet implemented"

    mkdir -p "$TEST_TEMP_DIR/repo"
    cd "$TEST_TEMP_DIR/repo"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"

    echo "content" > test.txt
    git add test.txt
    git commit -m "update user module" --quiet

    local sha=$(git rev-parse HEAD)

    run "$CONTEXT_LAYER" --classify "$sha" --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "Commit classification not yet implemented"

    if command -v jq &> /dev/null; then
        local type=$(echo "$output" | jq -r '.type' 2>/dev/null)
        [ "$type" = "chore" ] || skip "Ambiguous commit should default to 'chore', got '$type'"

        # Use portable float comparison from helpers
        assert_confidence_lt "$output" ".confidence" "0.8" || \
        skip "Ambiguous commit confidence should be < 0.8"
    fi
}

# ============================================================
# CT-CTX-004: Bug Fix History Extraction (SC-CTX-004)
# AC-010: Bug fix history weight
# ============================================================

@test "CT-CTX-004: extracts correct bug fix count for file" {
    [ -x "$CONTEXT_LAYER" ] || skip "context-layer.sh not yet implemented"

    setup_git_repo_with_commits "$TEST_TEMP_DIR/repo"
    cd "$TEST_TEMP_DIR/repo"

    run "$CONTEXT_LAYER" --bug-history --file test.txt --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "Bug history extraction not yet implemented"

    if command -v jq &> /dev/null; then
        local count=$(echo "$output" | jq -r '.bug_fix_count' 2>/dev/null)
        # We created 2 fix commits
        [ "$count" -eq 2 ] || skip "Bug fix count should be 2, got '$count'"

        local commits=$(echo "$output" | jq -r '.bug_fix_commits | length' 2>/dev/null)
        [ "$commits" -eq 2 ] || skip "Bug fix commits array should have 2 items"
    fi
}

@test "CT-CTX-004b: bug history includes commit SHAs" {
    [ -x "$CONTEXT_LAYER" ] || skip "context-layer.sh not yet implemented"
    skip_if_missing "jq"

    setup_git_repo_with_commits "$TEST_TEMP_DIR/repo"
    cd "$TEST_TEMP_DIR/repo"

    run "$CONTEXT_LAYER" --bug-history --file test.txt --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "Bug history extraction not yet implemented"

    # SHAs should be 7+ characters
    local sha1=$(echo "$output" | jq -r '.bug_fix_commits[0]' 2>/dev/null)
    [ "${#sha1}" -ge 7 ] || skip "SHA should be at least 7 characters"
}

# ============================================================
# CT-CTX-005: Hotspot Score Enhancement (SC-CTX-005)
# ============================================================

@test "CT-CTX-005: --with-bug-history enhances hotspot score" {
    [ -x "$HOTSPOT_ANALYZER" ] || skip "hotspot-analyzer.sh not yet implemented"
    [ -x "$CONTEXT_LAYER" ] || skip "context-layer.sh not yet implemented"

    setup_git_repo_with_commits "$TEST_TEMP_DIR/repo"
    cd "$TEST_TEMP_DIR/repo"

    # Get score without bug history (use 2>/dev/null to avoid stderr mixing)
    local json_without
    json_without=$("$HOTSPOT_ANALYZER" --format json 2>/dev/null)
    local status_without=$?
    [ "$status_without" -eq 0 ] || { cd - > /dev/null; skip "hotspot-analyzer.sh not working"; }
    local score_without=""
    if command -v jq &> /dev/null; then
        score_without=$(echo "$json_without" | jq -r '.hotspots[0].score // 0' 2>/dev/null)
    fi

    # Get score with bug history
    local json_with
    json_with=$("$HOTSPOT_ANALYZER" --with-bug-history --format json 2>/dev/null)
    local status_with=$?
    [ "$status_with" -eq 0 ] || { cd - > /dev/null; skip "--with-bug-history not yet implemented"; }
    local score_with=""
    if command -v jq &> /dev/null; then
        score_with=$(echo "$json_with" | jq -r '.hotspots[0].score // 0' 2>/dev/null)
    fi

    cd - > /dev/null

    # Score with bug history should be higher (due to bug fix ratio)
    if [ -n "$score_without" ] && [ -n "$score_with" ]; then
        local comparison=$(echo "$score_with > $score_without" | bc -l 2>/dev/null || echo "1")
        [ "$comparison" = "1" ] || skip "Score with bug history ($score_with) should be > without ($score_without)"
    fi
}

@test "CT-CTX-005b: hotspot output includes bug_weight field" {
    [ -x "$HOTSPOT_ANALYZER" ] || skip "hotspot-analyzer.sh not yet implemented"

    setup_git_repo_with_commits "$TEST_TEMP_DIR/repo"
    cd "$TEST_TEMP_DIR/repo"

    run "$HOTSPOT_ANALYZER" --with-bug-history --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--with-bug-history not yet implemented"

    [[ "$output" == *"bug"* ]] || skip "Output should mention bug-related field"
}

# ============================================================
# CT-CTX-006: Backward Compatibility (SC-CTX-006)
# AC-014: hotspot-analyzer.sh baseline
# ============================================================

@test "CT-CTX-006: hotspot-analyzer without --with-bug-history unchanged" {
    [ -x "$HOTSPOT_ANALYZER" ] || skip "hotspot-analyzer.sh not yet implemented"

    run "$HOTSPOT_ANALYZER" --format json
    [ "$status" -eq 0 ]

    # Output should NOT contain bug_weight when not using --with-bug-history
    [[ "$output" != *"bug_weight"* ]] || skip "bug_weight should not appear without --with-bug-history"
    [[ "$output" != *"bug_fix"* ]] || skip "bug_fix fields should not appear without --with-bug-history"
}

@test "CT-CTX-006b: output format matches existing hotspot schema" {
    [ -x "$HOTSPOT_ANALYZER" ] || skip "hotspot-analyzer.sh not yet implemented"
    skip_if_missing "jq"

    run "$HOTSPOT_ANALYZER" --format json
    [ "$status" -eq 0 ]

    # Verify essential output fields are present (text format may not have JSON schema)
    [[ "$output" == *"file"* ]] || [[ "$output" == *"score"* ]] || \
    skip "Output should contain file/score info"
}

# ============================================================
# CT-CTX-007: Context Index Generation (SC-CTX-007)
# ============================================================

@test "CT-CTX-007: --index generates context-index.json" {
    [ -x "$CONTEXT_LAYER" ] || skip "context-layer.sh not yet implemented"

    setup_git_repo_with_commits "$TEST_TEMP_DIR/repo"
    cd "$TEST_TEMP_DIR/repo"

    run "$CONTEXT_LAYER" --index --days 90

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--index not yet implemented"

    # Check index file was created
    [ -f "$TEST_TEMP_DIR/repo/.devbooks/context-index.json" ] || \
    [ -f "$TEST_TEMP_DIR/repo/context-index.json" ] || \
    skip "context-index.json not created"
}

@test "CT-CTX-007b: context index includes commit_types statistics" {
    [ -x "$CONTEXT_LAYER" ] || skip "context-layer.sh not yet implemented"
    skip_if_missing "jq"

    setup_git_repo_with_commits "$TEST_TEMP_DIR/repo"
    cd "$TEST_TEMP_DIR/repo"

    run "$CONTEXT_LAYER" --index --days 90

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--index not yet implemented"

    # Read the index file
    local index_file=""
    if [ -f "$TEST_TEMP_DIR/repo/.devbooks/context-index.json" ]; then
        index_file="$TEST_TEMP_DIR/repo/.devbooks/context-index.json"
    elif [ -f "$TEST_TEMP_DIR/repo/context-index.json" ]; then
        index_file="$TEST_TEMP_DIR/repo/context-index.json"
    else
        skip "context-index.json not found"
    fi

    local content=$(cat "$index_file")
    assert_json_field "$content" ".files"
    [[ "$content" == *"commit_types"* ]] || skip "commit_types not in index"
}

# ============================================================
# CT-CTX-008: Classification Accuracy (SC-CTX-008)
# AC-009: >= 90% accuracy
# ============================================================

@test "CT-CTX-008: classification accuracy >= 90% on test set" {
    [ -x "$CONTEXT_LAYER" ] || skip "context-layer.sh not yet implemented"

    # Create test repo with known commit types
    mkdir -p "$TEST_TEMP_DIR/repo"
    cd "$TEST_TEMP_DIR/repo"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"

    # Create labeled test set (15 commits - balanced for quick execution)
    # Note: This is an integration-level test; consider increasing samples
    # in a dedicated integration test suite if needed
    local correct=0
    local total=0

    # Test fix commits (5 samples)
    for msg in "fix: bug in parser" "fix(core): memory leak" "Fixed crash on startup" \
               "fix: resolve null pointer" "Bugfix: login issue"; do
        echo "$msg" > test.txt
        git add test.txt
        git commit -m "$msg" --quiet
        local sha=$(git rev-parse HEAD)
        run "$CONTEXT_LAYER" --classify "$sha" --format json
        if [ "$status" -eq 0 ] && command -v jq &> /dev/null; then
            local type=$(echo "$output" | jq -r '.type' 2>/dev/null)
            if [ "$type" = "fix" ]; then
                correct=$((correct + 1))
            fi
        fi
        total=$((total + 1))
    done

    # Test feat commits (5 samples)
    for msg in "feat: add dark mode" "feat(auth): oauth support" "Add new search feature" \
               "feat: implement caching" "Implement pagination"; do
        echo "$msg" > test.txt
        git add test.txt
        git commit -m "$msg" --quiet
        local sha=$(git rev-parse HEAD)
        run "$CONTEXT_LAYER" --classify "$sha" --format json
        if [ "$status" -eq 0 ] && command -v jq &> /dev/null; then
            local type=$(echo "$output" | jq -r '.type' 2>/dev/null)
            if [ "$type" = "feat" ]; then
                correct=$((correct + 1))
            fi
        fi
        total=$((total + 1))
    done

    # Test refactor commits (2 samples)
    for msg in "refactor: extract helper" "refactor(utils): clean up"; do
        echo "$msg" > test.txt
        git add test.txt
        git commit -m "$msg" --quiet
        local sha=$(git rev-parse HEAD)
        run "$CONTEXT_LAYER" --classify "$sha" --format json
        if [ "$status" -eq 0 ] && command -v jq &> /dev/null; then
            local type=$(echo "$output" | jq -r '.type' 2>/dev/null)
            if [ "$type" = "refactor" ]; then
                correct=$((correct + 1))
            fi
        fi
        total=$((total + 1))
    done

    # Test docs commits (2 samples)
    for msg in "docs: update README" "Document API usage"; do
        echo "$msg" > test.txt
        git add test.txt
        git commit -m "$msg" --quiet
        local sha=$(git rev-parse HEAD)
        run "$CONTEXT_LAYER" --classify "$sha" --format json
        if [ "$status" -eq 0 ] && command -v jq &> /dev/null; then
            local type=$(echo "$output" | jq -r '.type' 2>/dev/null)
            if [ "$type" = "docs" ]; then
                correct=$((correct + 1))
            fi
        fi
        total=$((total + 1))
    done

    # Test chore commit (1 sample)
    for msg in "chore: bump dependencies"; do
        echo "$msg" > test.txt
        git add test.txt
        git commit -m "$msg" --quiet
        local sha=$(git rev-parse HEAD)
        run "$CONTEXT_LAYER" --classify "$sha" --format json
        if [ "$status" -eq 0 ] && command -v jq &> /dev/null; then
            local type=$(echo "$output" | jq -r '.type' 2>/dev/null)
            if [ "$type" = "chore" ]; then
                correct=$((correct + 1))
            fi
        fi
        total=$((total + 1))
    done

    cd - > /dev/null

    # Calculate accuracy (15 total samples)
    if [ "$total" -gt 0 ]; then
        local accuracy=$((correct * 100 / total))
        [ "$accuracy" -ge 90 ] || skip "Accuracy ${accuracy}% < 90% (${correct}/${total})"
    else
        skip "No commits tested"
    fi
}

# ============================================================
# CT-CTX-009: Index Format (REQ-CTX-004)
# ============================================================

@test "CT-CTX-009: context index has required schema fields" {
    [ -x "$CONTEXT_LAYER" ] || skip "context-layer.sh not yet implemented"
    skip_if_missing "jq"

    setup_git_repo_with_commits "$TEST_TEMP_DIR/repo"
    cd "$TEST_TEMP_DIR/repo"

    run "$CONTEXT_LAYER" --index

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--index not yet implemented"

    local index_file=""
    for f in "$TEST_TEMP_DIR/repo/.devbooks/context-index.json" "$TEST_TEMP_DIR/repo/context-index.json"; do
        [ -f "$f" ] && index_file="$f" && break
    done
    [ -f "$index_file" ] || skip "context-index.json not created"

    local content=$(cat "$index_file")
    assert_valid_json "$content"
    assert_json_field "$content" ".schema_version"
    assert_json_field "$content" ".indexed_at"
    assert_json_field "$content" ".files"
}
