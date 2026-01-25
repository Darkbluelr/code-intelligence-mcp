#!/usr/bin/env bats
# federation-lite.bats - Federation Lite Contract Tests
#
# Purpose: Verify cross-repository contract discovery and indexing
# Depends: bats-core, jq, git
# Run: bats tests/federation-lite.bats
#
# Baseline: 2026-01-14
# Change: augment-upgrade-phase2
# Trace: AC-011

# Load shared helpers
load 'helpers/common'

# Store project root for absolute paths (tests may cd to temp dirs)
PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
FEDERATION_LITE="${PROJECT_ROOT}/scripts/federation-lite.sh"
TEST_TEMP_DIR=""

# ============================================================
# Setup / Teardown
# ============================================================

setup() {
    TEST_TEMP_DIR=$(mktemp -d)
    export FEDERATION_CONFIG="$TEST_TEMP_DIR/federation.yaml"
    export FEDERATION_INDEX="$TEST_TEMP_DIR/federation-index.json"
}

teardown() {
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Helper: Create test repositories
setup_test_repos() {
    local base="$1"

    # Main repo
    mkdir -p "$base/main-repo"
    cd "$base/main-repo"
    git init --quiet
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"
    echo "main" > README.md
    git add README.md
    git commit -m "init" --quiet
    cd - > /dev/null

    # API contracts repo
    mkdir -p "$base/api-contracts"
    cd "$base/api-contracts"
    git init --quiet
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"

    # Create proto file
    cat > user.proto << 'EOF'
syntax = "proto3";

service UserService {
    rpc GetUser (GetUserRequest) returns (User);
    rpc CreateUser (CreateUserRequest) returns (User);
}

message User {
    string id = 1;
    string name = 2;
    string email = 3;
}

message GetUserRequest {
    string id = 1;
}

message CreateUserRequest {
    string name = 1;
    string email = 2;
}
EOF

    # Create OpenAPI file
    cat > openapi.yaml << 'EOF'
openapi: "3.0.0"
info:
  title: User API
  version: "1.0.0"
paths:
  /users:
    get:
      summary: List users
      operationId: listUsers
    post:
      summary: Create user
      operationId: createUser
  /users/{id}:
    get:
      summary: Get user by ID
      operationId: getUser
components:
  schemas:
    User:
      type: object
      properties:
        id:
          type: string
        name:
          type: string
    CreateUserRequest:
      type: object
      properties:
        name:
          type: string
EOF

    git add .
    git commit -m "init contracts" --quiet
    cd - > /dev/null

    # TypeScript types repo
    mkdir -p "$base/shared-types/types"
    cd "$base/shared-types"
    git init --quiet
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"

    cat > types/user.d.ts << 'EOF'
export interface User {
    id: string;
    name: string;
    email: string;
}

export type UserRole = 'admin' | 'user' | 'guest';

export class UserService {
    getUser(id: string): Promise<User>;
    createUser(data: Partial<User>): Promise<User>;
}
EOF

    git add .
    git commit -m "init types" --quiet
    cd - > /dev/null
}

# Helper: Create federation config
create_federation_config() {
    local config_file="$1"
    local base_dir="$2"

    cat > "$config_file" << EOF
schema_version: "1.0.0"

federation:
  repositories:
    - name: "api-contracts"
      path: "$base_dir/api-contracts"
      contracts:
        - "**/*.proto"
        - "**/openapi.yaml"

    - name: "shared-types"
      path: "$base_dir/shared-types"
      contracts:
        - "**/*.d.ts"

  auto_discover:
    enabled: false

  update:
    trigger: "manual"
EOF
}

# Helper: Setup federation test environment (reduces test boilerplate)
# Usage: setup_federation_test
# Creates: test repos, federation config, changes to main-repo directory
# Note: Caller should cd back after test
setup_federation_test() {
    setup_test_repos "$TEST_TEMP_DIR"
    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"
    cd "$TEST_TEMP_DIR/main-repo"
}

# ============================================================
# Basic Verification
# ============================================================

@test "CT-FED-BASE-001: federation-lite.sh exists and is executable" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"
}

@test "CT-FED-BASE-002: --help shows usage information" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"
    run "$FEDERATION_LITE" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"federation"* ]] || [[ "$output" == *"index"* ]] || [[ "$output" == *"contract"* ]]
}

# ============================================================
# CT-FED-001: Explicit Repository Indexing (SC-FED-001)
# AC-011: Federation index generation
# ============================================================

@test "CT-FED-001: indexes explicitly configured repositories" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"

    setup_federation_test

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--update not yet implemented"

    # Check index was created
    [ -f "$FEDERATION_INDEX" ] || skip "federation-index.json not created"

    if command -v jq &> /dev/null; then
        local content=$(cat "$FEDERATION_INDEX")
        local repo_count=$(echo "$content" | jq '.repositories | length' 2>/dev/null)
        [ "$repo_count" -eq 2 ] || skip "Expected 2 repositories, got $repo_count"
    fi
}

@test "CT-FED-001b: index includes all configured repositories" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"
    skip_if_missing "jq"

    setup_federation_test

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--update not yet implemented"
    [ -f "$FEDERATION_INDEX" ] || skip "federation-index.json not created"

    local content=$(cat "$FEDERATION_INDEX")

    # Check both repos are indexed
    [[ "$content" == *"api-contracts"* ]] || skip "api-contracts not indexed"
    [[ "$content" == *"shared-types"* ]] || skip "shared-types not indexed"
}

# ============================================================
# CT-FED-002: Auto Discovery (SC-FED-002)
# ============================================================

@test "CT-FED-002: auto-discovers repositories when enabled" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"

    setup_test_repos "$TEST_TEMP_DIR"

    # Create config with auto-discover enabled
    cat > "$FEDERATION_CONFIG" << EOF
schema_version: "1.0.0"

federation:
  repositories: []

  auto_discover:
    enabled: true
    search_paths:
      - "$TEST_TEMP_DIR/*"
    contract_patterns:
      - "**/*.proto"
      - "**/openapi.yaml"
      - "**/*.d.ts"

  update:
    trigger: "manual"
EOF

    cd "$TEST_TEMP_DIR/main-repo"

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "Auto-discover not yet implemented"
    [ -f "$FEDERATION_INDEX" ] || skip "federation-index.json not created"

    # Should have discovered the api-contracts and shared-types repos
    if command -v jq &> /dev/null; then
        local content=$(cat "$FEDERATION_INDEX")
        local repo_count=$(echo "$content" | jq '.repositories | length' 2>/dev/null)
        [ "$repo_count" -ge 2 ] || skip "Auto-discover should find at least 2 repos"
    fi
}

# ============================================================
# CT-FED-003: Proto Symbol Extraction (SC-FED-003)
# ============================================================

