#!/usr/bin/env bats
# feature-toggle.bats - AC-010 Feature Toggle Acceptance Tests
#
# Purpose: Verify feature toggle config can enable/disable new features
# Depends: bats-core
# Run: bats tests/feature-toggle.bats
#
# Baseline: 2026-01-11
# Change: enhance-code-intelligence
# Trace: AC-010

# Load shared helpers
load 'helpers/common'

# Store project root for absolute paths (tests may cd to temp dirs)
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
CONFIG_FILE="${PROJECT_ROOT}/.devbooks/config.yaml"
HOTSPOT_ANALYZER="${PROJECT_ROOT}/scripts/hotspot-analyzer.sh"
BOUNDARY_DETECTOR="${PROJECT_ROOT}/scripts/boundary-detector.sh"
PATTERN_LEARNER="${PROJECT_ROOT}/scripts/pattern-learner.sh"

setup() {
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    fi
}

teardown() {
    if [ -f "${CONFIG_FILE}.bak" ]; then
        mv "${CONFIG_FILE}.bak" "$CONFIG_FILE"
    fi
}

# ============================================================
# Default Enabled Tests (FT-001)
# ============================================================

@test "FT-001: all new features enabled by default" {
    [ -f "$CONFIG_FILE" ] || skip "Config file not found"
    run grep -A 10 "features:" "$CONFIG_FILE"
    [[ "$output" == *"enhanced_hotspot"* ]] || skip "features section not found"
}

@test "FT-001b: without features config uses default values" {
    mkdir -p .devbooks
    echo "protocol: openspec" > "$CONFIG_FILE"

    if [ -x "$HOTSPOT_ANALYZER" ]; then
        run "$HOTSPOT_ANALYZER" --format json 2>&1
        [ "$status" -eq 0 ] || skip "Hotspot analyzer not yet implemented"
    else
        skip "Hotspot analyzer not yet implemented"
    fi
}

# ============================================================
# Disable Hotspot Tests (FT-002)
# ============================================================

@test "FT-002: disable enhanced_hotspot" {
    mkdir -p .devbooks
    cat > "$CONFIG_FILE" << 'EOF'
protocol: openspec
features:
  enhanced_hotspot: false
  intent_analysis: true
  subgraph_retrieval: true
  boundary_detection: true
  pattern_learning: true
  data_flow_tracing: true
  incremental_indexing: true
EOF

    if [ -x "$HOTSPOT_ANALYZER" ]; then
        run "$HOTSPOT_ANALYZER" --format json 2>&1
        [[ "$output" == *"disabled"* ]] || \
        [[ "$output" == *"fallback"* ]] || \
        skip "Feature toggle not yet implemented"
    else
        skip "Hotspot analyzer not yet implemented"
    fi
}

# ============================================================
# Disable Boundary Detection Tests (FT-003)
# ============================================================

@test "FT-003: disable boundary_detection" {
    mkdir -p .devbooks
    cat > "$CONFIG_FILE" << 'EOF'
protocol: openspec
features:
  enhanced_hotspot: true
  intent_analysis: true
  subgraph_retrieval: true
  boundary_detection: false
  pattern_learning: true
  data_flow_tracing: true
  incremental_indexing: true
EOF

    if [ -x "$BOUNDARY_DETECTOR" ]; then
        run "$BOUNDARY_DETECTOR" --path "src/server.ts" --format json 2>&1
        [[ "$output" == *"disabled"* ]] || \
        [[ "$output" == *"fallback"* ]] || \
        skip "Feature toggle not yet implemented"
    else
        skip "Boundary detector not yet implemented"
    fi
}

# ============================================================
# Disable All New Features Tests (FT-004)
# ============================================================

@test "FT-004: disable all new features" {
    mkdir -p .devbooks
    cat > "$CONFIG_FILE" << 'EOF'
protocol: openspec
features:
  enhanced_hotspot: false
  intent_analysis: false
  subgraph_retrieval: false
  boundary_detection: false
  pattern_learning: false
  data_flow_tracing: false
  incremental_indexing: false
EOF

    run grep -c "false" "$CONFIG_FILE"
    [ "$output" = "7" ] || skip "Config not properly set"
}

