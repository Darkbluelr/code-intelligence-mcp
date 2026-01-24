#!/usr/bin/env bash
set -euo pipefail

# Repo-local wrapper for DevBooks change-check.
# Defaults are aligned with this repo's layout:
#   change-root = dev-playbooks/changes
#   truth-root  = dev-playbooks/specs
#
# Usage:
#   ./change-check.sh <change-id> --mode strict
#
# Overrides:
# - You can override roots via flags supported by the upstream script, or via env:
#   DEVBOOKS_PROJECT_ROOT, DEVBOOKS_CHANGE_ROOT, DEVBOOKS_TRUTH_ROOT

upstream="${HOME}/.codex/skills/devbooks-delivery-workflow/scripts/change-check.sh"
if [[ ! -x "${upstream}" ]]; then
  echo "error: upstream change-check.sh not found or not executable: ${upstream}" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export DEVBOOKS_PROJECT_ROOT="${DEVBOOKS_PROJECT_ROOT:-${repo_root}}"
export DEVBOOKS_CHANGE_ROOT="${DEVBOOKS_CHANGE_ROOT:-dev-playbooks/changes}"
export DEVBOOKS_TRUTH_ROOT="${DEVBOOKS_TRUTH_ROOT:-dev-playbooks/specs}"

exec "${upstream}" "$@"
