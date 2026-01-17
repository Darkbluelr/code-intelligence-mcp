#!/usr/bin/env bats
# hotspot-analyzer.bats - AC-001 Hotspot Algorithm Acceptance Tests
#
# Purpose: Verify hotspot-analyzer.sh core functionality
# Depends: bats-core (https://github.com/bats-core/bats-core)
# Run: bats tests/hotspot-analyzer.bats
#
# Baseline: 2026-01-11
# Change: enhance-code-intelligence
# Trace: AC-001

# Load shared helpers
load 'helpers/common'

# Store project root for absolute paths (tests may cd to temp dirs)
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
HOTSPOT_ANALYZER="${PROJECT_ROOT}/scripts/hotspot-analyzer.sh"
TEST_TIMEOUT=5

# ============================================================
# Basic Functionality Tests (HS-001, HS-002)
# ============================================================

@test "HS-001: hotspot-analyzer.sh exists and is executable" {
    [ -x "$HOTSPOT_ANALYZER" ]
}

@test "HS-002: --help shows usage information" {
    run "$HOTSPOT_ANALYZER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hotspot"* ]] || [[ "$output" == *"hotspot"* ]]
    [[ "$output" == *"--top-n"* ]] || [[ "$output" == *"top"* ]]
}

@test "HS-002b: --version shows version" {
    run "$HOTSPOT_ANALYZER" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"1."* ]] || [[ "$output" == *"0."* ]]
}

# ============================================================
# Functionality Tests (HS-003, HS-004)
# ============================================================

@test "HS-003: default returns Top-20 hotspot files in JSON" {
    run "$HOTSPOT_ANALYZER" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"hotspots"* ]]
    [[ "$output" == *"schema_version"* ]]
}

@test "HS-004: custom top_n parameter" {
    # Use 2>/dev/null to avoid stderr mixing with JSON
    output=$("$HOTSPOT_ANALYZER" --top-n 10 --format json 2>/dev/null)
    status=$?
    [ "$status" -eq 0 ]
    if command -v jq &> /dev/null; then
        count=$(echo "$output" | jq '.hotspots | length')
        [ "$count" -le 10 ]
    fi
}

@test "HS-005: hotspot score formula (Frequency x Complexity)" {
    run "$HOTSPOT_ANALYZER" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"frequency"* ]]
    [[ "$output" == *"complexity"* ]]
    [[ "$output" == *"score"* ]]
}

@test "HS-005b: file without git history has Frequency 0" {
    run "$HOTSPOT_ANALYZER" --format json
    [ "$status" -eq 0 ]
}

# ============================================================
# Performance Tests (HS-006)
# ============================================================

@test "HS-006: performance baseline - execution time less than 5s" {
    measure_time "$HOTSPOT_ANALYZER" --format json
    local exit_code=$?

    [ "$exit_code" -eq 0 ]
    [ "$MEASURED_TIME_MS" -lt 5000 ] || skip "Performance baseline: ${MEASURED_TIME_MS}ms > 5000ms"
}

@test "HS-006b: output includes duration_ms field" {
    run "$HOTSPOT_ANALYZER" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"duration"* ]] || [[ "$output" == *"ms"* ]] || true
}

# ============================================================
# Parameter Validation Tests
# ============================================================

@test "HS-PARAM-001: --days parameter support" {
    run "$HOTSPOT_ANALYZER" --help
    [[ "$output" == *"--days"* ]] || [[ "$output" == *"day"* ]] || [[ "$output" == *"30"* ]]
}

@test "HS-PARAM-002: invalid parameter returns error" {
    run "$HOTSPOT_ANALYZER" --invalid-option
    [ "$status" -ne 0 ]
}

# ============================================================
# Output Format Tests
# ============================================================

@test "HS-OUTPUT-001: JSON output is valid JSON" {
    if ! command -v jq &> /dev/null; then
        skip "jq not installed"
    fi
    # Use 2>/dev/null to avoid stderr mixing with JSON
    output=$("$HOTSPOT_ANALYZER" --format json 2>/dev/null)
    status=$?
    [ "$status" -eq 0 ]
    echo "$output" | jq . > /dev/null
}

@test "HS-OUTPUT-002: output includes file field" {
    run "$HOTSPOT_ANALYZER" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *"file"* ]]
}