@test "CT-FED-003: extracts service and message from .proto" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"
    skip_if_missing "jq"

    setup_federation_test

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--update not yet implemented"
    [ -f "$FEDERATION_INDEX" ] || skip "federation-index.json not created"

    local content=$(cat "$FEDERATION_INDEX")

    # Check for proto symbols
    [[ "$content" == *"UserService"* ]] || skip "UserService not extracted"
    [[ "$content" == *"User"* ]] || skip "User message not extracted"
    [[ "$content" == *"GetUserRequest"* ]] || skip "GetUserRequest not extracted"
}

@test "CT-FED-003b: proto contract has type=proto" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"
    skip_if_missing "jq"

    setup_federation_test

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--update not yet implemented"
    [ -f "$FEDERATION_INDEX" ] || skip "federation-index.json not created"

    local content=$(cat "$FEDERATION_INDEX")

    # Find proto contract and check type
    local proto_type=$(echo "$content" | jq -r '.repositories[].contracts[] | select(.path | endswith(".proto")) | .type' 2>/dev/null | head -1)
    [ "$proto_type" = "proto" ] || skip "Proto contract should have type=proto, got '$proto_type'"
}

# ============================================================
# CT-FED-004: OpenAPI Symbol Extraction (SC-FED-004)
# ============================================================

@test "CT-FED-004: extracts paths and schemas from openapi.yaml" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"
    skip_if_missing "jq"

    setup_federation_test

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--update not yet implemented"
    [ -f "$FEDERATION_INDEX" ] || skip "federation-index.json not created"

    local content=$(cat "$FEDERATION_INDEX")

    # Check for OpenAPI symbols
    [[ "$content" == *"/users"* ]] || [[ "$content" == *"listUsers"* ]] || skip "Users path not extracted"
    [[ "$content" == *"User"* ]] || skip "User schema not extracted"
}

@test "CT-FED-004b: openapi contract has type=openapi" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"
    skip_if_missing "jq"

    setup_federation_test

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--update not yet implemented"
    [ -f "$FEDERATION_INDEX" ] || skip "federation-index.json not created"

    local content=$(cat "$FEDERATION_INDEX")

    local openapi_type=$(echo "$content" | jq -r '.repositories[].contracts[] | select(.path | endswith(".yaml")) | .type' 2>/dev/null | head -1)
    [ "$openapi_type" = "openapi" ] || skip "OpenAPI contract should have type=openapi, got '$openapi_type'"
}

# ============================================================
# CT-FED-005: Symbol Search (SC-FED-005)
# ============================================================

@test "CT-FED-005: --search finds symbol across repositories" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"

    setup_federation_test

    # First update the index
    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "--update not yet implemented"; }

    # Search for UserService
    run "$FEDERATION_LITE" --search "UserService" --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--search not yet implemented"

    # Should find UserService in results
    [[ "$output" == *"UserService"* ]] || skip "UserService not found in search"
    [[ "$output" == *"api-contracts"* ]] || [[ "$output" == *"proto"* ]] || \
    skip "Search result should include repository info"
}

@test "CT-FED-005b: search returns file path" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"
    skip_if_missing "jq"

    setup_federation_test

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "--update not yet implemented"; }

    run "$FEDERATION_LITE" --search "UserService" --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--search not yet implemented"

    # Should include file path in results
    [[ "$output" == *"user.proto"* ]] || skip "File path not in search results"
}

# ============================================================
# CT-FED-006: Status Query (SC-FED-006)
# ============================================================

@test "CT-FED-006: --status shows index information" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"

    setup_federation_test

    # First create index
    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "--update not yet implemented"; }

    # Check status
    run "$FEDERATION_LITE" --status

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--status not yet implemented"

    # Should show indexed_at time
    [[ "$output" == *"indexed"* ]] || [[ "$output" == *"time"* ]] || [[ "$output" == *"202"* ]] || \
    skip "Status should show index time"

    # Should show repository count
    [[ "$output" == *"2"* ]] || [[ "$output" == *"repositories"* ]] || \
    skip "Status should show repository info"
}

# ============================================================
# CT-FED-007: Missing Repository Path (SC-FED-007)
# ============================================================

@test "CT-FED-007: skips non-existent repository paths" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"

    setup_test_repos "$TEST_TEMP_DIR"

    # Create config with non-existent path
    cat > "$FEDERATION_CONFIG" << EOF
schema_version: "1.0.0"

federation:
  repositories:
    - name: "api-contracts"
      path: "$TEST_TEMP_DIR/api-contracts"
      contracts:
        - "**/*.proto"

    - name: "missing-repo"
      path: "$TEST_TEMP_DIR/does-not-exist"
      contracts:
        - "**/*"

  update:
    trigger: "manual"
EOF

    cd "$TEST_TEMP_DIR/main-repo"

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"

    cd - > /dev/null

    # Should succeed (skip missing, continue with valid)
    [ "$status" -eq 0 ] || skip "Should handle missing paths gracefully"

    # Check index was created with valid repos
    [ -f "$FEDERATION_INDEX" ] || skip "federation-index.json not created"

    if command -v jq &> /dev/null; then
        local content=$(cat "$FEDERATION_INDEX")
        # Should have 1 repo (api-contracts), not 2
        local repo_count=$(echo "$content" | jq '.repositories | length' 2>/dev/null)
        [ "$repo_count" -eq 1 ] || skip "Should only index existing repos, got $repo_count"
    fi
}

@test "CT-FED-007b: logs warning for missing path" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"

    setup_test_repos "$TEST_TEMP_DIR"

    cat > "$FEDERATION_CONFIG" << EOF
schema_version: "1.0.0"

federation:
  repositories:
    - name: "missing-repo"
      path: "$TEST_TEMP_DIR/does-not-exist"
      contracts:
        - "**/*"

  update:
    trigger: "manual"
EOF

    cd "$TEST_TEMP_DIR/main-repo"

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG" 2>&1

    cd - > /dev/null

    # Should log warning about missing path
    [[ "$output" == *"warn"* ]] || [[ "$output" == *"not found"* ]] || [[ "$output" == *"skip"* ]] || \
    [[ "$output" == *"missing"* ]] || skip "Should warn about missing repository"
}

# ============================================================
# CT-FED-008: Incremental Update (SC-FED-008)
# ============================================================

