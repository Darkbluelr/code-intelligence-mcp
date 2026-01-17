#!/bin/bash
# cache-manager.sh - Multi-level Cache Manager (L1 Memory + L2 File)
#
# Version: 1.0.0
# Purpose: Provide multi-level caching with mtime + blob hash invalidation
# Depends: jq, git (optional), md5sum/md5
#
# Usage:
#   cache-manager.sh --get <file_path> --query <query_hash>
#   cache-manager.sh --set <file_path> --query <query_hash> --value <value>
#   cache-manager.sh --clear-l1
#   cache-manager.sh --stats
#   cache-manager.sh --help
#
# Environment Variables:
#   CACHE_DIR           - Cache directory (default: ${TMPDIR:-/tmp}/.ci-cache)
#   CACHE_MAX_SIZE_MB   - Maximum cache size in MB (default: 50)
#   GIT_HASH_CMD        - Git hash command for testing (default: git hash-object)
#   DEBUG               - Enable debug output (default: false)
#
# Trace: AC-001 ~ AC-005, AC-N01, AC-N05, AC-N06
# Change: augment-upgrade-phase2

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

CACHE_SCHEMA_VERSION="1.0.0"
: "${CACHE_DIR:=${TMPDIR:-/tmp}/.ci-cache}"
: "${CACHE_MAX_SIZE_MB:=50}"
: "${GIT_HASH_CMD:=git hash-object}"
: "${DEBUG:=false}"

# Subgraph LRU Cache Configuration (REQ-SLC-001 ~ REQ-SLC-009)
: "${DEVBOOKS_DIR:=.devbooks}"
: "${SUBGRAPH_CACHE_DB:=${DEVBOOKS_DIR}/subgraph-cache.db}"
: "${CACHE_MAX_SIZE:=100}"  # Maximum number of cache entries
: "${CACHE_TTL_DAYS:=30}"   # MP8.3: TTL expiration in days
: "${CACHE_DEBUG:=0}"
: "${CACHE_EVICTION_LOG:=}" # MP8.1: Optional log file for evicted keys

# Hit/miss counters for statistics (per-session)
CACHE_HITS=0
CACHE_MISSES=0

# L1 cache (memory) - using associative arrays
# Initialize associative arrays (bash 4+)
if [[ "${BASH_VERSION%%.*}" -ge 4 ]]; then
    declare -A L1_CACHE=()
    declare -A FILE_MTIME_CACHE=()
    declare -A L1_META_MTIME=()
    declare -A L1_META_BLOB_HASH=()
else
    # Bash 3 fallback - arrays won't work, disable L1 cache
    L1_CACHE_DISABLED=true
fi

# ============================================================
# Utility Functions
# ============================================================

# Log functions
log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "[DEBUG] $1" >&2
    fi
}

log_info() {
    echo "[INFO] $1" >&2
}

log_warn() {
    echo "[WARN] $1" >&2
}

log_error() {
    echo "[ERROR] $1" >&2
}

# Get monotonic millisecond timestamp (cross-platform)
# Uses: gdate (macOS coreutils) > date +%s%3N (Linux) > perl (fallback)
get_ms_timestamp() {
    if command -v gdate &>/dev/null; then
        gdate +%s%3N  # milliseconds on macOS with coreutils
    elif date +%s%3N 2>/dev/null | grep -qv 'N'; then
        date +%s%3N   # milliseconds on Linux
    elif command -v perl &>/dev/null; then
        perl -MTime::HiRes=gettimeofday -e 'my ($s, $us) = gettimeofday(); printf "%d%03d\n", $s, $us/1000;'
    else
        # Fallback: use seconds * 1000 + monotonic counter
        local base_ms=$(($(date +%s) * 1000))
        # Use a file-based counter for monotonicity
        local counter_file="${CACHE_DIR:-/tmp}/.cache_ts_counter"
        local counter=0
        if [[ -f "$counter_file" ]]; then
            counter=$(cat "$counter_file" 2>/dev/null || echo "0")
        fi
        counter=$((counter + 1))
        echo "$counter" > "$counter_file" 2>/dev/null || true
        echo $((base_ms + counter % 1000))
    fi
}

# ============================================================
# Subgraph LRU Cache Functions (REQ-SLC-001 ~ REQ-SLC-009)
# ============================================================

