#!/bin/bash
# DevBooks 共享缓存工具函数库
# 版本: 3.0
# 用途: 为 augment-context-global.sh 和 augment-context.sh 提供统一的缓存机制

# ==================== 缓存配置 ====================
# 这些变量可以在 source 之前被覆盖
: "${CACHE_DIR:=${TMPDIR:-/tmp}/.devbooks-cache}"
: "${CACHE_TTL:=300}"  # 缓存有效期 5 分钟

# 确保缓存目录存在
ensure_cache_dir() {
  mkdir -p "$CACHE_DIR" 2>/dev/null
}

# ==================== 缓存核心函数 ====================

# 计算缓存键的哈希值
# 参数: $1 - 原始键（任意字符串）
# 输出: MD5 哈希值
get_cache_key() {
  local input="$1"
  if command -v md5sum &>/dev/null; then
    echo "$input" | md5sum | cut -d' ' -f1
  elif command -v md5 &>/dev/null; then
    echo "$input" | md5
  else
    # 降级：使用简单哈希（不推荐，仅作为最后手段）
    echo "$input" | cksum | cut -d' ' -f1
  fi
}

# 获取缓存内容
# 参数: $1 - 缓存键
# 返回: 0 表示命中缓存，1 表示未命中
# 输出: 缓存内容（如果命中）
get_cached() {
  local raw_key="$1"
  local key
  key="$(get_cache_key "$raw_key")"
  local cache_file="$CACHE_DIR/$key"

  if [ -f "$cache_file" ]; then
    # 获取文件修改时间（跨平台兼容）
    local file_mtime
    if stat -f %m "$cache_file" &>/dev/null; then
      # macOS
      file_mtime=$(stat -f %m "$cache_file")
    elif stat -c %Y "$cache_file" &>/dev/null; then
      # Linux
      file_mtime=$(stat -c %Y "$cache_file")
    else
      # 无法获取时间，认为缓存失效
      return 1
    fi

    local current_time
    current_time=$(date +%s)
    local age=$((current_time - file_mtime))

    if [ "$age" -lt "$CACHE_TTL" ]; then
      cat "$cache_file"
      return 0
    fi
  fi
  return 1
}

# 设置缓存内容
# 参数: $1 - 缓存键, $2 - 缓存内容
set_cache() {
  local raw_key="$1"
  local content="$2"
  local key
  key="$(get_cache_key "$raw_key")"
  local cache_file="$CACHE_DIR/$key"

  ensure_cache_dir
  echo "$content" > "$cache_file" 2>/dev/null
}

# 清理过期缓存（可选调用）
# 参数: 无
cleanup_expired_cache() {
  if [ -d "$CACHE_DIR" ]; then
    find "$CACHE_DIR" -type f -mmin +$((CACHE_TTL / 60 + 1)) -delete 2>/dev/null
  fi
}

# 清空所有缓存
# 参数: 无
clear_all_cache() {
  if [ -d "$CACHE_DIR" ]; then
    rm -rf "${CACHE_DIR:?}"/* 2>/dev/null
  fi
}

# 初始化：确保缓存目录存在
ensure_cache_dir