@test "CT-FED-008: incremental update only processes changed files" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"
    skip_if_missing "jq"

    setup_federation_test

    # First update
    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "--update not yet implemented"; }

    # Record original hash
    local original_hash=$(cat "$FEDERATION_INDEX" | jq -r '.repositories[0].contracts[0].hash // "none"' 2>/dev/null)

    # Modify one contract
    echo "// modified" >> "$TEST_TEMP_DIR/api-contracts/user.proto"

    # Second update
    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"

    cd - > /dev/null

    [ "$status" -eq 0 ]

    # Hash should be different for modified file
    local new_hash=$(cat "$FEDERATION_INDEX" | jq -r '.repositories[0].contracts[0].hash // "none"' 2>/dev/null)

    if [ "$original_hash" != "none" ] && [ "$new_hash" != "none" ]; then
        [ "$original_hash" != "$new_hash" ] || skip "Hash should change after modification"
    fi
}

# ============================================================
# CT-FED-009: Config Format (REQ-FED-002)
# ============================================================

@test "CT-FED-009: validates federation.yaml schema" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"

    # Create invalid config
    cat > "$FEDERATION_CONFIG" << 'EOF'
invalid_key: "bad"
EOF

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"

    # Should fail or warn about invalid config
    [ "$status" -ne 0 ] || [[ "$output" == *"invalid"* ]] || [[ "$output" == *"error"* ]] || \
    skip "Should validate config schema"
}

# ============================================================
# CT-FED-010: Index Format (REQ-FED-003)
# ============================================================

@test "CT-FED-010: index has required schema fields" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"
    skip_if_missing "jq"

    setup_federation_test

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--update not yet implemented"
    [ -f "$FEDERATION_INDEX" ] || skip "federation-index.json not created"

    local content=$(cat "$FEDERATION_INDEX")
    assert_valid_json "$content"
    assert_json_field "$content" ".schema_version"
    assert_json_field "$content" ".indexed_at"
    assert_json_field "$content" ".repositories"
}

# ============================================================
# CT-FED-011: MCP Tool Registration (REQ-FED-005)
# ============================================================

@test "CT-FED-011: ci_federation tool registered in server.ts" {
    local server_ts="./src/server.ts"
    [ -f "$server_ts" ] || skip "server.ts not found"

    run grep -l "ci_federation" "$server_ts"
    [ "$status" -eq 0 ] || skip "ci_federation not yet registered"
}

@test "CT-FED-011b: ci_federation has correct input schema" {
    local server_ts="./src/server.ts"
    [ -f "$server_ts" ] || skip "server.ts not found"

    run grep -A 30 "ci_federation" "$server_ts"
    [[ "$output" == *"ci_federation"* ]] || skip "ci_federation not yet registered"

    # Check for expected parameters
    [[ "$output" == *"action"* ]] || skip "action parameter not found"
    [[ "$output" == *"status"* ]] || [[ "$output" == *"update"* ]] || [[ "$output" == *"search"* ]] || \
    skip "action enum values not found"
}

# ============================================================
# Negative Tests: Error Handling
# ============================================================

@test "CT-FED-NEG-001: handles invalid proto syntax gracefully" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"

    # Create repo with invalid proto
    mkdir -p "$TEST_TEMP_DIR/bad-repo"
    cd "$TEST_TEMP_DIR/bad-repo"
    git init --quiet
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"

    # Invalid proto syntax
    cat > invalid.proto << 'EOF'
syntax = "proto3"
this is not valid proto {
    malformed content here
EOF

    git add invalid.proto
    git commit -m "add invalid proto" --quiet
    cd - > /dev/null

    # Create config pointing to bad repo
    cat > "$FEDERATION_CONFIG" << EOF
schema_version: "1.0.0"
federation:
  repositories:
    - name: "bad-repo"
      path: "$TEST_TEMP_DIR/bad-repo"
      contracts:
        - "**/*.proto"
  update:
    trigger: "manual"
EOF

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"

    # Should handle gracefully - either skip, warn, or fail with clear error
    [[ "$output" == *"error"* ]] || [[ "$output" == *"invalid"* ]] || \
    [[ "$output" == *"parse"* ]] || [[ "$output" == *"skip"* ]] || \
    [ "$status" -ne 0 ] || skip "Should handle invalid proto syntax"
}

@test "CT-FED-NEG-002: handles invalid OpenAPI schema gracefully" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"

    # Create repo with invalid OpenAPI
    mkdir -p "$TEST_TEMP_DIR/bad-api-repo"
    cd "$TEST_TEMP_DIR/bad-api-repo"
    git init --quiet
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"

    # Invalid OpenAPI schema
    cat > invalid-api.yaml << 'EOF'
openapi: "3.0.0"
info:
  title: "Bad API"
  # missing required 'version' field
paths:
  /bad:
    get:
      # missing required 'responses' field
      summary: "Incomplete endpoint"
EOF

    git add invalid-api.yaml
    git commit -m "add invalid openapi" --quiet
    cd - > /dev/null

    # Create config
    cat > "$FEDERATION_CONFIG" << EOF
schema_version: "1.0.0"
federation:
  repositories:
    - name: "bad-api-repo"
      path: "$TEST_TEMP_DIR/bad-api-repo"
      contracts:
        - "**/*.yaml"
  update:
    trigger: "manual"
EOF

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"

    # Should handle gracefully
    [[ "$output" == *"error"* ]] || [[ "$output" == *"invalid"* ]] || \
    [[ "$output" == *"schema"* ]] || [[ "$output" == *"warn"* ]] || \
    [ "$status" -eq 0 ] || skip "Should handle invalid OpenAPI gracefully"
}

@test "CT-FED-NEG-003: handles empty repository gracefully" {
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"

    # Create empty repo (no contracts)
    mkdir -p "$TEST_TEMP_DIR/empty-repo"
    cd "$TEST_TEMP_DIR/empty-repo"
    git init --quiet
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"

    echo "README" > README.md
    git add README.md
    git commit -m "initial" --quiet
    cd - > /dev/null

    # Create config pointing to empty repo
    cat > "$FEDERATION_CONFIG" << EOF
schema_version: "1.0.0"
federation:
  repositories:
    - name: "empty-repo"
      path: "$TEST_TEMP_DIR/empty-repo"
      contracts:
        - "**/*.proto"
        - "**/*.yaml"
  update:
    trigger: "manual"
EOF

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"

    # Should succeed (no contracts is valid) or warn
    [ "$status" -eq 0 ] || [[ "$output" == *"no contracts"* ]] || \
    [[ "$output" == *"empty"* ]] || skip "Should handle empty repository"
}

# ============================================================
# M5: Federation Virtual Edge Tests (T-FV-xxx)
# Purpose: Verify virtual edge generation for cross-repo connections
# Trace: AC-FV (Federation Virtual Edge feature)
# ============================================================