# Initialize SQLite database for subgraph cache (REQ-SLC-001, REQ-SLC-002)
# Creates the database with WAL mode and proper table structure
init_subgraph_cache_db() {
    # Ensure devbooks directory exists
    mkdir -p "$(dirname "$SUBGRAPH_CACHE_DB")" 2>/dev/null || true

    # Check if sqlite3 is available
    if ! command -v sqlite3 &>/dev/null; then
        log_error "sqlite3 is required for subgraph cache"
        return 2
    fi

    # Create database with WAL mode and table structure
    # Redirect stdout to suppress 'wal' output from PRAGMA
    sqlite3 "$SUBGRAPH_CACHE_DB" <<'INIT_SQL' >/dev/null
-- Enable WAL mode for concurrent reads (REQ-SLC-001)
PRAGMA journal_mode=WAL;

-- Create cache table (REQ-SLC-002)
-- Use 'key' and 'value' column names for test compatibility
CREATE TABLE IF NOT EXISTS subgraph_cache (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    access_time INTEGER NOT NULL,
    created_time INTEGER NOT NULL,
    ttl_expires INTEGER DEFAULT NULL
);

-- Create index on access_time for LRU eviction (REQ-SLC-003)
CREATE INDEX IF NOT EXISTS idx_access_time ON subgraph_cache(access_time);

-- Create index on ttl_expires for TTL expiration (MP8.3)
CREATE INDEX IF NOT EXISTS idx_ttl_expires ON subgraph_cache(ttl_expires);

-- Create statistics table for tracking hit/miss (REQ-SLC-009)
CREATE TABLE IF NOT EXISTS cache_stats (
    stat_key TEXT PRIMARY KEY,
    stat_value INTEGER NOT NULL DEFAULT 0
);

-- Initialize statistics
INSERT OR IGNORE INTO cache_stats (stat_key, stat_value) VALUES ('hits', 0);
INSERT OR IGNORE INTO cache_stats (stat_key, stat_value) VALUES ('misses', 0);
INIT_SQL

    return $?
}

# Ensure database is initialized before operations
ensure_subgraph_cache_db() {
    if [[ ! -f "$SUBGRAPH_CACHE_DB" ]]; then
        init_subgraph_cache_db
    fi
}

# Get value from subgraph cache (REQ-SLC-005)
# Updates access_time and increments hit/miss counter
# MP8.1: Updates access_time for LRU tracking
# MP8.3: Checks TTL expiration
subgraph_cache_get() {
    local cache_key="$1"

    ensure_subgraph_cache_db || return 2

    # Use millisecond timestamp for more precise LRU tracking
    local now
    now=$(get_ms_timestamp)

    # First, clean up expired entries (MP8.3: TTL expiration)
    local now_seconds=$((now / 1000))
    sqlite3 "$SUBGRAPH_CACHE_DB" "DELETE FROM subgraph_cache WHERE ttl_expires IS NOT NULL AND ttl_expires < $now_seconds;" 2>/dev/null || true

    # Update access_time and get value in single transaction (REQ-SLC-005)
    # MP8.1: Updates access_time on each access for accurate LRU tracking
    local result
    result=$(sqlite3 "$SUBGRAPH_CACHE_DB" <<GET_SQL
BEGIN;
-- Update access time if key exists (MP8.1: LRU tracking)
UPDATE subgraph_cache SET access_time = $now WHERE key = '$cache_key';
-- Get the value
SELECT value FROM subgraph_cache WHERE key = '$cache_key';
-- Update hit/miss counter
UPDATE cache_stats SET stat_value = stat_value + 1
WHERE stat_key = CASE WHEN (SELECT COUNT(*) FROM subgraph_cache WHERE key = '$cache_key') > 0 THEN 'hits' ELSE 'misses' END;
COMMIT;
GET_SQL
    )

    if [[ -n "$result" ]]; then
        CACHE_HITS=$((CACHE_HITS + 1))
        echo "$result"
        return 0
    else
        CACHE_MISSES=$((CACHE_MISSES + 1))
        # Update misses in DB
        sqlite3 "$SUBGRAPH_CACHE_DB" "UPDATE cache_stats SET stat_value = stat_value + 1 WHERE stat_key = 'misses';" 2>/dev/null || true
        return 1
    fi
}

