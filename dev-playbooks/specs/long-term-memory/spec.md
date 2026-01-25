# 规格：对话长期记忆

> **Capability**: long-term-memory
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-17
> **Last Referenced By**: augment-final-10-percent
> **Last Verified**: 2026-01-17
> **Health**: pending

---

## Requirements（需求）

### REQ-LTM-001：突破 10 轮对话限制

系统应支持无限轮对话记忆：

| 指标 | 当前 | 目标 |
|------|------|------|
| 对话轮数 | 10 轮 | 无限制 |
| 记忆召回延迟 | N/A | <100ms |
| 存储效率 | N/A | 每轮 <1KB |

### REQ-LTM-002：滚动摘要机制

系统应实现滚动摘要以压缩历史对话：

```
对话轮次:  1  2  3  4  5  6  7  8  9  10  11  12  ...
           └──────────────┘  └──────────────┘
              摘要 S1             摘要 S2

召回时:
- 最近 5 轮: 完整内容
- 更早轮次: 仅摘要
```

### REQ-LTM-003：符号索引

系统应建立符号到对话的倒排索引：

```sql
-- symbol_index 表结构
CREATE TABLE symbol_index (
  symbol TEXT NOT NULL,
  conversation_id TEXT NOT NULL,
  turn_id INTEGER NOT NULL,
  relevance REAL NOT NULL,  -- 0.0 - 1.0
  context TEXT,              -- 符号出现的上下文
  PRIMARY KEY (symbol, conversation_id, turn_id)
);

CREATE INDEX idx_symbol ON symbol_index(symbol);
CREATE INDEX idx_relevance ON symbol_index(relevance DESC);
```

### REQ-LTM-004：SQLite 存储

系统应使用 SQLite 作为存储后端：

```sql
-- 数据库位置
.devbooks/conversation-memory.db

-- 表结构
CREATE TABLE conversations (
  id TEXT PRIMARY KEY,
  project_root TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_active DATETIME,
  summary TEXT,
  turn_count INTEGER DEFAULT 0
);

CREATE TABLE turns (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  conversation_id TEXT NOT NULL,
  role TEXT NOT NULL,  -- 'user' | 'assistant'
  content TEXT NOT NULL,
  symbols TEXT,  -- JSON array of mentioned symbols
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (conversation_id) REFERENCES conversations(id)
);

CREATE TABLE summaries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  conversation_id TEXT NOT NULL,
  start_turn INTEGER NOT NULL,
  end_turn INTEGER NOT NULL,
  summary TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (conversation_id) REFERENCES conversations(id)
);
```

### REQ-LTM-005：智能召回算法

系统应基于多维度相关性进行召回：

```bash
# 召回分数计算
relevance_score =
  symbol_match * 0.4 +      # 符号匹配度
  recency * 0.3 +           # 时间衰减
  context_similarity * 0.3   # 上下文相似度

# 召回策略
1. 从当前查询提取关键符号
2. 在 symbol_index 中检索匹配项
3. 获取相关的 turns 或 summaries
4. 按 relevance_score 排序
5. 返回 Top-K 结果
```

### REQ-LTM-006：自动符号提取

系统应自动从对话中提取代码符号：

```bash
# 提取规则
- 函数名: processOrder, getUserById
- 类名: OrderService, PaymentHandler
- 文件路径: src/service.ts, lib/utils.js
- 变量名: config, options, result
- 错误类型: TypeError, NetworkError
```

### REQ-LTM-007：隐私与清理

系统应支持对话数据的管理：

```bash
# 清理策略
memory_cleanup --older-than 30d    # 删除 30 天前的对话
memory_cleanup --conversation <id>  # 删除指定对话
memory_cleanup --all                # 清空所有记忆

# 导出/导入
memory_export --format json > backup.json
memory_import < backup.json
```

### REQ-LTM-008：并发安全

系统应保证多会话并发访问的安全性：

```bash
# SQLite 并发配置
PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=5000;
PRAGMA synchronous=NORMAL;
```

---

## Scenarios（场景）

### SC-LTM-001：记忆跨越 100 轮对话

**Given**: 用户与系统进行了 100 轮对话
**When**: 在第 101 轮查询 "之前讨论的 OrderService 问题"
**Then**:
- 系统召回相关的历史上下文
- 包含早期对话的摘要
- 包含最近对话的完整内容

### SC-LTM-002：基于符号的精确召回

**Given**:
- 第 20 轮讨论了 `processPayment` 函数的 bug
- 第 50 轮讨论了 `validateOrder` 函数的重构
**When**: 查询 "之前 processPayment 的问题解决了吗"
**Then**:
- 召回第 20 轮的相关内容
- 不召回第 50 轮的无关内容
- 延迟 < 100ms

### SC-LTM-003：滚动摘要生成

**Given**: 对话轮数达到 10 轮
**When**: 系统执行定期摘要
**Then**:
- 生成第 1-5 轮的摘要
- 保留第 6-10 轮的完整内容
- 摘要包含关键符号和结论

### SC-LTM-004：新会话继承记忆