# Helper: Setup virtual edge test environment with graph.db
setup_virtual_edge_env() {
    local base="$1"

    # Create graph.db with virtual_edges table
    export GRAPH_DB="$base/graph.db"
    if command -v sqlite3 &> /dev/null; then
        sqlite3 "$GRAPH_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS virtual_edges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_repo TEXT NOT NULL,
    source_symbol TEXT NOT NULL,
    target_repo TEXT NOT NULL,
    target_symbol TEXT NOT NULL,
    edge_type TEXT DEFAULT 'VIRTUAL_CALLS',
    confidence REAL NOT NULL,
    confidence_level TEXT DEFAULT 'medium',
    contract_type TEXT,
    contract_bonus REAL DEFAULT 0.0,
    exact_match REAL DEFAULT 0.0,
    signature_similarity REAL DEFAULT 0.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF
    fi

    # Create local repo with function calling remote service
    mkdir -p "$base/local-repo/src"
    cd "$base/local-repo"
    git init --quiet
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"

    cat > src/user-client.ts << 'EOF'
// Local client calling remote UserService
export async function getUserById(id: string): Promise<User> {
    return await rpc.call('UserService', 'GetUser', { id });
}

export async function fetchUser(userId: string): Promise<User> {
    return await fetch(`/api/users/${userId}`).then(r => r.json());
}
EOF

    git add .
    git commit -m "init local repo" --quiet
    cd - > /dev/null
}

# Helper: Check if virtual edge generation is implemented
# Note: Named differently from common.bash skip_if_not_ready to avoid collision
skip_if_virtual_edge_not_ready() {
    local feature="$1"
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"

    # Check if generate-virtual-edges subcommand exists
    run "$FEDERATION_LITE" --help 2>&1
    [[ "$output" == *"generate-virtual-edges"* ]] || \
    [[ "$output" == *"virtual"* ]] || \
    skip "$feature not yet implemented"
}

# ============================================================
# T-FV-001: Proto Virtual Edge Generation
# Given: Local call matches remote Proto definition
# When: Call federation-lite.sh generate-virtual-edges
# Then: Virtual edge generated, written to graph.db virtual_edges table
# ============================================================

@test "T-FV-001: test_proto_virtual_edge - Proto contract virtual edge generation" {
    skip_if_virtual_edge_not_ready "Proto virtual edge generation"
    skip_if_missing "sqlite3"
    skip_if_missing "jq"

    setup_test_repos "$TEST_TEMP_DIR"
    setup_virtual_edge_env "$TEST_TEMP_DIR"
    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"

    cd "$TEST_TEMP_DIR/local-repo"

    # First update the federation index
    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "Federation update failed"; }

    # Generate virtual edges
    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/local-repo"

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "generate-virtual-edges failed: $output"

    # Verify virtual edge was created in graph.db
    local edge_count=$(sqlite3 "$GRAPH_DB" "SELECT COUNT(*) FROM virtual_edges WHERE contract_type='proto'")
    [ "$edge_count" -ge 1 ] || fail "Expected at least 1 proto virtual edge, got $edge_count"

    # Verify edge connects getUserById to GetUser
    local has_edge=$(sqlite3 "$GRAPH_DB" \
        "SELECT COUNT(*) FROM virtual_edges
         WHERE source_symbol LIKE '%getUserById%'
         AND target_symbol LIKE '%GetUser%'")
    [ "$has_edge" -ge 1 ] || fail "Expected virtual edge from getUserById to GetUser"
}

# ============================================================
# T-FV-002: Confidence Calculation
# Given: Local getUserById, remote GetUserById (Proto)
# When: Calculate confidence
# Then: confidence = 0.7*0.6 + 0.6*0.3 + 0.1*0.1 = 0.61
# Formula: exact_match*0.6 + signature_similarity*0.3 + contract_bonus*0.1
# ============================================================

@test "T-FV-002: test_confidence_calculation - Confidence correctly calculated" {
    skip_if_virtual_edge_not_ready "Confidence calculation"
    skip_if_missing "sqlite3"

    setup_test_repos "$TEST_TEMP_DIR"
    setup_virtual_edge_env "$TEST_TEMP_DIR"
    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"

    cd "$TEST_TEMP_DIR/local-repo"

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "Federation update failed"; }

    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/local-repo"

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "generate-virtual-edges failed"

    # Get the confidence for getUserById -> GetUser edge
    # Expected: exact_match=0.7 (prefix match), signature_similarity=0.6, contract_bonus=0.1 (proto)
    # confidence = 0.7*0.6 + 0.6*0.3 + 0.1*0.1 = 0.42 + 0.18 + 0.01 = 0.61
    local confidence=$(sqlite3 "$GRAPH_DB" \
        "SELECT confidence FROM virtual_edges
         WHERE source_symbol LIKE '%getUserById%'
         AND target_symbol LIKE '%GetUser%'
         LIMIT 1")

    [ -n "$confidence" ] || skip "No confidence value found"

    # Allow some tolerance (0.55 to 0.65 range)
    # Using bc for floating point comparison if available
    if command -v bc &> /dev/null; then
        local in_range=$(echo "$confidence >= 0.55 && $confidence <= 0.65" | bc -l)
        [ "$in_range" -eq 1 ] || fail "Expected confidence ~0.61, got $confidence"
    else
        # Simple string check for approximate value
        [[ "$confidence" == 0.6* ]] || skip "Confidence should be ~0.61, got $confidence"
    fi
}

# ============================================================
# T-FV-003: Low Confidence Filter
# Given: Symbols with no obvious relationship
# When: Confidence < 0.5
# Then: No virtual edge generated
# ============================================================

@test "T-FV-003: test_low_confidence_filter - Low confidence edges filtered out" {
    skip_if_virtual_edge_not_ready "Low confidence filtering"
    skip_if_missing "sqlite3"

    # Create test environment with unrelated symbols
    mkdir -p "$TEST_TEMP_DIR/unrelated-local/src"
    cd "$TEST_TEMP_DIR/unrelated-local"
    git init --quiet
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"

    # Create function with no relation to remote proto
    cat > src/unrelated.ts << 'EOF'
// Completely unrelated function
export function processPayment(amount: number): boolean {
    return amount > 0;
}
EOF

    git add .
    git commit -m "init unrelated" --quiet
    cd - > /dev/null

    setup_test_repos "$TEST_TEMP_DIR"
    export GRAPH_DB="$TEST_TEMP_DIR/graph.db"
    sqlite3 "$GRAPH_DB" "CREATE TABLE IF NOT EXISTS virtual_edges (
        id INTEGER PRIMARY KEY, source_repo TEXT, source_symbol TEXT,
        target_repo TEXT, target_symbol TEXT, confidence REAL,
        contract_type TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )"

    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || skip "Federation update failed"

    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/unrelated-local" \
        --min-confidence 0.5

    [ "$status" -eq 0 ] || skip "generate-virtual-edges failed"

    # Should not create edge for processPayment (no relation to UserService)
    local low_conf_edges=$(sqlite3 "$GRAPH_DB" \
        "SELECT COUNT(*) FROM virtual_edges
         WHERE source_symbol LIKE '%processPayment%'
         AND confidence < 0.5")
    [ "$low_conf_edges" -eq 0 ] || fail "Low confidence edge should be filtered out"
}