# Set value in subgraph cache with LRU eviction (REQ-SLC-006)
# Evicts oldest entries when over MAX_SIZE in same transaction
# MP8.1: LRU eviction - evicts oldest 20% when at capacity
# MP8.3: TTL expiration - sets ttl_expires based on CACHE_TTL_DAYS
# MP8.4: Atomic write using single SQLite transaction
subgraph_cache_set() {
    local cache_key="$1"
    local cache_value="$2"

    ensure_subgraph_cache_db || return 2

    # Use millisecond timestamp for more precise LRU tracking
    local now
    now=$(get_ms_timestamp)

    local now_seconds=$((now / 1000))
    local max_size="${CACHE_MAX_SIZE:-100}"
    local ttl_days="${CACHE_TTL_DAYS:-30}"
    local ttl_expires=$((now_seconds + ttl_days * 86400))

    # Escape single quotes in value for SQL
    local escaped_value
    escaped_value="${cache_value//\'/\'\'}"

    # Calculate eviction count (20% of max_size, minimum 1)
    local evict_count=$(( (max_size * 20 + 99) / 100 ))  # ceil(max_size * 0.2)
    [[ $evict_count -lt 1 ]] && evict_count=1

    # Get current count before insert
    local current_count
    current_count=$(sqlite3 "$SUBGRAPH_CACHE_DB" "SELECT COUNT(*) FROM subgraph_cache;" 2>/dev/null || echo "0")

    # Check if eviction is needed (count >= max_size)
    if [[ "$current_count" -ge "$max_size" ]]; then
        # Log evicted keys if CACHE_EVICTION_LOG is set (CT-CL-005)
        if [[ -n "${CACHE_EVICTION_LOG:-}" ]]; then
            local evicted_keys
            evicted_keys=$(sqlite3 "$SUBGRAPH_CACHE_DB" \
                "SELECT key FROM subgraph_cache ORDER BY access_time ASC LIMIT $evict_count;" 2>/dev/null || echo "")
            if [[ -n "$evicted_keys" ]]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Evicting $evict_count entries: $evicted_keys" >> "$CACHE_EVICTION_LOG"
            fi
        fi

        # Log to debug output
        log_debug "LRU eviction: removing $evict_count oldest entries (current=$current_count, max=$max_size)"
    fi

    # Insert/update with LRU eviction in single transaction (REQ-SLC-006)
    # MP8.1: Evict oldest 20% when at capacity
    # MP8.3: Set TTL expiration
    # MP8.4: Atomic write via SQLite transaction
    sqlite3 "$SUBGRAPH_CACHE_DB" <<SET_SQL
BEGIN;
-- First, clean up expired entries (MP8.3: TTL expiration)
DELETE FROM subgraph_cache WHERE ttl_expires IS NOT NULL AND ttl_expires < $now_seconds;

-- Evict oldest 20% if at capacity (MP8.1: LRU eviction)
-- Order by access_time ASC, then created_time ASC (for tie-breaking)
DELETE FROM subgraph_cache
WHERE key IN (
    SELECT key FROM subgraph_cache
    ORDER BY access_time ASC, created_time ASC
    LIMIT CASE
        WHEN (SELECT COUNT(*) FROM subgraph_cache) >= $max_size THEN $evict_count
        ELSE 0
    END
);
-- Insert or replace (preserving created_time if exists)
INSERT OR REPLACE INTO subgraph_cache (key, value, access_time, created_time, ttl_expires)
VALUES ('$cache_key', '$escaped_value', $now, COALESCE(
    (SELECT created_time FROM subgraph_cache WHERE key = '$cache_key'), $now
), $ttl_expires);
COMMIT;
SET_SQL

    return $?
}

# Delete entry from subgraph cache
subgraph_cache_delete() {
    local cache_key="$1"

    ensure_subgraph_cache_db || return 2

    sqlite3 "$SUBGRAPH_CACHE_DB" "DELETE FROM subgraph_cache WHERE key = '$cache_key';"
    return $?
}

# Clear all entries from subgraph cache
subgraph_cache_clear() {
    ensure_subgraph_cache_db || return 2

    sqlite3 "$SUBGRAPH_CACHE_DB" <<CLEAR_SQL
DELETE FROM subgraph_cache;
UPDATE cache_stats SET stat_value = 0 WHERE stat_key IN ('hits', 'misses');
CLEAR_SQL

    return $?
}

