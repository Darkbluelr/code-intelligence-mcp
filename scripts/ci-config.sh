#!/bin/bash
# ci-config.yaml 解析与工作区解析工具

_ci_config_trim() {
  local value="$1"
  value="${value%%#*}"
  value="$(echo "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  echo "$value"
}

_ci_config_find_file() {
  local start="${1:-$(pwd)}"
  local current="$start"
  while [[ "$current" != "/" && -n "$current" ]]; do
    if [[ -f "$current/ci-config.yaml" ]]; then
      echo "$current/ci-config.yaml"
      return 0
    fi
    local parent
    parent="$(dirname "$current")"
    if [[ "$parent" == "$current" ]]; then
      break
    fi
    current="$parent"
  done
  return 1
}

ci_config_get_file() {
  if [[ -n "${CI_CONFIG_FILE:-}" && -f "$CI_CONFIG_FILE" ]]; then
    echo "$CI_CONFIG_FILE"
    return 0
  fi

  local root="${PROJECT_ROOT:-$(pwd)}"
  local found
  found="$(_ci_config_find_file "$root" 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    echo "$found"
    return 0
  fi
  return 1
}

ci_config_get_root() {
  local config_file
  config_file="$(ci_config_get_file 2>/dev/null || true)"
  if [[ -n "$config_file" ]]; then
    dirname "$config_file"
    return 0
  fi
  echo "${PROJECT_ROOT:-$(pwd)}"
}