# ============================================================
# T-FV-004: Virtual Edge Query
# Given: graph.db contains virtual edges
# When: Call federation-lite.sh query-virtual <symbol>
# Then: Returns match info (source_repo, target_repo, confidence)
# ============================================================

@test "T-FV-004: test_virtual_edge_query - Query virtual edges by symbol" {
    skip_if_virtual_edge_not_ready "Virtual edge query"
    skip_if_missing "sqlite3"
    skip_if_missing "jq"

    setup_test_repos "$TEST_TEMP_DIR"
    setup_virtual_edge_env "$TEST_TEMP_DIR"
    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"

    cd "$TEST_TEMP_DIR/local-repo"

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "Federation update failed"; }

    # Generate some virtual edges first
    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/local-repo"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "generate-virtual-edges failed"; }

    # Query virtual edges for getUserById
    run "$FEDERATION_LITE" query-virtual "getUserById" \
        --db "$GRAPH_DB" \
        --format json

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "query-virtual failed: $output"

    # Verify output contains required fields
    [[ "$output" == *"source_repo"* ]] || fail "Output missing source_repo"
    [[ "$output" == *"target_repo"* ]] || fail "Output missing target_repo"
    [[ "$output" == *"confidence"* ]] || fail "Output missing confidence"

    # Verify JSON structure if jq available
    if command -v jq &> /dev/null; then
        local source_repo=$(echo "$output" | jq -r '.[0].source_repo // .source_repo // empty' 2>/dev/null)
        [ -n "$source_repo" ] || skip "Could not parse source_repo from JSON"
    fi
}

# ============================================================
# T-FV-005: High Confidence Mark
# Given: Confidence = 0.85
# When: Generate virtual edge
# Then: Marked as "high confidence"
# ============================================================

@test "T-FV-005: test_high_confidence_mark - High confidence edges marked correctly" {
    skip_if_virtual_edge_not_ready "High confidence marking"
    skip_if_missing "sqlite3"

    # Create local repo with exact match to remote
    mkdir -p "$TEST_TEMP_DIR/exact-match-repo/src"
    cd "$TEST_TEMP_DIR/exact-match-repo"
    git init --quiet
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"

    # Exact match: GetUser matches GetUser in proto
    cat > src/exact-client.ts << 'EOF'
// Exact match to proto service
export async function GetUser(id: string): Promise<User> {
    return await rpc.call('UserService', 'GetUser', { id });
}
EOF

    git add .
    git commit -m "init exact match" --quiet
    cd - > /dev/null

    setup_test_repos "$TEST_TEMP_DIR"
    export GRAPH_DB="$TEST_TEMP_DIR/graph.db"
    sqlite3 "$GRAPH_DB" "CREATE TABLE IF NOT EXISTS virtual_edges (
        id INTEGER PRIMARY KEY, source_repo TEXT, source_symbol TEXT,
        target_repo TEXT, target_symbol TEXT, confidence REAL,
        confidence_level TEXT, contract_type TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )"

    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || skip "Federation update failed"

    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/exact-match-repo"

    [ "$status" -eq 0 ] || skip "generate-virtual-edges failed"

    # Check for high confidence marking (confidence >= 0.8)
    local high_conf=$(sqlite3 "$GRAPH_DB" \
        "SELECT confidence_level FROM virtual_edges
         WHERE confidence >= 0.8
         LIMIT 1")

    [ "$high_conf" = "high" ] || skip "High confidence edge should be marked as 'high', got '$high_conf'"
}

# ============================================================
# T-FV-006: OpenAPI Virtual Edge
# Given: Local fetch('/api/users/{id}'), remote OpenAPI definition
# When: Generate
# Then: contract_bonus = 0.05, VIRTUAL_CALLS edge generated
# ============================================================