# Get subgraph cache statistics (REQ-SLC-007, REQ-SLC-009)
subgraph_cache_stats() {
    local format="${1:-json}"

    ensure_subgraph_cache_db || return 2

    # Get statistics from database
    local total_entries oldest_access newest_access hits misses cache_size_bytes

    total_entries=$(sqlite3 "$SUBGRAPH_CACHE_DB" "SELECT COUNT(*) FROM subgraph_cache;" 2>/dev/null || echo "0")
    oldest_access=$(sqlite3 "$SUBGRAPH_CACHE_DB" "SELECT MIN(access_time) FROM subgraph_cache;" 2>/dev/null || echo "0")
    newest_access=$(sqlite3 "$SUBGRAPH_CACHE_DB" "SELECT MAX(access_time) FROM subgraph_cache;" 2>/dev/null || echo "0")
    hits=$(sqlite3 "$SUBGRAPH_CACHE_DB" "SELECT stat_value FROM cache_stats WHERE stat_key = 'hits';" 2>/dev/null || echo "0")
    misses=$(sqlite3 "$SUBGRAPH_CACHE_DB" "SELECT stat_value FROM cache_stats WHERE stat_key = 'misses';" 2>/dev/null || echo "0")

    # Handle null values
    [[ -z "$oldest_access" ]] && oldest_access=0
    [[ -z "$newest_access" ]] && newest_access=0
    [[ -z "$hits" ]] && hits=0
    [[ -z "$misses" ]] && misses=0

    # Calculate hit rate
    local hit_rate="0"
    local total_requests=$((hits + misses))
    if [[ $total_requests -gt 0 ]]; then
        hit_rate=$(awk "BEGIN {printf \"%.2f\", $hits / $total_requests}")
    fi

    # Get database file size
    if [[ -f "$SUBGRAPH_CACHE_DB" ]]; then
        cache_size_bytes=$(stat -c %s "$SUBGRAPH_CACHE_DB" 2>/dev/null || stat -f %z "$SUBGRAPH_CACHE_DB" 2>/dev/null || echo "0")
    else
        cache_size_bytes=0
    fi

    if [[ "$format" == "json" ]]; then
        jq -n \
            --argjson total_entries "$total_entries" \
            --argjson oldest_access "$oldest_access" \
            --argjson newest_access "$newest_access" \
            --argjson hits "$hits" \
            --argjson misses "$misses" \
            --arg hit_rate "$hit_rate" \
            --argjson cache_size_bytes "$cache_size_bytes" \
            '{
                total_entries: $total_entries,
                oldest_access: $oldest_access,
                newest_access: $newest_access,
                hits: $hits,
                misses: $misses,
                hit_rate: ($hit_rate | tonumber),
                cache_size_bytes: $cache_size_bytes
            }'
    else
        echo "Total entries: $total_entries"
        echo "Oldest access: $oldest_access"
        echo "Newest access: $newest_access"
        echo "Hits: $hits"
        echo "Misses: $misses"
        echo "Hit rate: $hit_rate"
        echo "Cache size (bytes): $cache_size_bytes"
    fi
}

# Show help message
show_help() {
    cat << 'EOF'
cache-manager.sh - Multi-level Cache Manager (L1 Memory + L2 File + SQLite LRU)

Usage:
  cache-manager.sh --get <file_path> --query <query_hash> [--debug]
  cache-manager.sh --set <file_path> --query <query_hash> --value <value>
  cache-manager.sh --clear-l1
  cache-manager.sh --stats
  cache-manager.sh --help

  # Subgraph LRU Cache Commands
  cache-manager.sh cache-get <key>
  cache-manager.sh cache-set <key> <value>
  cache-manager.sh cache-delete <key>
  cache-manager.sh cache-clear
  cache-manager.sh stats [--format json|text]

Options:
  --get         Get cached value for file and query
  --set         Set cache value for file and query
  --clear-l1    Clear L1 (memory) cache
  --stats       Show cache statistics (L1/L2)
  --debug       Enable debug output
  --help        Show this help message
  --format      Output format for stats (json or text)

Subgraph Cache Commands:
  cache-get     Get value from SQLite LRU cache
  cache-set     Set value in SQLite LRU cache
  cache-delete  Delete entry from cache
  cache-clear   Clear all cache entries
  stats         Show subgraph cache statistics

Environment Variables:
  CACHE_DIR           Cache directory (default: ${TMPDIR:-/tmp}/.ci-cache)
  CACHE_MAX_SIZE_MB   Maximum L2 cache size in MB (default: 50)
  CACHE_MAX_SIZE      Maximum subgraph cache entries (default: 100)
  SUBGRAPH_CACHE_DB   SQLite database path (default: .devbooks/subgraph-cache.db)
  DEVBOOKS_DIR        DevBooks directory (default: .devbooks)

Examples:
  # Get cached value
  cache-manager.sh --get src/server.ts --query abc123

  # Set cache value
  cache-manager.sh --set src/server.ts --query abc123 --value "result data"

  # Clear memory cache
  cache-manager.sh --clear-l1

  # Show L1/L2 statistics
  cache-manager.sh --stats

  # Subgraph cache operations
  cache-manager.sh cache-set "key1" "value1"
  cache-manager.sh cache-get "key1"
  cache-manager.sh stats --format json
EOF
}

# ============================================================
# Core Cache Functions (MP1.1)
# ============================================================

# Get file modification time (cross-platform)
# REQ: Portable across macOS and Linux
get_file_mtime() {
    local file_path="$1"

    if [[ ! -f "$file_path" ]]; then
        echo "0"
        return 1
    fi

    # Try Linux stat first, then macOS stat
    if stat -c %Y "$file_path" 2>/dev/null; then
        return 0
    elif stat -f %m "$file_path" 2>/dev/null; then
        return 0
    else
        echo "0"
        return 1
    fi
}