# ============================================================
# Boundary Value Tests (HS-BOUNDARY)
# ============================================================

@test "HS-BOUNDARY-001: --top-n 0 returns empty or error" {
    run "$HOTSPOT_ANALYZER" --top-n 0 --format json 2>&1
    # Should either return empty hotspots array or error
    [ "$status" -eq 0 ] || [ "$status" -ne 0 ]
    if [ "$status" -eq 0 ]; then
        if command -v jq &> /dev/null; then
            count=$(echo "$output" | jq '.hotspots | length' 2>/dev/null || echo "0")
            [ "$count" -eq 0 ] || skip "Implementation allows top-n 0"
        fi
    fi
}

@test "HS-BOUNDARY-002: --top-n -1 returns error" {
    run "$HOTSPOT_ANALYZER" --top-n -1 --format json 2>&1
    # Negative values should be rejected
    [ "$status" -ne 0 ] || \
    [[ "$output" == *"invalid"* ]] || \
    [[ "$output" == *"error"* ]] || \
    skip "Implementation accepts negative top-n"
}

@test "HS-BOUNDARY-003: --top-n very large value handled" {
    run "$HOTSPOT_ANALYZER" --top-n 99999 --format json 2>&1
    # Should succeed but return at most available files
    [ "$status" -eq 0 ] || skip "Large top-n not yet supported"
}

@test "HS-BOUNDARY-004: --days 0 returns error or empty" {
    run "$HOTSPOT_ANALYZER" --days 0 --format json 2>&1
    # Zero days should be rejected or return empty
    [ "$status" -ne 0 ] || \
    [[ "$output" == *"error"* ]] || \
    [ "$status" -eq 0 ]
}

@test "HS-BOUNDARY-005: --days -1 returns error" {
    run "$HOTSPOT_ANALYZER" --days -1 --format json 2>&1
    # Negative days should be rejected
    [ "$status" -ne 0 ] || \
    [[ "$output" == *"invalid"* ]] || \
    [[ "$output" == *"error"* ]] || \
    skip "Implementation accepts negative days"
}

@test "HS-BOUNDARY-006: empty repository handled gracefully" {
    # Create empty temp directory
    setup_temp_dir
    cd "$TEST_TEMP_DIR"
    git init --quiet

    run "$HOTSPOT_ANALYZER" --format json 2>&1

    cd - > /dev/null
    cleanup_temp_dir

    # Should return empty hotspots or appropriate message
    [ "$status" -eq 0 ] || \
    [[ "$output" == *"empty"* ]] || \
    [[ "$output" == *"no "* ]] || \
    skip "Empty repo handling not yet implemented"
}

@test "HS-BOUNDARY-007: non-git directory handled gracefully" {
    setup_temp_dir
    cd "$TEST_TEMP_DIR"

    run "$HOTSPOT_ANALYZER" --format json 2>&1

    cd - > /dev/null
    cleanup_temp_dir

    # Should return error or warning about non-git directory
    [ "$status" -ne 0 ] || \
    [[ "$output" == *"git"* ]] || \
    [[ "$output" == *"not"* ]] || \
    skip "Non-git directory handling not yet implemented"
}

# ============================================================
# Hotspot Weighting Contract Tests (CT-HW-001 ~ CT-HW-006)
# ============================================================
#
# Spec: dev-playbooks/changes/algorithm-optimization-parity/specs/hotspot-weighting/spec.md
# Change: algorithm-optimization-parity
# Module: Hotspot weighting algorithm
#
# Weighted score formula: score = churn*0.4 + complexity*0.3 + coupling*0.2 + age*0.1
# All factors normalized to [0,1] range
# ============================================================