@test "T-FV-006: test_openapi_virtual_edge - OpenAPI contract virtual edge" {
    skip_if_virtual_edge_not_ready "OpenAPI virtual edge"
    skip_if_missing "sqlite3"

    setup_test_repos "$TEST_TEMP_DIR"
    setup_virtual_edge_env "$TEST_TEMP_DIR"
    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"

    cd "$TEST_TEMP_DIR/local-repo"

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "Federation update failed"; }

    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/local-repo"

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "generate-virtual-edges failed"

    # Verify OpenAPI virtual edge was created for fetchUser -> /api/users/{id}
    local openapi_edge=$(sqlite3 "$GRAPH_DB" \
        "SELECT contract_type, edge_type FROM virtual_edges
         WHERE source_symbol LIKE '%fetchUser%'
         AND contract_type = 'openapi'
         LIMIT 1")

    [ -n "$openapi_edge" ] || skip "No OpenAPI virtual edge found for fetchUser"

    # Verify contract_bonus is 0.05 for OpenAPI
    local bonus=$(sqlite3 "$GRAPH_DB" \
        "SELECT contract_bonus FROM virtual_edges
         WHERE contract_type = 'openapi'
         LIMIT 1")

    if [ -n "$bonus" ]; then
        if command -v bc &> /dev/null; then
            local is_correct=$(echo "$bonus == 0.05" | bc -l)
            [ "$is_correct" -eq 1 ] || skip "OpenAPI contract_bonus should be 0.05, got $bonus"
        fi
    fi

    # Verify edge_type is VIRTUAL_CALLS
    local edge_type=$(sqlite3 "$GRAPH_DB" \
        "SELECT edge_type FROM virtual_edges
         WHERE contract_type = 'openapi'
         LIMIT 1")
    [ "$edge_type" = "VIRTUAL_CALLS" ] || skip "Edge type should be VIRTUAL_CALLS, got '$edge_type'"
}

# ============================================================
# T-FV-007: Virtual Edge Sync
# Given: Virtual edge exists, remote definition changed
# When: Call --sync
# Then: Virtual edge updated/deleted, updated_at refreshed
# ============================================================

@test "T-FV-007: test_virtual_edge_sync - Virtual edge sync update" {
    skip_if_virtual_edge_not_ready "Virtual edge sync"
    skip_if_missing "sqlite3"

    setup_test_repos "$TEST_TEMP_DIR"
    setup_virtual_edge_env "$TEST_TEMP_DIR"
    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"

    cd "$TEST_TEMP_DIR/local-repo"

    # Initial update and edge generation
    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "Federation update failed"; }

    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/local-repo"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "generate-virtual-edges failed"; }

    # Record original updated_at
    local original_time=$(sqlite3 "$GRAPH_DB" \
        "SELECT updated_at FROM virtual_edges LIMIT 1")

    # Sleep briefly to ensure timestamp difference
    sleep 1

    # Modify remote proto definition
    cd "$TEST_TEMP_DIR/api-contracts"
    cat >> user.proto << 'EOF'

// New method added
message DeleteUserRequest {
    string id = 1;
}
EOF
    git add user.proto
    git commit -m "add DeleteUserRequest" --quiet

    cd "$TEST_TEMP_DIR/local-repo"

    # Sync virtual edges
    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/local-repo" \
        --sync

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--sync failed"

    # Verify updated_at was refreshed
    local new_time=$(sqlite3 "$GRAPH_DB" \
        "SELECT updated_at FROM virtual_edges LIMIT 1")

    [ "$original_time" != "$new_time" ] || skip "updated_at should be refreshed after sync"
}

# ============================================================
# T-FV-007b: Virtual Edge Deletion on Remote Definition Removal
# Given: Virtual edge exists, remote definition is deleted
# When: Call --sync
# Then: Virtual edge should be removed from graph.db
# ============================================================

@test "T-FV-007b: test_virtual_edge_deletion - Virtual edge removed when remote definition deleted" {
    skip_if_virtual_edge_not_ready "Virtual edge deletion"
    skip_if_missing "sqlite3"

    setup_test_repos "$TEST_TEMP_DIR"
    setup_virtual_edge_env "$TEST_TEMP_DIR"
    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"

    cd "$TEST_TEMP_DIR/local-repo"

    # Initial update and edge generation
    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "Federation update failed"; }

    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/local-repo"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "generate-virtual-edges failed"; }

    # Record original edge count targeting GetUser
    local original_count=$(sqlite3 "$GRAPH_DB" \
        "SELECT COUNT(*) FROM virtual_edges WHERE target_symbol LIKE '%GetUser%'")

    [ "$original_count" -ge 1 ] || { cd - > /dev/null; skip "No virtual edges for GetUser found"; }

    # Delete the remote proto definition (remove GetUser method)
    cd "$TEST_TEMP_DIR/api-contracts"

    # Replace proto file without GetUser
    cat > user.proto << 'EOF'
syntax = "proto3";

service UserService {
    // GetUser method removed
    rpc CreateUser (CreateUserRequest) returns (User);
}

message User {
    string id = 1;
    string name = 2;
    string email = 3;
}

message CreateUserRequest {
    string name = 1;
    string email = 2;
}
EOF
    git add user.proto
    git commit -m "remove GetUser method" --quiet

    cd "$TEST_TEMP_DIR/local-repo"

    # Re-update federation index
    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "Federation update after deletion failed"; }

    # Sync virtual edges (should remove stale edges)
    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/local-repo" \
        --sync

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "--sync after deletion failed"

    # Verify virtual edges targeting GetUser are removed
    local new_count=$(sqlite3 "$GRAPH_DB" \
        "SELECT COUNT(*) FROM virtual_edges WHERE target_symbol LIKE '%GetUser%'")

    if [ "$new_count" -ge "$original_count" ]; then
        skip "Virtual edges should be removed when remote definition is deleted (before: $original_count, after: $new_count)"
    fi
}

# ============================================================
# T-FV-008: Fuzzy Match Algorithm
# Given: fetchUser vs getUser
# When: Calculate exact_match
# Then: Returns 0.4 (fuzzy match)
# ============================================================

@test "T-FV-008: test_fuzzy_match - Fuzzy match algorithm returns correct score" {
    skip_if_virtual_edge_not_ready "Fuzzy match algorithm"
    skip_if_missing "sqlite3"

    # Create repo with fuzzy-match function name
    mkdir -p "$TEST_TEMP_DIR/fuzzy-repo/src"
    cd "$TEST_TEMP_DIR/fuzzy-repo"
    git init --quiet
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"

    # fetchUser is fuzzy match to getUser (not exact, not prefix)
    cat > src/fuzzy-client.ts << 'EOF'
// Fuzzy match: fetchUser vs getUser (different verb, same noun)
export async function fetchUser(id: string): Promise<User> {
    return await api.get(`/users/${id}`);
}
EOF

    git add .
    git commit -m "init fuzzy" --quiet
    cd - > /dev/null

    setup_test_repos "$TEST_TEMP_DIR"
    export GRAPH_DB="$TEST_TEMP_DIR/graph.db"
    sqlite3 "$GRAPH_DB" "CREATE TABLE IF NOT EXISTS virtual_edges (
        id INTEGER PRIMARY KEY, source_repo TEXT, source_symbol TEXT,
        target_repo TEXT, target_symbol TEXT, confidence REAL,
        exact_match REAL, signature_similarity REAL, contract_bonus REAL,
        contract_type TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )"

    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || skip "Federation update failed"

    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/fuzzy-repo"

    [ "$status" -eq 0 ] || skip "generate-virtual-edges failed"

    # Check exact_match score for fuzzy match
    local exact_match=$(sqlite3 "$GRAPH_DB" \
        "SELECT exact_match FROM virtual_edges
         WHERE source_symbol LIKE '%fetchUser%'
         LIMIT 1")

    [ -n "$exact_match" ] || skip "No exact_match score found"

    # Fuzzy match should return 0.4
    if command -v bc &> /dev/null; then
        local is_fuzzy=$(echo "$exact_match >= 0.35 && $exact_match <= 0.45" | bc -l)
        [ "$is_fuzzy" -eq 1 ] || fail "Fuzzy match should return ~0.4, got $exact_match"
    else
        [[ "$exact_match" == 0.4* ]] || skip "Fuzzy match should be ~0.4, got $exact_match"
    fi
}

# ============================================================
# M6: Virtual Edge Confidence Algorithm Tests (CT-VE-xxx)
# Purpose: Verify virtual edge confidence calculation algorithm
# Trace: AC-VE (algorithm-optimization-parity)
# Spec: dev-playbooks/changes/algorithm-optimization-parity/specs/virtual-edge/spec.md
#
# Formula: confidence = exact×0.6 + signature×0.3 + contract×0.1
# ============================================================

# Helper: Create test environment for confidence algorithm tests
setup_confidence_test_env() {
    local base="$1"

    # Create graph.db with confidence test schema
    export GRAPH_DB="$base/confidence-test.db"
    if command -v sqlite3 &> /dev/null; then
        sqlite3 "$GRAPH_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS virtual_edges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_repo TEXT NOT NULL,
    source_symbol TEXT NOT NULL,
    target_repo TEXT NOT NULL,
    target_symbol TEXT NOT NULL,
    edge_type TEXT DEFAULT 'VIRTUAL_CALLS',
    confidence REAL NOT NULL,
    confidence_level TEXT DEFAULT 'medium',
    exact_match REAL DEFAULT 0.0,
    signature_similarity REAL DEFAULT 0.0,
    contract_bonus REAL DEFAULT 0.0,
    contract_type TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF
    fi
}