# Get blob hash for a file
# Uses git hash-object for tracked files, md5 for untracked
# REQ: AC-005 - blob hash invalidation
get_blob_hash() {
    local file_path="$1"

    if [[ ! -f "$file_path" ]]; then
        echo ""
        return 1
    fi

    # Check if file is in a git repo and tracked
    if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        if git ls-files --error-unmatch "$file_path" &>/dev/null 2>&1; then
            # Use git blob hash for tracked files
            $GIT_HASH_CMD "$file_path" 2>/dev/null
            return $?
        fi
    fi

    # Fallback to MD5 for untracked files or non-git directories
    # REQ: CT-CACHE-007 - Git unavailable fallback
    if command -v md5sum &>/dev/null; then
        md5sum "$file_path" 2>/dev/null | cut -d' ' -f1
    elif command -v md5 &>/dev/null; then
        md5 -q "$file_path" 2>/dev/null
    else
        # Last resort: use cksum
        cksum "$file_path" 2>/dev/null | cut -d' ' -f1
    fi
}

# Compute cache key from file path, mtime, blob hash, and query hash
# REQ: CT-CACHE-003 - Cache key includes file_path:mtime:blob_hash:query_hash
compute_cache_key() {
    local file_path="$1"
    local mtime="$2"
    local blob_hash="$3"
    local query_hash="$4"

    local combined="${file_path}:${mtime}:${blob_hash}:${query_hash}"

    # Hash the combined string for a shorter key
    if command -v md5sum &>/dev/null; then
        printf '%s' "$combined" | md5sum | cut -d' ' -f1
    elif command -v md5 &>/dev/null; then
        if md5 -q /dev/null >/dev/null 2>&1; then
            printf '%s' "$combined" | md5 -q
        else
            printf '%s' "$combined" | md5
        fi
    else
        printf '%s' "$combined" | cksum | cut -d' ' -f1
    fi
}

# ============================================================
# Cache Invalidation (MP1.2)
# ============================================================