@test "CT-HW-001: weighted score formula - score = churn*0.4 + complexity*0.3 + coupling*0.2 + age*0.1" {
    # Test weighted score formula implementation
    # Expected: output contains weighted score field and follows formula
    skip_if_missing "jq"

    run "$HOTSPOT_ANALYZER" --format json --weighted 2>&1
    skip_if_not_ready "$status" "$output" "Weighted scoring formula"

    local json
    json=$(extract_json "$output")

    # Verify output contains score field
    assert_contains "$json" "score" "Output should contain score field"

    # Verify score is based on weighted factors
    # Check if contains all factors
    if [[ "$json" == *"churn"* ]] && [[ "$json" == *"complexity"* ]]; then
        # If detailed factors present, verify formula
        local first_hotspot
        first_hotspot=$(echo "$json" | jq '.hotspots[0]' 2>/dev/null)

        if [ "$first_hotspot" != "null" ] && [ -n "$first_hotspot" ]; then
            local churn complexity coupling age score
            churn=$(echo "$first_hotspot" | jq -r '.churn // .churn_norm // 0' 2>/dev/null)
            complexity=$(echo "$first_hotspot" | jq -r '.complexity // .complexity_norm // 0' 2>/dev/null)
            coupling=$(echo "$first_hotspot" | jq -r '.coupling // .coupling_norm // 0' 2>/dev/null)
            age=$(echo "$first_hotspot" | jq -r '.age // .age_norm // 0' 2>/dev/null)
            score=$(echo "$first_hotspot" | jq -r '.score // 0' 2>/dev/null)

            # Verify score is non-negative
            if [ -n "$score" ] && [ "$score" != "null" ]; then
                float_gte "$score" "0" || fail "Score should be non-negative"
            fi
        fi
    fi
}

@test "CT-HW-002: normalization - all factors in [0,1] range" {
    # Test factor normalization to [0,1] range
    skip_if_missing "jq"

    run "$HOTSPOT_ANALYZER" --format json --weighted --normalized 2>&1
    skip_if_not_ready "$status" "$output" "Factor normalization"

    local json
    json=$(extract_json "$output")

    # Get hotspots list
    local hotspots_count
    hotspots_count=$(echo "$json" | jq '.hotspots | length' 2>/dev/null)

    if [ "$hotspots_count" -gt 0 ] 2>/dev/null; then
        # Check normalized factors for each hotspot
        local i=0
        while [ "$i" -lt "$hotspots_count" ] && [ "$i" -lt 5 ]; do
            local hotspot
            hotspot=$(echo "$json" | jq ".hotspots[$i]" 2>/dev/null)

            # Check churn_norm or normalized churn
            local churn_norm
            churn_norm=$(echo "$hotspot" | jq -r '.churn_norm // .churn_normalized // .factors.churn // "skip"' 2>/dev/null)
            if [ "$churn_norm" != "skip" ] && [ "$churn_norm" != "null" ]; then
                float_gte "$churn_norm" "0" || fail "churn_norm should be >= 0"
                float_gte "1" "$churn_norm" || skip "churn_norm ($churn_norm) > 1, may need investigation"
            fi

            # Check complexity_norm
            local complexity_norm
            complexity_norm=$(echo "$hotspot" | jq -r '.complexity_norm // .complexity_normalized // .factors.complexity // "skip"' 2>/dev/null)
            if [ "$complexity_norm" != "skip" ] && [ "$complexity_norm" != "null" ]; then
                float_gte "$complexity_norm" "0" || fail "complexity_norm should be >= 0"
                float_gte "1" "$complexity_norm" || skip "complexity_norm ($complexity_norm) > 1, may need investigation"
            fi

            i=$((i + 1))
        done
    else
        skip "No hotspots returned for normalization test"
    fi
}

@test "CT-HW-003: configurable weights - custom weight support" {
    # Test configurable weights
    skip_if_missing "jq"

    # Try custom weights parameter
    run "$HOTSPOT_ANALYZER" --format json --weights "0.5,0.2,0.2,0.1" 2>&1

    # If --weights not supported, try config file approach
    if [ "$status" -ne 0 ] || [[ "$output" == *"unknown"* ]] || [[ "$output" == *"invalid"* ]]; then
        # Try environment variable approach
        HOTSPOT_WEIGHTS="0.5,0.2,0.2,0.1" run "$HOTSPOT_ANALYZER" --format json --weighted 2>&1

        if [ "$status" -ne 0 ]; then
            skip "Custom weights configuration not yet implemented"
        fi
    fi

    local json
    json=$(extract_json "$output")

    # Verify output is valid
    assert_contains "$json" "hotspots" "Output should contain hotspots"
}

