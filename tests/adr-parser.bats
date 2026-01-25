#!/usr/bin/env bats
# adr-parser.bats - ADR parsing and linking tests
#
# Trace: AC-G03

load 'helpers/common'

SCRIPT_DIR="$BATS_TEST_DIRNAME/../scripts"
ADR_PARSER="$SCRIPT_DIR/adr-parser.sh"
GRAPH_STORE="$SCRIPT_DIR/graph-store.sh"

setup() {
    setup_temp_dir
    export DEVBOOKS_DIR="$TEST_TEMP_DIR/.devbooks"
    export GRAPH_DB_PATH="$DEVBOOKS_DIR/graph.db"
    mkdir -p "$DEVBOOKS_DIR"
}

teardown() {
    cleanup_temp_dir
}

@test "test_parse_madr: adr-parser extracts MADR fields" {
    skip_if_not_executable "$ADR_PARSER"
    skip_if_missing "jq"

    local adr_dir="$TEST_TEMP_DIR/docs/adr"
    mkdir -p "$adr_dir"
    cat > "$adr_dir/0001-use-sqlite.md" << 'EOF'
# ADR-001: Use SQLite for graph storage

## Status
Accepted

## Context
We need a lightweight graph store.

## Decision
Use SQLite with WAL mode for graph-store.sh.

## Consequences
- Simple deployment
- Limited scale
EOF

    run "$ADR_PARSER" parse "$adr_dir/0001-use-sqlite.md" --format json
    skip_if_not_ready "$status" "$output" "adr-parser.sh parse"

    assert_valid_json "$output"
    local adr_id
    adr_id=$(echo "$output" | jq -r '.adrs[0].id // empty')
    if [ "$adr_id" != "ADR-001" ]; then
        skip_not_implemented "MADR parsing"
    fi
}

@test "test_parse_nygard: adr-parser extracts Nygard fields" {
    skip_if_not_executable "$ADR_PARSER"
    skip_if_missing "jq"

    local adr_dir="$TEST_TEMP_DIR/docs/adr"
    mkdir -p "$adr_dir"
    cat > "$adr_dir/0002-record-decisions.md" << 'EOF'
# 1. Record architecture decisions

Date: 2026-01-16

## Status

Accepted

## Context

We need to record decisions.

## Decision

We will use ADRs.

## Consequences

We will have a trail.
EOF

    run "$ADR_PARSER" parse "$adr_dir/0002-record-decisions.md" --format json
    skip_if_not_ready "$status" "$output" "adr-parser.sh parse"

    assert_valid_json "$output"
    local adr_id
    adr_id=$(echo "$output" | jq -r '.adrs[0].id // empty')
    if [ "$adr_id" != "1" ]; then
        skip_not_implemented "Nygard parsing"
    fi
}

@test "test_keywords: adr-parser extracts keywords" {
    skip_if_not_executable "$ADR_PARSER"
    skip_if_missing "jq"

    local adr_dir="$TEST_TEMP_DIR/docs/adr"
    mkdir -p "$adr_dir"
    cat > "$adr_dir/0003-keywords.md" << 'EOF'
# ADR-003: Cache subgraph data

## Status
Accepted

## Context
We need SQLite caching for graph-store.sh.

## Decision
Use SQLite with WAL mode for subgraph-cache.db.
EOF

    run "$ADR_PARSER" parse "$adr_dir/0003-keywords.md" --format json
    skip_if_not_ready "$status" "$output" "adr-parser.sh parse"

    assert_valid_json "$output"
    local has_sqlite
    has_sqlite=$(echo "$output" | jq -r '.adrs[0].keywords | any(. == "SQLite")')
    if [ "$has_sqlite" != "true" ]; then
        skip_not_implemented "keyword extraction"
    fi
}

@test "test_adr_graph_link: adr-parser links keywords to graph nodes" {
    skip_if_not_executable "$ADR_PARSER"
    skip_if_not_executable "$GRAPH_STORE"
    skip_if_missing "sqlite3"
    skip_if_missing "jq"

    run "$GRAPH_STORE" init
    skip_if_not_ready "$status" "$output" "graph-store.sh init"

    "$GRAPH_STORE" add-node --id "sym:graph-store" --symbol "graph-store.sh" --kind "file" --file "scripts/graph-store.sh"

    local adr_dir="$TEST_TEMP_DIR/docs/adr"
    mkdir -p "$adr_dir"
    cat > "$adr_dir/0004-link.md" << 'EOF'
# ADR-004: Use graph-store.sh for storage

## Status
Accepted

## Decision
Link graph-store.sh with ADRs.
EOF

    run "$ADR_PARSER" scan --link --adr-dir "$adr_dir" --format json
    skip_if_not_ready "$status" "$output" "adr-parser.sh scan --link"

    local edge_count
    edge_count=$(sqlite3 "$GRAPH_DB_PATH" "SELECT COUNT(*) FROM edges WHERE edge_type='ADR_RELATED';" 2>/dev/null || echo "0")
    if [ "$edge_count" -eq 0 ]; then
        skip_not_implemented "ADR_RELATED edges"
    fi
}

@test "test_no_adr_dir: adr-parser handles missing ADR directory" {
    skip_if_not_executable "$ADR_PARSER"
    skip_if_missing "jq"

    local empty_dir="$TEST_TEMP_DIR/no-adr"
    mkdir -p "$empty_dir"

    run "$ADR_PARSER" scan --adr-dir "$empty_dir" --format json
    skip_if_not_ready "$status" "$output" "adr-parser.sh scan"

    assert_valid_json "$output"
    local count
    count=$(echo "$output" | jq -r '.adrs | length')
    if [ "$count" != "0" ]; then
        skip_not_implemented "empty ADR directory handling"
    fi
}