# Check if file is being written (mtime changed within 1s)
# REQ: CT-CACHE-004 - Write-in-progress detection
is_file_being_written() {
    local file_path="$1"
    local current_mtime="$2"

    # Use file-based mtime tracking for cross-process detection
    # This works even with bash 3 (no associative arrays)
    local mtime_cache_dir="${CACHE_DIR}/mtime"
    mkdir -p "$mtime_cache_dir" 2>/dev/null

    # Create a safe filename from the file path
    local safe_name
    safe_name=$(printf '%s' "$file_path" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$file_path" | md5 -q 2>/dev/null || echo "default")
    local mtime_file="${mtime_cache_dir}/${safe_name}.mtime"

    local last_mtime="0"
    if [[ -f "$mtime_file" ]]; then
        last_mtime=$(cat "$mtime_file" 2>/dev/null || echo "0")
    fi

    # Update mtime cache file
    echo "$current_mtime" > "$mtime_file" 2>/dev/null

    # Also update in-memory cache if available (bash 4+)
    if [[ -z "${L1_CACHE_DISABLED:-}" ]]; then
        local l1_key="mtime:${file_path}"
        FILE_MTIME_CACHE[$l1_key]="$current_mtime"
    fi

    # If mtime changed within last 1 second, file may be writing
    if [[ "$last_mtime" != "0" ]]; then
        local delta=$((current_mtime - last_mtime))
        if [[ $delta -ge 0 && $delta -lt 1 ]]; then
            log_debug "File may be in write progress, skipping cache: $file_path (delta=${delta}s)"
            return 0  # File is being written
        fi
    fi

    return 1  # File is not being written
}

# Validate cache entry against current file state
# REQ: CT-CACHE-003 - mtime and blob hash validation
validate_cache_entry() {
    local cache_file="$1"
    local current_mtime="$2"
    local current_blob_hash="$3"

    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi

    # Check schema version
    local schema_version
    schema_version=$(jq -r '.schema_version // ""' "$cache_file" 2>/dev/null)
    if [[ "$schema_version" != "$CACHE_SCHEMA_VERSION" ]]; then
        log_debug "Schema version mismatch: $schema_version != $CACHE_SCHEMA_VERSION"
        return 1
    fi

    # Check mtime
    local cached_mtime
    cached_mtime=$(jq -r '.mtime // 0' "$cache_file" 2>/dev/null)
    if [[ "$cached_mtime" != "$current_mtime" ]]; then
        log_debug "mtime mismatch: $cached_mtime != $current_mtime"
        return 1
    fi

    # Check blob hash
    local cached_blob_hash
    cached_blob_hash=$(jq -r '.blob_hash // ""' "$cache_file" 2>/dev/null)
    if [[ "$cached_blob_hash" != "$current_blob_hash" ]]; then
        log_debug "blob hash mismatch: $cached_blob_hash != $current_blob_hash"
        return 1
    fi

    return 0
}

# ============================================================
# LRU Eviction (MP1.4)
# ============================================================

# Check cache size and evict if needed
# REQ: CT-CACHE-006 - LRU eviction deletes oldest 20%
# REQ: AC-N05 - Cache disk usage <= 50MB
check_and_evict_if_needed() {
    local cache_l2_dir="${CACHE_DIR}/l2"

    if [[ ! -d "$cache_l2_dir" ]]; then
        return 0
    fi

    # Get current cache size in KB for precise comparison
    local current_size_kb
    current_size_kb=$(du -sk "$cache_l2_dir" 2>/dev/null | cut -f1 || echo "0")
    local max_size_kb=$((CACHE_MAX_SIZE_MB * 1024))
    # Target 80% of limit to leave room for new entries
    local target_size_kb=$((max_size_kb * 80 / 100))

    # Loop until cache is below target size
    while [[ $current_size_kb -ge $max_size_kb ]]; do
        log_info "Cache reached limit ${current_size_kb}KB >= ${max_size_kb}KB, executing LRU eviction"

        # Count total cache files
        local total_files
        total_files=$(find "$cache_l2_dir" -type f -name "*.json" 2>/dev/null | wc -l | tr -d ' ')

        if [[ "$total_files" -lt 1 ]]; then
            return 0
        fi

        # Calculate eviction count (20% of files, minimum 1)
        local evict_count=$((total_files * 20 / 100))
        [[ $evict_count -lt 1 ]] && evict_count=1

        # Find and delete oldest files by accessed_at
        local tmp_file
        tmp_file=$(mktemp)

        find "$cache_l2_dir" -type f -name "*.json" -exec sh -c '
            for f do
                accessed=$(jq -r ".accessed_at // 0" "$f" 2>/dev/null || echo "0")
                echo "$accessed $f"
            done
        ' _ {} + | sort -n | head -n "$evict_count" > "$tmp_file"

        local deleted=0
        while IFS= read -r line; do
            local file_to_delete
            file_to_delete=$(echo "$line" | cut -d' ' -f2-)
            if [[ -f "$file_to_delete" ]]; then
                rm -f "$file_to_delete"
                deleted=$((deleted + 1))
            fi
        done < "$tmp_file"

        rm -f "$tmp_file"
        log_info "Evicted $deleted cache entries"

        # Re-check size after eviction
        current_size_kb=$(du -sk "$cache_l2_dir" 2>/dev/null | cut -f1 || echo "0")

        # If we're below target, stop evicting
        if [[ $current_size_kb -lt $target_size_kb ]]; then
            break
        fi
    done
}

# ============================================================
# Main Cache Operations (MP1.1, MP1.3)
# ============================================================

# Get cached value with validation
# REQ: CT-CACHE-001 - L1 hit returns in < 10ms
# REQ: CT-CACHE-002 - L2 hit returns in < 100ms
get_cached_with_validation() {
    local file_path="$1"
    local query_hash="$2"

    # Normalize file path
    if [[ -f "$file_path" ]]; then
        file_path=$(cd "$(dirname "$file_path")" && pwd)/$(basename "$file_path") 2>/dev/null || file_path="$file_path"
    fi

    # 1. Check L1 cache (memory) - only if bash 4+
    local l1_key="${file_path}:${query_hash}"
    local current_mtime=""
    local current_blob_hash=""
    if [[ -z "${L1_CACHE_DISABLED:-}" ]] && [[ -n "${L1_CACHE[$l1_key]:-}" ]]; then
        local cached_mtime="${L1_META_MTIME[$l1_key]:-}"
        local cached_blob_hash="${L1_META_BLOB_HASH[$l1_key]:-}"
        if [[ -n "$cached_mtime" && -n "$cached_blob_hash" ]]; then
            current_mtime=$(get_file_mtime "$file_path")
            if [[ "$current_mtime" != "0" ]]; then
                current_blob_hash=$(get_blob_hash "$file_path")
                if [[ "$current_mtime" == "$cached_mtime" && "$current_blob_hash" == "$cached_blob_hash" ]]; then
                    log_debug "L1 cache hit for $file_path"
                    echo "${L1_CACHE[$l1_key]}"
                    return 0
                fi
            fi
        fi
        unset 'L1_CACHE[$l1_key]' 'L1_META_MTIME[$l1_key]' 'L1_META_BLOB_HASH[$l1_key]'
    fi

    # 2. Get current file state
    if [[ -z "$current_mtime" ]]; then
        current_mtime=$(get_file_mtime "$file_path")
    fi
    if [[ "$current_mtime" == "0" ]]; then
        log_debug "Could not get mtime for $file_path"
        return 1
    fi

    # 3. Check if file is being written
    if is_file_being_written "$file_path" "$current_mtime"; then
        log_debug "File may be in write progress, skipping cache"
        return 0  # Return success but no output (cache skip)
    fi

    # 4. Get blob hash
    if [[ -z "$current_blob_hash" ]]; then
        current_blob_hash=$(get_blob_hash "$file_path")
    fi

    # 5. Compute cache key
    local cache_key
    cache_key=$(compute_cache_key "$file_path" "$current_mtime" "$current_blob_hash" "$query_hash")
    local cache_file="${CACHE_DIR}/l2/${cache_key}.json"

    # 6. Check L2 cache (file)
    if [[ -f "$cache_file" ]]; then
        # Validate and read directly
        if validate_cache_entry "$cache_file" "$current_mtime" "$current_blob_hash"; then
            local value
            value=$(jq -r '.value // ""' "$cache_file" 2>/dev/null)

            # Update accessed_at timestamp (best effort, with optional flock)
            local tmp_file="${cache_file}.tmp.$$"
            local current_time
            current_time=$(date +%s)
            if jq --arg accessed_at "$current_time" '.accessed_at = ($accessed_at | tonumber)' "$cache_file" > "$tmp_file" 2>/dev/null; then
                mv "$tmp_file" "$cache_file" 2>/dev/null || rm -f "$tmp_file"
            else
                rm -f "$tmp_file" 2>/dev/null
            fi

            # Write to L1 (if available)
            if [[ -z "${L1_CACHE_DISABLED:-}" ]]; then
                L1_CACHE[$l1_key]="$value"
                L1_META_MTIME[$l1_key]="$current_mtime"
                L1_META_BLOB_HASH[$l1_key]="$current_blob_hash"
            fi

            log_debug "L2 cache hit for $file_path (mtime=$current_mtime, blob_hash=$current_blob_hash)"
            echo "$value"
            return 0
        else
            log_debug "L2 cache validation failed for $file_path"
        fi
    fi

    log_debug "Cache miss for $file_path (mtime=$current_mtime, blob_hash=$current_blob_hash)"
    # Return success (0) even on cache miss - caller checks output
    # This allows tests to distinguish between "not implemented" and "cache miss"
    return 0
}

# Set cache value with lock protection
# REQ: CT-CACHE-005 - Concurrent writes use flock
set_cache_with_lock() {
    local file_path="$1"
    local query_hash="$2"
    local value="$3"

    # Normalize file path
    if [[ -f "$file_path" ]]; then
        file_path=$(cd "$(dirname "$file_path")" && pwd)/$(basename "$file_path") 2>/dev/null || file_path="$file_path"
    fi

    # Ensure cache directory exists
    mkdir -p "${CACHE_DIR}/l2" 2>/dev/null

    # Get file state
    local mtime blob_hash
    mtime=$(get_file_mtime "$file_path")
    blob_hash=$(get_blob_hash "$file_path")

    # Compute cache key
    local cache_key
    cache_key=$(compute_cache_key "$file_path" "$mtime" "$blob_hash" "$query_hash")
    local cache_file="${CACHE_DIR}/l2/${cache_key}.json"
    local tmp_file="${cache_file}.tmp.$$"
    local lock_file="${cache_file}.lock"

    # Check and evict if needed
    check_and_evict_if_needed

    # Atomic write with flock protection
    (
        if command -v flock &>/dev/null; then
            flock -x 200 2>/dev/null || true
        fi

        local current_time
        current_time=$(date +%s)

        # Write to temporary file first
        jq -n \
            --arg schema_version "$CACHE_SCHEMA_VERSION" \
            --arg key "$cache_key" \
            --arg file_path "$file_path" \
            --arg mtime "$mtime" \
            --arg blob_hash "$blob_hash" \
            --arg query_hash "$query_hash" \
            --arg value "$value" \
            --arg created_at "$current_time" \
            --arg accessed_at "$current_time" \
            '{
                schema_version: $schema_version,
                key: $key,
                file_path: $file_path,
                mtime: ($mtime | tonumber),
                blob_hash: $blob_hash,
                query_hash: $query_hash,
                value: $value,
                created_at: ($created_at | tonumber),
                accessed_at: ($accessed_at | tonumber)
            }' > "$tmp_file" 2>/dev/null

        # Atomic move
        mv "$tmp_file" "$cache_file" 2>/dev/null || rm -f "$tmp_file"

    ) 200>"$lock_file" 2>/dev/null

    # Check and evict after write to ensure we stay under limit
    check_and_evict_if_needed

    # Write to L1 cache (if available)
    if [[ -z "${L1_CACHE_DISABLED:-}" ]]; then
        local l1_key="${file_path}:${query_hash}"
        L1_CACHE[$l1_key]="$value"
        L1_META_MTIME[$l1_key]="$mtime"
        L1_META_BLOB_HASH[$l1_key]="$blob_hash"
    fi

    log_debug "Cache set for $file_path"
}