_ci_config_get_section_value() {
  local file="$1"
  local section="$2"
  local key="$3"

  [[ -f "$file" ]] || return 1

  awk -v section="$section" -v key="$key" '
    function trim(val) {
      sub(/#.*/, "", val)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      gsub(/^["'"'"']|["'"'"']$/, "", val)
      return val
    }
    /^[[:space:]]*#/ { next }
    /^[^[:space:]]/ {
      gsub(/:.*/, "", $1)
      in_section = ($1 == section)
    }
    in_section && /^[[:space:]]+[a-zA-Z0-9_.-]+:/ {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      split(line, parts, ":")
      if (parts[1] == key) {
        val = line
        sub(/^[^:]+:[[:space:]]*/, "", val)
        print trim(val)
        exit
      }
    }
  ' "$file"
}

_ci_config_get_section_list() {
  local file="$1"
  local section="$2"
  local key="$3"

  [[ -f "$file" ]] || return 1

  awk -v section="$section" -v key="$key" '
    function trim(val) {
      sub(/#.*/, "", val)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      gsub(/^["'"'"']|["'"'"']$/, "", val)
      return val
    }
    /^[[:space:]]*#/ { next }
    /^[^[:space:]]/ {
      gsub(/:.*/, "", $1)
      in_section = ($1 == section)
      in_list = 0
    }
    in_section && $0 ~ "^[[:space:]]*"key":[[:space:]]*$" {
      in_list = 1
      next
    }
    in_section && in_list {
      if ($0 ~ /^[[:space:]]*-[[:space:]]+/) {
        val = $0
        sub(/^[[:space:]]*-[[:space:]]+/, "", val)
        val = trim(val)
        if (val != "") {
          print val
        }
        next
      }
      if ($0 ~ /^[[:space:]]+[a-zA-Z0-9_.-]+:/) {
        in_list = 0
      }
    }
  ' "$file"
}

ci_config_get_global_index_dir() {
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"
  [[ -n "$file" ]] || return 1
  _ci_config_get_section_value "$file" "global" "index_dir"
}

ci_config_get_global_respect_gitignore() {
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"
  [[ -n "$file" ]] || return 1
  _ci_config_get_section_value "$file" "global" "respect_gitignore"
}

ci_config_get_global_exclude() {
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"
  [[ -n "$file" ]] || return 1
  _ci_config_get_section_list "$file" "global" "global_exclude"
}

ci_config_get_default_workspace_name() {
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"
  if [[ -n "$file" ]]; then
    local name
    name="$(_ci_config_get_section_value "$file" "default_workspace" "name" || true)"
    if [[ -n "$name" ]]; then
      echo "$name"
      return 0
    fi
  fi
  echo "main"
}

ci_config_get_default_workspace_root() {
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"
  [[ -n "$file" ]] || return 1
  _ci_config_get_section_value "$file" "default_workspace" "root"
}

ci_config_get_default_workspace_include() {
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"
  [[ -n "$file" ]] || return 1
  _ci_config_get_section_list "$file" "default_workspace" "include"
}

ci_config_get_default_workspace_exclude() {
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"
  [[ -n "$file" ]] || return 1
  _ci_config_get_section_list "$file" "default_workspace" "exclude"
}

ci_config_get_default_workspace_respect_gitignore() {
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"
  [[ -n "$file" ]] || return 1
  _ci_config_get_section_value "$file" "default_workspace" "respect_gitignore"
}

ci_config_list_workspace_names() {
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"
  local default_name
  default_name="$(ci_config_get_default_workspace_name)"
  echo "$default_name"
  [[ -n "$file" ]] || return 0

  awk '
    /^[[:space:]]*#/ { next }
    /^workspaces:/ { in_ws = 1; next }
    in_ws && /^[^[:space:]]/ { in_ws = 0 }
    in_ws && /^[[:space:]]*-[[:space:]]*name:/ {
      line = $0
      sub(/.*name:[[:space:]]*/, "", line)
      sub(/#.*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      gsub(/^["'"'"']|["'"'"']$/, "", line)
      if (line != "") {
        print line
      }
    }
  ' "$file" | awk 'NF' | sort -u
}

_ci_config_get_workspace_scalar() {
  local file="$1"
  local workspace="$2"
  local key="$3"

  [[ -f "$file" ]] || return 1

  awk -v target="$workspace" -v key="$key" '
    function trim(val) {
      sub(/#.*/, "", val)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      gsub(/^["'"'"']|["'"'"']$/, "", val)
      return val
    }
    /^[[:space:]]*#/ { next }
    /^workspaces:/ { in_ws = 1; next }
    in_ws && /^[^[:space:]]/ { in_ws = 0; in_target = 0 }
    in_ws && /^[[:space:]]*-[[:space:]]*name:/ {
      line = $0
      sub(/.*name:[[:space:]]*/, "", line)
      name = trim(line)
      in_target = (name == target)
      next
    }
    in_target && $0 ~ "^[[:space:]]*"key":[[:space:]]*" {
      line = $0
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", line)
      print trim(line)
      exit
    }
  ' "$file"
}

_ci_config_get_workspace_list() {
  local file="$1"
  local workspace="$2"
  local key="$3"

  [[ -f "$file" ]] || return 1

  awk -v target="$workspace" -v key="$key" '
    function trim(val) {
      sub(/#.*/, "", val)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      gsub(/^["'"'"']|["'"'"']$/, "", val)
      return val
    }
    /^[[:space:]]*#/ { next }
    /^workspaces:/ { in_ws = 1; next }
    in_ws && /^[^[:space:]]/ { in_ws = 0; in_target = 0; in_list = 0 }
    in_ws && /^[[:space:]]*-[[:space:]]*name:/ {
      line = $0
      sub(/.*name:[[:space:]]*/, "", line)
      name = trim(line)
      in_target = (name == target)
      in_list = 0
      next
    }
    in_target && $0 ~ "^[[:space:]]*"key":[[:space:]]*$" {
      in_list = 1
      next
    }
    in_target && in_list {
      if ($0 ~ /^[[:space:]]*-[[:space:]]+/) {
        line = $0
        sub(/^[[:space:]]*-[[:space:]]+/, "", line)
        val = trim(line)
        if (val != "") {
          print val
        }
        next
      }
      if ($0 ~ /^[[:space:]]*[a-zA-Z0-9_.-]+:/) {
        in_list = 0
      }
    }
  ' "$file"
}

_ci_config_get_workspace_embedding_field() {
  local file="$1"
  local workspace="$2"
  local field="$3"

  [[ -f "$file" ]] || return 1

  awk -v target="$workspace" -v field="$field" '
    function trim(val) {
      sub(/#.*/, "", val)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      gsub(/^["'"'"']|["'"'"']$/, "", val)
      return val
    }
    /^[[:space:]]*#/ { next }
    /^workspaces:/ { in_ws = 1; next }
    in_ws && /^[^[:space:]]/ { in_ws = 0; in_target = 0; in_index = 0; in_embedding = 0 }
    in_ws && /^[[:space:]]*-[[:space:]]*name:/ {
      line = $0
      sub(/.*name:[[:space:]]*/, "", line)
      name = trim(line)
      in_target = (name == target)
      in_index = 0
      in_embedding = 0
      next
    }
    in_target && /^[[:space:]]*index:[[:space:]]*$/ { in_index = 1; in_embedding = 0; next }
    in_target && in_index && /^[[:space:]]*embedding:[[:space:]]*$/ { in_embedding = 1; next }
    in_target && in_index && in_embedding && $0 ~ "^[[:space:]]*"field":[[:space:]]*" {
      line = $0
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", line)
      print trim(line)
      exit
    }
    in_target && in_index && $0 ~ /^[[:space:]]*[a-zA-Z0-9_.-]+:/ && $0 !~ /^[[:space:]]*embedding:/ {
      in_embedding = 0
    }
  ' "$file"
}

ci_config_get_workspace_root() {
  local workspace="$1"
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"

  if [[ -n "$file" ]]; then
    local value
    value="$(_ci_config_get_workspace_scalar "$file" "$workspace" "root" || true)"
    if [[ -n "$value" ]]; then
      echo "$value"
      return 0
    fi
  fi

  local default_name
  default_name="$(ci_config_get_default_workspace_name)"
  if [[ "$workspace" == "$default_name" ]]; then
    ci_config_get_default_workspace_root
    return 0
  fi
  return 1
}

ci_config_get_workspace_respect_gitignore() {
  local workspace="$1"
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"

  if [[ -n "$file" ]]; then
    local value
    value="$(_ci_config_get_workspace_scalar "$file" "$workspace" "respect_gitignore" || true)"
    if [[ -n "$value" ]]; then
      echo "$value"
      return 0
    fi
  fi

  local default_name
  default_name="$(ci_config_get_default_workspace_name)"
  if [[ "$workspace" == "$default_name" ]]; then
    ci_config_get_default_workspace_respect_gitignore
    return 0
  fi
  return 1
}

ci_config_get_workspace_include() {
  local workspace="$1"
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"

  if [[ -n "$file" ]]; then
    _ci_config_get_workspace_list "$file" "$workspace" "include"
    return 0
  fi

  return 1
}

ci_config_get_workspace_exclude() {
  local workspace="$1"
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"

  if [[ -n "$file" ]]; then
    _ci_config_get_workspace_list "$file" "$workspace" "exclude"
    return 0
  fi

  return 1
}

ci_config_get_workspace_embedding_field() {
  local workspace="$1"
  local field="$2"
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"
  [[ -n "$file" ]] || return 1
  _ci_config_get_workspace_embedding_field "$file" "$workspace" "$field"
}

ci_config_get_default_embedding_field() {
  local field="$1"
  local file
  file="$(ci_config_get_file 2>/dev/null || true)"
  [[ -n "$file" ]] || return 1

  awk -v field="$field" '
    function trim(val) {
      sub(/#.*/, "", val)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      gsub(/^["'"'"']|["'"'"']$/, "", val)
      return val
    }
    /^[[:space:]]*#/ { next }
    /^default_workspace:/ { in_default = 1; next }
    in_default && /^[^[:space:]]/ { in_default = 0; in_index = 0; in_embedding = 0 }
    in_default && /^[[:space:]]*index:[[:space:]]*$/ { in_index = 1; in_embedding = 0; next }
    in_default && in_index && /^[[:space:]]*embedding:[[:space:]]*$/ { in_embedding = 1; next }
    in_default && in_index && in_embedding && $0 ~ "^[[:space:]]*"field":[[:space:]]*" {
      line = $0
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", line)
      print trim(line)
      exit
    }
    in_default && in_index && $0 ~ /^[[:space:]]*[a-zA-Z0-9_.-]+:/ && $0 !~ /^[[:space:]]*embedding:/ {
      in_embedding = 0
    }
  ' "$file"
}
