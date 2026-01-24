#!/bin/bash
# Backward-compat wrapper for renamed hook.
# Delegates to context-inject-global.sh to keep existing tests/configs working.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/context-inject-global.sh"

if [ -x "$TARGET" ]; then
  exec "$TARGET" "$@"
fi

echo "[DevBooks] Missing hook: $TARGET" >&2
exit 1