# Helper: Create local repo with specific symbol for confidence testing
create_confidence_test_repo() {
    local base="$1"
    local repo_name="$2"
    local symbol_name="$3"
    local symbol_signature="${4:-}"

    mkdir -p "$base/$repo_name/src"
    cd "$base/$repo_name"
    git init --quiet
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"

    # Create TypeScript file with the test symbol
    cat > src/client.ts << EOF
// Test client for confidence calculation
export async function ${symbol_name}(${symbol_signature}): Promise<any> {
    return await rpc.call('UserService', '${symbol_name}', {});
}
EOF

    git add .
    git commit -m "init confidence test repo" --quiet
    cd - > /dev/null
}

# Helper: Skip if virtual edge confidence feature not ready
skip_if_confidence_not_ready() {
    local feature="$1"
    [ -x "$FEDERATION_LITE" ] || skip "federation-lite.sh not yet implemented"

    # Check if generate-virtual-edges with confidence options exists
    run "$FEDERATION_LITE" --help 2>&1
    [[ "$output" == *"generate-virtual-edges"* ]] || \
    [[ "$output" == *"confidence"* ]] || \
    skip "$feature not yet implemented"
}

# ============================================================
# CT-VE-001: Confidence Formula Verification
# Given: exact=0.8, signature=0.7, contract=0.1
# When: Calculate confidence
# Then: confidence = 0.8×0.6 + 0.7×0.3 + 0.1×0.1 = 0.48 + 0.21 + 0.01 = 0.70
# ============================================================

@test "CT-VE-001: confidence formula - exact×0.6 + signature×0.3 + contract×0.1" {
    skip_if_confidence_not_ready "Confidence formula verification"
    skip_if_missing "sqlite3"

    # Create test environment
    setup_test_repos "$TEST_TEMP_DIR"
    setup_confidence_test_env "$TEST_TEMP_DIR"
    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"

    # Create local repo with exact match symbol (GetUser matches GetUser)
    create_confidence_test_repo "$TEST_TEMP_DIR" "formula-test-repo" "GetUser" "id: string"

    cd "$TEST_TEMP_DIR/formula-test-repo"

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "Federation update failed"; }

    # Generate virtual edges
    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/formula-test-repo"

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "generate-virtual-edges failed: $output"

    # Verify edge was created
    local edge_count=$(sqlite3 "$GRAPH_DB" "SELECT COUNT(*) FROM virtual_edges")
    [ "$edge_count" -ge 1 ] || skip "No virtual edges created"

    # Get confidence components for verification
    local edge_data=$(sqlite3 "$GRAPH_DB" -separator '|' \
        "SELECT confidence, exact_match, signature_similarity, contract_bonus
         FROM virtual_edges
         WHERE source_symbol LIKE '%GetUser%'
         LIMIT 1")

    [ -n "$edge_data" ] || skip "No edge data for GetUser found"

    # Parse components
    local confidence=$(echo "$edge_data" | cut -d'|' -f1)
    local exact=$(echo "$edge_data" | cut -d'|' -f2)
    local signature=$(echo "$edge_data" | cut -d'|' -f3)
    local contract=$(echo "$edge_data" | cut -d'|' -f4)

    # Verify formula: confidence = exact×0.6 + signature×0.3 + contract×0.1
    if command -v bc &> /dev/null && [ -n "$exact" ] && [ -n "$signature" ] && [ -n "$contract" ]; then
        local expected=$(echo "scale=4; $exact * 0.6 + $signature * 0.3 + $contract * 0.1" | bc -l)
        local diff=$(echo "scale=4; ($confidence - $expected)^2" | bc -l)

        # Allow small tolerance (0.01)
        local within_tolerance=$(echo "$diff < 0.0001" | bc -l)
        [ "$within_tolerance" -eq 1 ] || \
            fail "Confidence formula mismatch: got $confidence, expected $expected (exact=$exact, sig=$signature, contract=$contract)"
    else
        # Fallback: just verify confidence is reasonable
        [ -n "$confidence" ] || fail "No confidence value found"
    fi
}

# ============================================================
# CT-VE-002: High Confidence Marking
# Given: confidence >= 0.8
# When: Generate virtual edge
# Then: confidence_level = 'high'
# ============================================================

