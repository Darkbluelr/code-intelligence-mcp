#!/bin/bash
# federation-lite-discovery.sh - Contract discovery and symbol extraction
#
# Version: 1.0.0
# Purpose: Discover contract files and extract symbols
# Trace: AC-011
# Change: augment-upgrade-phase2

# Prevent multiple sourcing
[[ -n "${FEDERATION_LITE_DISCOVERY_LOADED:-}" ]] && return 0
FEDERATION_LITE_DISCOVERY_LOADED=1

# ============================================================
# Contract Discovery
# ============================================================

# Detect contract type from filename
# REQ-FED-001: Cross-repo contract discovery
detect_contract_type() {
    local file="$1"
    local basename
    basename=$(basename "$file")

    case "$file" in
        *.proto)
            echo "proto"
            ;;
        */openapi.yaml|*/openapi.yml|*/swagger.yaml|*/swagger.yml|*/swagger.json)
            echo "openapi"
            ;;
        *.graphql|*.gql)
            echo "graphql"
            ;;
        *.d.ts)
            echo "typescript"
            ;;
        */types/*.ts|*/types/**/*.ts)
            echo "typescript"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# ============================================================
# Symbol Extraction
# ============================================================

# Extract symbols from Protocol Buffers file
# REQ-FED-004: Extract service, message, enum, rpc
extract_proto_symbols() {
    local file="$1"
    local symbols="[]"

    while IFS= read -r line; do
        # Match: service Name {
        if [[ "$line" =~ ^[[:space:]]*(service)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
            symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[2]}" '. + [$s]')
        fi
        # Match: message Name {
        if [[ "$line" =~ ^[[:space:]]*(message)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
            symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[2]}" '. + [$s]')
        fi
        # Match: enum Name {
        if [[ "$line" =~ ^[[:space:]]*(enum)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
            symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[2]}" '. + [$s]')
        fi
        # Match: rpc MethodName (
        if [[ "$line" =~ ^[[:space:]]*(rpc)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\( ]]; then
            symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[2]}" '. + [$s]')
        fi
    done < "$file"

    echo "$symbols"
}

# Extract symbols from OpenAPI file
# REQ-FED-004: Extract paths, schemas
extract_openapi_symbols() {
    local file="$1"
    local symbols="[]"

    # Use jq if it's JSON, or parse YAML manually
    if [[ "$file" == *.json ]]; then
        # Extract paths
        local paths
        paths=$(jq -r '.paths | keys[]' "$file" 2>/dev/null || echo "")
        for path in $paths; do
            # Get methods for each path
            local methods
            methods=$(jq -r ".paths[\"$path\"] | keys[]" "$file" 2>/dev/null || echo "")
            for method in $methods; do
                method_upper=$(echo "$method" | tr '[:lower:]' '[:upper:]')
                symbols=$(echo "$symbols" | jq --arg s "$method_upper $path" '. + [$s]')
            done
        done

        # Extract schemas
        local schemas
        schemas=$(jq -r '.components.schemas | keys[]' "$file" 2>/dev/null || echo "")
        for schema in $schemas; do
            symbols=$(echo "$symbols" | jq --arg s "$schema" '. + [$s]')
        done
    else
        # Simple YAML parsing for paths and schemas
        local in_paths=false
        local in_schemas=false
        local current_path=""

        while IFS= read -r line; do
            if [[ "$line" =~ ^paths:[[:space:]]*$ ]]; then
                in_paths=true
                in_schemas=false
                continue
            fi
            if [[ "$line" =~ ^[[:space:]]+schemas:[[:space:]]*$ ]] || [[ "$line" =~ ^components:[[:space:]]*$ ]]; then
                in_schemas=true
                in_paths=false
                continue
            fi

            # Path entries like: /users:
            if [[ "$in_paths" == "true" && "$line" =~ ^[[:space:]]+(/[^:]+):[[:space:]]*$ ]]; then
                current_path="${BASH_REMATCH[1]}"
            fi
            # Methods like: get:, post:
            if [[ "$in_paths" == "true" && -n "$current_path" && "$line" =~ ^[[:space:]]+(get|post|put|delete|patch):[[:space:]]*$ ]]; then
                local method
                method=$(echo "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')
                symbols=$(echo "$symbols" | jq --arg s "$method $current_path" '. + [$s]')
            fi
            # Schema entries
            if [[ "$in_schemas" == "true" && "$line" =~ ^[[:space:]]+([A-Za-z][A-Za-z0-9_]*):[[:space:]]*$ ]]; then
                symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[1]}" '. + [$s]')
            fi
        done < "$file"
    fi

    echo "$symbols"
}

# Extract symbols from GraphQL file
# REQ-FED-004: Extract type, query, mutation
extract_graphql_symbols() {
    local file="$1"
    local symbols="[]"

    while IFS= read -r line; do
        # Match: type Name {
        if [[ "$line" =~ ^[[:space:]]*(type|input|interface|enum)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
            symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[2]}" '. + [$s]')
        fi
        # Match: query Name or mutation Name
        if [[ "$line" =~ ^[[:space:]]*(query|mutation|subscription)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
            symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[2]}" '. + [$s]')
        fi
    done < "$file"

    echo "$symbols"
}

# Extract symbols from TypeScript definition file
# REQ-FED-004: Extract export interface/type/class
extract_typescript_symbols() {
    local file="$1"
    local symbols="[]"

    while IFS= read -r line; do
        # Match: export interface Name
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(interface|type|class|enum)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
            symbols=$(echo "$symbols" | jq --arg s "${BASH_REMATCH[3]}" '. + [$s]')
        fi
    done < "$file"

    echo "$symbols"
}

# Extract symbols from any contract file
extract_symbols() {
    local file="$1"
    local type="$2"

    case "$type" in
        proto)
            extract_proto_symbols "$file"
            ;;
        openapi)
            extract_openapi_symbols "$file"
            ;;
        graphql)
            extract_graphql_symbols "$file"
            ;;
        typescript)
            extract_typescript_symbols "$file"
            ;;
        *)
            echo "[]"
            ;;
    esac
}

# Extract local function calls from TypeScript/JavaScript files
extract_local_symbols() {
    local repo_path="$1"
    local symbols="[]"

    # Find TypeScript/JavaScript files
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ ! -f "$file" ]] && continue

        local rel_path
        rel_path=$(realpath --relative-to="$repo_path" "$file" 2>/dev/null || basename "$file")

        # Extract function declarations and async functions
        while IFS= read -r line; do
            # Match: export async function name
            # Match: export function name
            # Match: async function name
            # Match: function name
            if [[ "$line" =~ (export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
                local func_name="${BASH_REMATCH[3]}"
                symbols=$(echo "$symbols" | jq \
                    --arg name "$func_name" \
                    --arg file "$rel_path" \
                    --arg type "function" \
                    '. + [{"name": $name, "file": $file, "type": $type}]')
            fi
            # Match: const name = async
            # Match: const name = function
            if [[ "$line" =~ (export[[:space:]]+)?(const|let|var)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(async[[:space:]]+)?(function|\() ]]; then
                local func_name="${BASH_REMATCH[3]}"
                symbols=$(echo "$symbols" | jq \
                    --arg name "$func_name" \
                    --arg file "$rel_path" \
                    --arg type "function" \
                    '. + [{"name": $name, "file": $file, "type": $type}]')
            fi
        done < "$file"
    done < <(find "$repo_path" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) \
        -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)

    echo "$symbols"
}