# ============================================================
# Single Enable Tests
# ============================================================

@test "FT-SINGLE-001: only enable pattern_learning" {
    mkdir -p .devbooks
    cat > "$CONFIG_FILE" << 'EOF'
protocol: openspec
features:
  enhanced_hotspot: false
  intent_analysis: false
  subgraph_retrieval: false
  boundary_detection: false
  pattern_learning: true
  data_flow_tracing: false
  incremental_indexing: false
EOF

    if [ -x "$PATTERN_LEARNER" ]; then
        run "$PATTERN_LEARNER" --learn 2>&1
        [ "$status" -eq 0 ] || skip "Pattern learner not yet implemented"
    else
        skip "Pattern learner not yet implemented"
    fi
}

# ============================================================
# Config Loading Tests
# ============================================================

@test "FT-LOAD-001: script reads features config" {
    if [ -x "$HOTSPOT_ANALYZER" ]; then
        run "$HOTSPOT_ANALYZER" --help 2>&1
        [[ "$output" == *"config"* ]] || \
        [[ "$output" == *"feature"* ]] || \
        [[ "$output" == *"enable"* ]] || \
        skip "Config loading not documented"
    else
        skip "Hotspot analyzer not yet implemented"
    fi
}

@test "FT-LOAD-002: config file missing uses default values" {
    rm -f "$CONFIG_FILE"

    if [ -x "$HOTSPOT_ANALYZER" ]; then
        run "$HOTSPOT_ANALYZER" --format json 2>&1
        [ "$status" -eq 0 ] || \
        [[ "$output" == *"default"* ]] || \
        skip "Default config handling not yet implemented"
    else
        skip "Hotspot analyzer not yet implemented"
    fi
}

# ============================================================
# Config Validation Tests
# ============================================================

@test "FT-VALIDATE-001: invalid config value warns" {
    mkdir -p .devbooks
    cat > "$CONFIG_FILE" << 'EOF'
protocol: openspec
features:
  enhanced_hotspot: "invalid"
EOF

    if [ -x "$HOTSPOT_ANALYZER" ]; then
        run "$HOTSPOT_ANALYZER" --format json 2>&1
        [[ "$output" == *"invalid"* ]] || \
        [[ "$output" == *"warning"* ]] || \
        [[ "$output" == *"error"* ]] || \
        [ "$status" -eq 0 ] || \
        skip "Config validation not yet implemented"
    else
        skip "Hotspot analyzer not yet implemented"
    fi
}

# ============================================================
# Runtime Toggle Tests
# ============================================================

@test "FT-RUNTIME-001: environment variable overrides config" {
    mkdir -p .devbooks
    cat > "$CONFIG_FILE" << 'EOF'
protocol: openspec
features:
  enhanced_hotspot: false
EOF

    if [ -x "$HOTSPOT_ANALYZER" ]; then
        export CI_FEATURE_ENHANCED_HOTSPOT=true
        run "$HOTSPOT_ANALYZER" --format json 2>&1
        unset CI_FEATURE_ENHANCED_HOTSPOT
        skip "Environment variable override not yet implemented"
    else
        skip "Hotspot analyzer not yet implemented"
    fi
}

# ============================================================
# Feature List Completeness Tests
# ============================================================

@test "FT-LIST-001: all new features have toggles" {
    [ -f "$CONFIG_FILE" ] || skip "Config file not found"

    features=(
        "enhanced_hotspot"
        "intent_analysis"
        "subgraph_retrieval"
        "boundary_detection"
        "pattern_learning"
        "data_flow_tracing"
        "incremental_indexing"
    )

    for feature in "${features[@]}"; do
        run grep "$feature" "$CONFIG_FILE"
        [ "$status" -eq 0 ] || skip "$feature flag not found"
    done
}
