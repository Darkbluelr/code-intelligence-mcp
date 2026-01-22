#!/usr/bin/env bats
# feature-toggle.bats - AC-010 Feature Toggle Acceptance Tests
#
# Purpose: Verify config/features.yaml controls new capabilities
# Depends: bats-core, jq
# Run: bats tests/feature-toggle.bats
#
# Change: 20260118-2112-enhance-code-intelligence-capabilities
# Trace: AC-010

load 'helpers/common'

PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
FEATURES_CONFIG="${PROJECT_ROOT}/config/features.yaml"
SEMANTIC_ANOMALY_SCRIPT="${PROJECT_ROOT}/scripts/semantic-anomaly.sh"
GRAPH_RAG_SCRIPT="${PROJECT_ROOT}/scripts/graph-rag.sh"

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing command: $cmd"
}

setup() {
    setup_temp_dir
    backup_file "$FEATURES_CONFIG"
    require_cmd rg
    require_cmd jq
    [ -x "$SEMANTIC_ANOMALY_SCRIPT" ] || fail "Missing executable: $SEMANTIC_ANOMALY_SCRIPT"
    [ -x "$GRAPH_RAG_SCRIPT" ] || fail "Missing executable: $GRAPH_RAG_SCRIPT"
}

teardown() {
    restore_file "$FEATURES_CONFIG"
    cleanup_temp_dir
}

# ============================================================
# Config Presence
# ============================================================

@test "T-FT-001: config/features.yaml exists and has features root" {
    [ -f "$FEATURES_CONFIG" ] || fail "Missing config file: $FEATURES_CONFIG"
    run rg -n "^features:" "$FEATURES_CONFIG"
    assert_exit_success "$status"
}

# ============================================================
# Config Completeness
# ============================================================

@test "T-FT-002: config declares toggles for all new capabilities" {
    [ -f "$FEATURES_CONFIG" ] || fail "Missing config file: $FEATURES_CONFIG"

    features=(
        "context_compressor"
        "drift_detector"
        "data_flow_tracing"
        "graph_store"
        "hybrid_retrieval"
        "llm_rerank"
        "context_signals"
        "semantic_anomaly"
        "benchmark"
        "performance_regression"
    )

    missing=()
    for feature in "${features[@]}"; do
        if ! rg -n "^[[:space:]]+${feature}:" "$FEATURES_CONFIG" >/dev/null 2>&1; then
            missing+=("$feature")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        fail "Missing feature toggles: ${missing[*]}"
    fi
}

# ============================================================
# Toggle Enforcement
# ============================================================

@test "T-FT-003: semantic-anomaly disabled via config/features.yaml" {
    local temp_config="$TEST_TEMP_DIR/features-disabled.yaml"
    cat > "$temp_config" << 'EOF'
features:
  semantic_anomaly:
    enabled: false
EOF

    cat > "$TEST_TEMP_DIR/sample.ts" << 'EOF'
async function fetchData() { await fetch('/api'); }
EOF

    DEVBOOKS_FEATURE_CONFIG="$temp_config" run "$SEMANTIC_ANOMALY_SCRIPT" "$TEST_TEMP_DIR/sample.ts"
    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.status == "disabled"'
}

@test "T-FT-006: llm-rerank disabled via config/features.yaml" {
    local temp_config="$TEST_TEMP_DIR/features-disabled.yaml"
    cat > "$temp_config" << 'EOF'
features:
  llm_rerank:
    enabled: false
EOF

    DEVBOOKS_FEATURE_CONFIG="$temp_config" run "$GRAPH_RAG_SCRIPT" --query "test query" --rerank --format json --mock-embedding --cwd "$TEST_TEMP_DIR" 2>&1
    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.reranked == false' >/dev/null || fail "reranked should be false"
    echo "$output" | jq -e '.metadata.fallback_reason == "disabled"' >/dev/null || fail "missing disabled fallback"
}

@test "T-FT-007: hybrid-retrieval disabled disables graph candidates" {
    local temp_config="$TEST_TEMP_DIR/features-disabled.yaml"
    cat > "$temp_config" << 'EOF'
features:
  hybrid_retrieval:
    enabled: false
EOF

    DEVBOOKS_FEATURE_CONFIG="$temp_config" run "$GRAPH_RAG_SCRIPT" --query "graph store" --fusion-depth 1 --format json --mock-embedding --cwd "$TEST_TEMP_DIR" 2>&1
    assert_exit_success "$status"
    echo "$output" | jq -e '.metadata.graph_candidates == 0' >/dev/null || fail "graph_candidates should be 0 when disabled"
}

@test "T-FT-008: all feature toggles can be disabled via config" {
    cat > "$TEST_TEMP_DIR/all-disabled.yaml" << 'EOF'
features:
  context_compressor:
    enabled: false
  drift_detector:
    enabled: false
  data_flow_tracing:
    enabled: false
  graph_store:
    enabled: false
  hybrid_retrieval:
    enabled: false
  llm_rerank:
    enabled: false
  context_signals:
    enabled: false
  semantic_anomaly:
    enabled: false
  benchmark:
    enabled: false
  performance_regression:
    enabled: false
EOF

    features=(
        "context_compressor"
        "drift_detector"
        "data_flow_tracing"
        "graph_store"
        "hybrid_retrieval"
        "llm_rerank"
        "context_signals"
        "semantic_anomaly"
        "benchmark"
        "performance_regression"
    )

    for feature in "${features[@]}"; do
        DEVBOOKS_FEATURE_CONFIG="$TEST_TEMP_DIR/all-disabled.yaml" \
          run bash -c "source \"$PROJECT_ROOT/scripts/common.sh\"; is_feature_enabled \"$feature\""
        if [ "$status" -eq 0 ]; then
            fail "Feature $feature should be disabled"
        fi
    done
}

@test "T-FT-009: missing config defaults new capabilities to disabled" {
    rm -f "$FEATURES_CONFIG"
    unset DEVBOOKS_FEATURE_CONFIG
    unset FEATURES_CONFIG

    features=(
        "context_compressor"
        "drift_detector"
        "data_flow_tracing"
        "graph_store"
        "hybrid_retrieval"
        "llm_rerank"
        "context_signals"
        "semantic_anomaly"
        "benchmark"
        "performance_regression"
    )

    for feature in "${features[@]}"; do
        run bash -c "source \"$PROJECT_ROOT/scripts/common.sh\"; is_feature_enabled \"$feature\""
        if [ "$status" -eq 0 ]; then
            fail "Feature $feature should be disabled by default"
        fi
    done
}

@test "T-FT-004: --enable-all-features is documented" {
    run "$GRAPH_RAG_SCRIPT" --help
    assert_exit_success "$status"
    assert_contains "$output" "--enable-all-features"
}

@test "T-FT-005: missing features config does not break scripts" {
    rm -f "$FEATURES_CONFIG"

    cat > "$TEST_TEMP_DIR/clean.ts" << 'EOF'
const value = 1;
EOF

    run "$SEMANTIC_ANOMALY_SCRIPT" "$TEST_TEMP_DIR/clean.ts"
    assert_exit_success "$status"
    echo "$output" | jq -e 'has("summary")'
}