**Given**:
- 昨天的会话讨论了 `CacheManager` 的实现
- 今天开始新会话
**When**: 查询 "继续昨天的缓存实现"
**Then**:
- 识别到 `CacheManager` 相关的历史对话
- 召回昨天的讨论摘要
- 提供连续的上下文

### SC-LTM-005：并发会话隔离

**Given**:
- 会话 A 讨论项目 X
- 会话 B 讨论项目 Y
**When**: 两个会话同时写入记忆
**Then**:
- 数据正确写入各自的对话记录
- 无数据混淆
- 无锁竞争超时

### SC-LTM-006：记忆清理

**Given**: 数据库中有 60 天的对话记录
**When**: 运行 `memory_cleanup --older-than 30d`
**Then**:
- 删除 30 天前的对话和轮次
- 保留最近 30 天的数据
- 更新符号索引

---

## API 契约

### memory_store

```bash
# 存储对话轮次
memory_store --conversation <id> --role <user|assistant> --content <text>

# 返回
{
  "turn_id": 42,
  "conversation_id": "conv-20260117-abc123",
  "symbols_extracted": ["OrderService", "processPayment", "src/order.ts"],
  "stored_at": "2026-01-17T10:30:00Z"
}
```

### memory_recall

```bash
# 召回相关记忆
memory_recall --query "processPayment 函数的问题" --limit 5

# 返回
{
  "results": [
    {
      "conversation_id": "conv-20260115-def456",
      "turn_id": 23,
      "role": "assistant",
      "content": "processPayment 函数存在并发问题...",
      "relevance": 0.92,
      "created_at": "2026-01-15T14:20:00Z",
      "is_summary": false
    },
    {
      "conversation_id": "conv-20260110-ghi789",
      "turn_id": null,
      "summary": "讨论了 OrderService 的支付流程重构...",
      "relevance": 0.75,
      "created_at": "2026-01-10T09:15:00Z",
      "is_summary": true
    }
  ],
  "total_searched": 150,
  "latency_ms": 45
}
```

### memory_summarize

```bash
# 生成摘要
memory_summarize --conversation <id> --from-turn 1 --to-turn 10

# 返回
{
  "summary_id": 5,
  "conversation_id": "conv-20260117-abc123",
  "turns_summarized": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
  "summary": "讨论了 OrderService 的 processPayment 函数重构，解决了并发问题...",
  "key_symbols": ["OrderService", "processPayment", "mutex"],
  "key_decisions": ["使用互斥锁保护关键区域", "添加重试机制"]
}
```

### memory_cleanup

```bash
# 清理旧记忆
memory_cleanup --older-than 30d

# 返回
{
  "conversations_deleted": 15,
  "turns_deleted": 234,
  "summaries_deleted": 8,
  "space_freed_kb": 512
}
```

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-LTM-001 | SC-LTM-001 | AC-007 |
| REQ-LTM-002 | SC-LTM-003 | AC-007 |
| REQ-LTM-003 | SC-LTM-002 | AC-007 |
| REQ-LTM-004 | All | AC-007 |
| REQ-LTM-005 | SC-LTM-002 | AC-007 |
| REQ-LTM-006 | SC-LTM-002, SC-LTM-004 | AC-007 |
| REQ-LTM-007 | SC-LTM-006 | AC-007 |
| REQ-LTM-008 | SC-LTM-005 | AC-007 |

---

## 非功能需求

### 性能基准

| 操作 | 指标 | 阈值 |
|------|------|------|
| 单轮存储 | 延迟 | <20ms |
| 符号召回（100轮历史） | 延迟 | <100ms |
| 符号召回（1000轮历史） | 延迟 | <200ms |
| 摘要生成（10轮） | 延迟 | <500ms |

### 存储效率

| 数据类型 | 预期大小 |
|----------|----------|
| 单轮对话 | <1KB |
| 10 轮摘要 | <500B |
| 符号索引条目 | <100B |
| 1000 轮历史 | <2MB |

### 可靠性要求

| 场景 | 要求 |
|------|------|
| 数据持久化 | 100%（WAL 模式） |
| 并发写入成功率 | ≥99.9% |
| 数据一致性 | ACID 保证 |

---

## 测试契约

### 单元测试

```bash
# @smoke 快速验证
test_store_and_recall_single_turn
test_symbol_extraction

# @critical 关键功能
test_recall_across_100_turns
test_summary_generation
test_symbol_based_recall_accuracy

# @full 完整覆盖
test_concurrent_sessions
test_memory_cleanup
test_large_history_performance
```

### 集成测试

```bash
# 端到端测试
test_e2e_memory_persistence
test_cross_session_memory
test_incremental_summarization
```

---

## 数据迁移

### 从无状态到有状态

对于现有项目，首次启用长期记忆时：

```bash
# 1. 创建数据库
memory_init

# 2. 从现有日志导入（如果有）
memory_import --from-logs .devbooks/conversation-logs/

# 3. 建立初始索引
memory_reindex
```

### 数据库升级

```sql
-- 版本控制表
CREATE TABLE schema_version (
  version INTEGER PRIMARY KEY,
  applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 升级脚本命名
migrations/001_initial.sql
migrations/002_add_context_column.sql
```