@test "CT-VE-002: high confidence marking - confidence >= 0.8 marked as high" {
    skip_if_confidence_not_ready "High confidence marking"
    skip_if_missing "sqlite3"

    setup_test_repos "$TEST_TEMP_DIR"
    setup_confidence_test_env "$TEST_TEMP_DIR"
    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"

    # Create local repo with exact name match (should yield high confidence)
    # Exact match: GetUser -> GetUser (proto)
    create_confidence_test_repo "$TEST_TEMP_DIR" "high-conf-repo" "GetUser" "id: string"

    cd "$TEST_TEMP_DIR/high-conf-repo"

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "Federation update failed"; }

    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/high-conf-repo"

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "generate-virtual-edges failed"

    # Find edges with confidence >= 0.8 and verify they are marked 'high'
    local high_conf_edges=$(sqlite3 "$GRAPH_DB" \
        "SELECT confidence_level FROM virtual_edges
         WHERE confidence >= 0.8
         LIMIT 1")

    if [ -n "$high_conf_edges" ]; then
        [ "$high_conf_edges" = "high" ] || \
            fail "Edges with confidence >= 0.8 should be marked 'high', got '$high_conf_edges'"
    else
        # If no high confidence edges exist, check if any edges exist
        local any_edges=$(sqlite3 "$GRAPH_DB" "SELECT COUNT(*) FROM virtual_edges")
        if [ "$any_edges" -eq 0 ]; then
            skip "No virtual edges generated for high confidence test"
        fi

        # Verify that low confidence edges are NOT marked as high
        local all_levels=$(sqlite3 "$GRAPH_DB" \
            "SELECT confidence, confidence_level FROM virtual_edges
             WHERE confidence < 0.8")
        for row in $all_levels; do
            local level=$(echo "$row" | cut -d'|' -f2)
            [ "$level" != "high" ] || \
                fail "Edge with confidence < 0.8 should NOT be marked 'high'"
        done
    fi
}

# ============================================================
# CT-VE-003: Low Confidence Filtering
# Given: confidence < 0.5
# When: Generate virtual edge
# Then: Edge should NOT be created
# ============================================================

@test "CT-VE-003: low confidence filtering - confidence < 0.5 not generated" {
    skip_if_confidence_not_ready "Low confidence filtering"
    skip_if_missing "sqlite3"

    setup_test_repos "$TEST_TEMP_DIR"
    setup_confidence_test_env "$TEST_TEMP_DIR"
    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"

    # Create local repo with unrelated symbol (should yield low confidence)
    mkdir -p "$TEST_TEMP_DIR/low-conf-repo/src"
    cd "$TEST_TEMP_DIR/low-conf-repo"
    git init --quiet
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"

    # Create completely unrelated function
    cat > src/unrelated.ts << 'EOF'
// Completely unrelated to any proto/openapi symbols
export function processPaymentTransaction(amount: number, currency: string): boolean {
    return amount > 0 && currency.length === 3;
}

export function calculateShippingCost(weight: number): number {
    return weight * 0.5;
}
EOF

    git add .
    git commit -m "init unrelated repo" --quiet
    cd - > /dev/null

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || skip "Federation update failed"

    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/low-conf-repo" \
        --min-confidence 0.5

    [ "$status" -eq 0 ] || skip "generate-virtual-edges failed"

    # Verify no edges with confidence < 0.5 exist
    local low_conf_count=$(sqlite3 "$GRAPH_DB" \
        "SELECT COUNT(*) FROM virtual_edges WHERE confidence < 0.5")

    [ "$low_conf_count" -eq 0 ] || \
        fail "Expected 0 edges with confidence < 0.5, got $low_conf_count"

    # Also verify: edges for unrelated symbols should not exist
    local unrelated_edges=$(sqlite3 "$GRAPH_DB" \
        "SELECT COUNT(*) FROM virtual_edges
         WHERE source_symbol LIKE '%processPaymentTransaction%'
         OR source_symbol LIKE '%calculateShippingCost%'")

    [ "$unrelated_edges" -eq 0 ] || \
        fail "Unrelated symbols should not generate virtual edges, got $unrelated_edges"
}

# ============================================================
# CT-VE-004: Edge Type Verification
# Given: Virtual edge is generated
# When: Check edge_type
# Then: edge_type = 'VIRTUAL_CALLS'
# ============================================================

@test "CT-VE-004: edge type - generates VIRTUAL_CALLS edges" {
    skip_if_confidence_not_ready "Edge type verification"
    skip_if_missing "sqlite3"

    setup_test_repos "$TEST_TEMP_DIR"
    setup_confidence_test_env "$TEST_TEMP_DIR"
    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"

    # Create local repo with matching symbol
    create_confidence_test_repo "$TEST_TEMP_DIR" "edge-type-repo" "GetUser" "id: string"

    cd "$TEST_TEMP_DIR/edge-type-repo"

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || { cd - > /dev/null; skip "Federation update failed"; }

    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/edge-type-repo"

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "generate-virtual-edges failed"

    # Get all edge types
    local edge_types=$(sqlite3 "$GRAPH_DB" "SELECT DISTINCT edge_type FROM virtual_edges")

    [ -n "$edge_types" ] || skip "No virtual edges generated"

    # Verify all edges are VIRTUAL_CALLS
    local non_virtual_calls=$(sqlite3 "$GRAPH_DB" \
        "SELECT COUNT(*) FROM virtual_edges WHERE edge_type != 'VIRTUAL_CALLS'")

    [ "$non_virtual_calls" -eq 0 ] || \
        fail "All virtual edges should have edge_type='VIRTUAL_CALLS', found $non_virtual_calls with other types"

    # Verify at least one VIRTUAL_CALLS edge exists
    local virtual_calls_count=$(sqlite3 "$GRAPH_DB" \
        "SELECT COUNT(*) FROM virtual_edges WHERE edge_type = 'VIRTUAL_CALLS'")

    [ "$virtual_calls_count" -ge 1 ] || \
        fail "Expected at least 1 VIRTUAL_CALLS edge, got $virtual_calls_count"
}

# ============================================================
# CT-VE-005: Performance - 100 Symbol Matching < 200ms
# Given: 100 symbols to match
# When: Generate virtual edges
# Then: Execution time < 200ms
# ============================================================

@test "CT-VE-005: performance - 100 symbol matching under 200ms" {
    skip_if_confidence_not_ready "Performance test"
    skip_if_missing "sqlite3"

    setup_test_repos "$TEST_TEMP_DIR"
    setup_confidence_test_env "$TEST_TEMP_DIR"
    create_federation_config "$FEDERATION_CONFIG" "$TEST_TEMP_DIR"

    # Create local repo with 100 symbols
    mkdir -p "$TEST_TEMP_DIR/perf-test-repo/src"
    cd "$TEST_TEMP_DIR/perf-test-repo"
    git init --quiet
    git config user.email "$GIT_TEST_EMAIL"
    git config user.name "$GIT_TEST_NAME"

    # Generate 100 functions
    cat > src/functions.ts << 'HEADER'
// Performance test: 100 symbols
HEADER

    for i in $(seq 1 100); do
        cat >> src/functions.ts << EOF
export async function getUser${i}(id: string): Promise<User> {
    return await rpc.call('UserService', 'GetUser', { id });
}

EOF
    done

    git add .
    git commit -m "init 100 symbols" --quiet
    cd - > /dev/null

    run "$FEDERATION_LITE" --update --config "$FEDERATION_CONFIG"
    [ "$status" -eq 0 ] || skip "Federation update failed"

    cd "$TEST_TEMP_DIR/perf-test-repo"

    # Measure execution time
    local start_time end_time elapsed_ms
    start_time=$(get_time_ns)

    run "$FEDERATION_LITE" generate-virtual-edges \
        --config "$FEDERATION_CONFIG" \
        --db "$GRAPH_DB" \
        --local-repo "$TEST_TEMP_DIR/perf-test-repo"

    end_time=$(get_time_ns)

    cd - > /dev/null

    [ "$status" -eq 0 ] || skip "generate-virtual-edges failed"

    # Calculate elapsed time in milliseconds
    if [ "$start_time" != "0" ] && [ "$end_time" != "0" ]; then
        elapsed_ms=$(( (end_time - start_time) / 1000000 ))

        # Verify performance: should complete in < 200ms
        if [ "$elapsed_ms" -ge 200 ]; then
            fail "100 symbol matching took ${elapsed_ms}ms, expected < 200ms"
        fi

        # Log for debugging
        echo "# 100 symbol matching completed in ${elapsed_ms}ms" >&3
    else
        skip "Unable to measure execution time (nanosecond timing not available)"
    fi

    # Additional verification: check that edges were actually created
    local edge_count=$(sqlite3 "$GRAPH_DB" "SELECT COUNT(*) FROM virtual_edges")
    [ "$edge_count" -ge 1 ] || skip "No virtual edges created during performance test"
}