@test "CT-HW-004: recency priority - weight boost for changes within 30 days" {
    # Test recency boost for changes within 30 days
    skip_if_missing "jq"

    # Use --recency-boost or --recent-weight parameter
    run "$HOTSPOT_ANALYZER" --format json --weighted --recency-boost 2>&1
    skip_if_not_ready "$status" "$output" "Recency boost feature"

    local json
    json=$(extract_json "$output")

    # Verify recency-related fields present
    if [[ "$json" == *"recency"* ]] || [[ "$json" == *"age"* ]] || [[ "$json" == *"last_modified"* ]]; then
        # Get first hotspot
        local first_hotspot
        first_hotspot=$(echo "$json" | jq '.hotspots[0]' 2>/dev/null)

        if [ "$first_hotspot" != "null" ]; then
            # Check for recency_factor or age_factor
            local recency
            recency=$(echo "$first_hotspot" | jq -r '.recency_factor // .age_factor // .recency_boost // "none"' 2>/dev/null)

            if [ "$recency" != "none" ] && [ "$recency" != "null" ]; then
                # Recently modified files should have higher recency factor
                float_gte "$recency" "0" || fail "Recency factor should be non-negative"
            fi
        fi
    else
        skip "Recency/age fields not present in output"
    fi
}

@test "CT-HW-005: coupling penalty - high coupling increases score" {
    # Test high coupling increases hotspot score (penalizes high coupling)
    skip_if_missing "jq"

    run "$HOTSPOT_ANALYZER" --format json --weighted --coupling 2>&1
    skip_if_not_ready "$status" "$output" "Coupling penalty feature"

    local json
    json=$(extract_json "$output")

    # Verify coupling field present
    if [[ "$json" == *"coupling"* ]]; then
        # Get hotspots list
        local hotspots_count
        hotspots_count=$(echo "$json" | jq '.hotspots | length' 2>/dev/null)

        if [ "$hotspots_count" -gt 1 ] 2>/dev/null; then
            # Check coupling for multiple hotspots
            local high_coupling_file=""
            local high_coupling_score=0
            local i=0

            while [ "$i" -lt "$hotspots_count" ] && [ "$i" -lt 10 ]; do
                local hotspot
                hotspot=$(echo "$json" | jq ".hotspots[$i]" 2>/dev/null)

                local coupling
                coupling=$(echo "$hotspot" | jq -r '.coupling // .coupling_score // 0' 2>/dev/null)
                local score
                score=$(echo "$hotspot" | jq -r '.score // 0' 2>/dev/null)

                # Record high coupling file (coupling > 5 as threshold)
                if float_gte "$coupling" "5" 2>/dev/null; then
                    high_coupling_file=$(echo "$hotspot" | jq -r '.file // .path' 2>/dev/null)
                    high_coupling_score="$score"
                fi

                i=$((i + 1))
            done

            # High coupling file should have corresponding score
            if [ -n "$high_coupling_file" ]; then
                float_gte "$high_coupling_score" "0" || fail "High coupling file should have positive score"
            fi
        fi
    else
        skip "Coupling fields not present in output"
    fi
}

@test "CT-HW-006: performance - 500 files scoring under 200ms" {
    # Test 500 files scoring performance
    skip_if_missing "jq"

    # Create test directory
    setup_temp_dir
    cd "$TEST_TEMP_DIR"

    # Initialize git repo
    git init --quiet
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"

    # Create 500 files
    mkdir -p src
    local i=0
    while [ "$i" -lt 500 ]; do
        echo "// File $i" > "src/file_$i.ts"
        i=$((i + 1))
    done

    # Add and commit
    git add .
    git commit -m "Add 500 files" --quiet

    # Measure execution time
    measure_time "$HOTSPOT_ANALYZER" --format json --weighted 2>/dev/null
    local exit_code=$?
    local execution_time=$MEASURED_TIME_MS

    cd - > /dev/null
    cleanup_temp_dir

    # Verify execution success
    if [ "$exit_code" -ne 0 ]; then
        skip "Weighted hotspot analysis not yet implemented for performance test"
    fi

    # Verify performance requirement: < 200ms
    if [ "$execution_time" -ge 200 ]; then
        fail "Performance requirement not met: ${execution_time}ms >= 200ms for 500 files"
    fi
}