# Clear L1 (memory) cache
clear_l1_cache() {
    if [[ -z "${L1_CACHE_DISABLED:-}" ]]; then
        L1_CACHE=()
        FILE_MTIME_CACHE=()
        L1_META_MTIME=()
        L1_META_BLOB_HASH=()
    fi
    log_debug "L1 cache cleared"
}

# Show cache statistics
show_stats() {
    local cache_l2_dir="${CACHE_DIR}/l2"

    local l1_entries=0
    if [[ -z "${L1_CACHE_DISABLED:-}" ]]; then
        l1_entries=${#L1_CACHE[@]}
    fi
    local l2_entries=0
    local size_kb=0
    local size_mb=0

    if [[ -d "$cache_l2_dir" ]]; then
        l2_entries=$(find "$cache_l2_dir" -type f -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
        size_kb=$(du -sk "$cache_l2_dir" 2>/dev/null | cut -f1 || echo "0")
        size_mb=$((size_kb / 1024))
    fi

    jq -n \
        --arg l1_entries "$l1_entries" \
        --arg l2_entries "$l2_entries" \
        --arg size_kb "$size_kb" \
        --arg size_mb "$size_mb" \
        --arg max_size_mb "$CACHE_MAX_SIZE_MB" \
        --arg cache_dir "$CACHE_DIR" \
        --arg schema_version "$CACHE_SCHEMA_VERSION" \
        '{
            l1_entries: ($l1_entries | tonumber),
            l2_entries: ($l2_entries | tonumber),
            size_kb: ($size_kb | tonumber),
            size_mb: ($size_mb | tonumber),
            max_size_mb: ($max_size_mb | tonumber),
            cache_dir: $cache_dir,
            schema_version: $schema_version
        }'
}

# ============================================================
# Main Entry Point
# ============================================================

main() {
    local action=""
    local file_path=""
    local query_hash=""
    local value=""
    local format="json"

    # Check for subgraph cache commands first (positional arguments)
    if [[ $# -gt 0 ]]; then
        case "$1" in
            cache-get)
                shift
                if [[ $# -lt 1 ]]; then
                    log_error "Usage: cache-manager.sh cache-get <key>"
                    exit 1
                fi
                subgraph_cache_get "$1"
                exit $?
                ;;
            cache-set)
                shift
                if [[ $# -lt 2 ]]; then
                    log_error "Usage: cache-manager.sh cache-set <key> <value>"
                    exit 1
                fi
                subgraph_cache_set "$1" "$2"
                exit $?
                ;;
            cache-delete)
                shift
                if [[ $# -lt 1 ]]; then
                    log_error "Usage: cache-manager.sh cache-delete <key>"
                    exit 1
                fi
                subgraph_cache_delete "$1"
                exit $?
                ;;
            cache-clear)
                subgraph_cache_clear
                echo "Subgraph cache cleared"
                exit $?
                ;;
            stats)
                shift
                # Parse --format option
                while [[ $# -gt 0 ]]; do
                    case "$1" in
                        --format)
                            format="$2"
                            shift 2
                            ;;
                        *)
                            shift
                            ;;
                    esac
                done
                subgraph_cache_stats "$format"
                exit $?
                ;;
        esac
    fi

    # Parse traditional options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --get)
                action="get"
                shift
                ;;
            --set)
                action="set"
                shift
                ;;
            --clear-l1)
                action="clear-l1"
                shift
                ;;
            --stats)
                action="stats"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --debug)
                DEBUG="true"
                shift
                ;;
            --query)
                query_hash="$2"
                shift 2
                ;;
            --value)
                value="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$file_path" ]]; then
                    file_path="$1"
                fi
                shift
                ;;
        esac
    done

    # Ensure jq is available
    if ! command -v jq &>/dev/null; then
        log_error "jq is required but not installed"
        exit 2
    fi

    case "$action" in
        get)
            if [[ -z "$file_path" ]] || [[ -z "$query_hash" ]]; then
                log_error "Usage: cache-manager.sh --get <file_path> --query <query_hash>"
                exit 1
            fi
            get_cached_with_validation "$file_path" "$query_hash"
            ;;
        set)
            if [[ -z "$file_path" ]] || [[ -z "$query_hash" ]] || [[ -z "$value" ]]; then
                log_error "Usage: cache-manager.sh --set <file_path> --query <query_hash> --value <value>"
                exit 1
            fi
            set_cache_with_lock "$file_path" "$query_hash" "$value"
            ;;
        clear-l1)
            clear_l1_cache
            echo "L1 cache cleared"
            ;;
        stats)
            show_stats
            ;;
        "")
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown action: $action"
            show_help
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
