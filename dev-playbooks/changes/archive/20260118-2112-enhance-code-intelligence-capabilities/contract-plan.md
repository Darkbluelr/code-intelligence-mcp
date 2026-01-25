# 契约与数据定义计划

> **Change-ID**: `20260118-2112-enhance-code-intelligence-capabilities`
> **Created**: 2026-01-19
> **Status**: Draft

---

## A) 契约与数据定义计划

### 1. CLI 接口契约变更

#### 1.1 新增 CLI 参数（向后兼容）

| 脚本 | 新增参数 | 默认值 | 兼容性 | Contract Test ID |
|------|----------|--------|--------|------------------|
| `call-chain.sh` | `--data-flow` | false | 向后兼容 | CT-CLI-001 |
| `call-chain.sh` | `--max-depth <n>` | 5 | 向后兼容 | CT-CLI-002 |
| `context-compressor.sh` | `--compress <level>` | medium | 新脚本 | CT-CLI-003 |
| `context-compressor.sh` | `--budget <tokens>` | 无限制 | 新脚本 | CT-CLI-004 |
| `drift-detector.sh` | `--snapshot` | - | 新脚本 | CT-CLI-005 |
| `drift-detector.sh` | `--compare <file>` | - | 新脚本 | CT-CLI-006 |
| `drift-detector.sh` | `--report` | - | 新脚本 | CT-CLI-007 |
| `graph-store.sh` | `--migrate` | - | 向后兼容 | CT-CLI-008 |
| `graph-store.sh` | `--rebuild-closure` | - | 向后兼容 | CT-CLI-009 |
| `embedding.sh` | `--hybrid <query>` | - | 向后兼容 | CT-CLI-010 |
| `embedding.sh` | `--weights <k,v,g>` | 0.3,0.5,0.2 | 向后兼容 | CT-CLI-011 |
| `graph-rag.sh` | `--no-rerank` | false | 向后兼容 | CT-CLI-012 |
| `graph-rag.sh` | `--rerank-strategy <s>` | auto | 向后兼容 | CT-CLI-013 |
| `benchmark.sh` | `--dataset <type>` | self | 新脚本 | CT-CLI-014 |
| `benchmark.sh` | `--baseline` | - | 新脚本 | CT-CLI-015 |
| `benchmark.sh` | `--compare <file>` | - | 新脚本 | CT-CLI-016 |

**兼容策略**：
- 所有新增参数为可选参数
- 不修改现有参数的语义
- 默认行为保持不变

**Contract Tests**：
- 测试新增参数的解析
- 测试默认值行为
- 测试向后兼容性（不传新参数时行为不变）

---

### 2. 配置文件契约变更

#### 2.1 config/features.yaml 新增配置项

```yaml
# 新增配置项（向后兼容）
features:
  context_compression: true
  drift_detection: true
  data_flow_tracing: true
  graph_acceleration: true
  hybrid_retrieval: true
  reranker: true
  context_signals: true
  anomaly_feedback: true
  benchmark: true

# 混合检索权重配置
hybrid_retrieval:
  enabled: true
  weights:
    keyword: 0.3
    vector: 0.5
    graph: 0.2
  rrf_k: 60

# 重排序配置
reranker:
  enabled: true
  strategy: auto  # auto/llm/heuristic
  llm_timeout: 5000  # ms

# 上下文信号配置
context_signals:
  enabled: true
  fix_weight: true
  intent_weight: true
  session_focus: true
  decay_enabled: true
  decay_days: 90
```

**Schema 版本**：v1.0.0

**兼容策略**：
- 所有新增配置项有默认值
- 缺失配置项时使用默认值
- 不破坏现有配置项

**Contract Test ID**: CT-CONFIG-001

---

### 3. SQLite Schema 契约变更

#### 3.1 Schema 版本迁移（v1 → v2）

**新增表 1：schema_version**

```sql
CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER PRIMARY KEY,
  applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  description TEXT
);
```

**Contract Test ID**: CT-SCHEMA-001

---

**新增表 2：transitive_closure（闭包表）**

```sql
CREATE TABLE IF NOT EXISTS transitive_closure (
  ancestor TEXT NOT NULL,
  descendant TEXT NOT NULL,
  depth INTEGER NOT NULL,
  PRIMARY KEY (ancestor, descendant)
);

CREATE INDEX idx_closure_ancestor ON transitive_closure(ancestor);
CREATE INDEX idx_closure_descendant ON transitive_closure(descendant);
CREATE INDEX idx_closure_depth ON transitive_closure(depth);
```

**Contract Test ID**: CT-SCHEMA-002

---

**新增表 3：path_index（路径索引表）**

```sql
CREATE TABLE IF NOT EXISTS path_index (
  path_id INTEGER PRIMARY KEY AUTOINCREMENT,
  source TEXT NOT NULL,
  target TEXT NOT NULL,
  path TEXT NOT NULL,  -- JSON 数组
  length INTEGER NOT NULL,
  frequency INTEGER DEFAULT 1,
  last_accessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_path_source ON path_index(source);
CREATE INDEX idx_path_target ON path_index(target);
CREATE INDEX idx_path_length ON path_index(length);
```

**Contract Test ID**: CT-SCHEMA-003

---

**新增表 4：user_signals（用户交互信号表）**

```sql
CREATE TABLE IF NOT EXISTS user_signals (
  signal_id INTEGER PRIMARY KEY AUTOINCREMENT,
  file_path TEXT NOT NULL,
  signal_type TEXT NOT NULL,  -- view/edit/ignore
  weight REAL NOT NULL,
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_signals_file ON user_signals(file_path);
CREATE INDEX idx_signals_type ON user_signals(signal_type);
CREATE INDEX idx_signals_timestamp ON user_signals(timestamp);
```

**Contract Test ID**: CT-SCHEMA-004

---

#### 3.2 Schema 迁移契约

**迁移步骤**：
1. 检测当前 Schema 版本
2. 备份数据库：`cp graph.db graph.db.backup`
3. 执行迁移 SQL（创建新表）
4. 预计算闭包表
5. 更新 schema_version 为 2
6. 验证数据完整性

**失败回滚**：
- 迁移失败时自动恢复备份
- 记录迁移日志到 `.devbooks/migration.log`

**幂等性**：
- 迁移脚本可重复执行
- 已迁移的数据库不会重复迁移

**Contract Test ID**: CT-MIGRATION-001

---

### 4. 输出格式契约变更

#### 4.1 数据流追踪输出格式（扩展）

**新增字段**：
```json
{
  "source": { ... },
  "sink": { ... },
  "path": [ ... ],
  "depth": 4,
  "transforms_count": 4,
  "truncated": false,  // 新增：是否截断
  "cycle_detected": false,  // 新增：是否检测到循环
  "cycle_path": []  // 新增：循环路径
}
```

**兼容策略**：
- 新增字段为可选字段
- 旧版本客户端可忽略新字段

**Contract Test ID**: CT-OUTPUT-001

---

#### 4.2 上下文压缩输出格式（新增）

```json
{
  "compressed_context": "...",
  "metadata": {
    "original_tokens": 10000,
    "compressed_tokens": 3500,
    "compression_ratio": 0.65,
    "files_processed": 5,
    "cache_hits": 3
  },
  "files": [ ... ],
  "preserved_signatures": [ ... ]
}
```

**Contract Test ID**: CT-OUTPUT-002

---

#### 4.3 架构漂移报告格式（新增）

```json
{
  "drift_score": 55,
  "level": "severe",  // normal/warning/severe
  "changes": [
    {
      "type": "undocumented_component",
      "component": "NewService",
      "weight": 0.3
    }
  ],
  "recommendations": [ ... ]
}
```

**Contract Test ID**: CT-OUTPUT-003

---

#### 4.4 混合检索输出格式（扩展）

**新增字段**：
```json
{
  "results": [ ... ],
  "metadata": {
    "retrieval_method": "hybrid",  // 新增
    "weights": {  // 新增
      "keyword": 0.3,
      "vector": 0.5,
      "graph": 0.2
    },
    "rrf_k": 60,  // 新增
    "degraded": false  // 新增：是否降级
  }
}
```

**Contract Test ID**: CT-OUTPUT-004

---

#### 4.5 异常检测输出格式（新增）

```jsonl
{"file": "src/service.ts", "type": "pattern_deviation", "confidence": 0.85, "line": 42, "description": "..."}
```

**Contract Test ID**: CT-OUTPUT-005

---

### 5. 契约测试清单

| Test ID | 测试内容 | 断言点 | 优先级 |
|---------|----------|--------|--------|
| CT-CLI-001 | `call-chain.sh --data-flow` 参数解析 | 参数正确解析，启用数据流追踪 | P0 |
| CT-CLI-002 | `call-chain.sh --max-depth` 参数解析 | 深度限制生效 | P0 |
| CT-CLI-003 | `context-compressor.sh --compress` 参数解析 | 压缩级别正确应用 | P0 |
| CT-CLI-008 | `graph-store.sh --migrate` 迁移命令 | 迁移成功，Schema 版本更新 | P0 |
| CT-CLI-010 | `embedding.sh --hybrid` 混合检索 | 三种检索方法融合 | P1 |
| CT-CONFIG-001 | 配置文件解析 | 所有新增配置项正确解析 | P0 |
| CT-SCHEMA-001 | schema_version 表创建 | 表结构正确 | P0 |
| CT-SCHEMA-002 | transitive_closure 表创建 | 表结构和索引正确 | P0 |
| CT-SCHEMA-003 | path_index 表创建 | 表结构和索引正确 | P1 |
| CT-SCHEMA-004 | user_signals 表创建 | 表结构和索引正确 | P2 |
| CT-MIGRATION-001 | Schema 迁移幂等性 | 重复迁移不报错 | P0 |
| CT-OUTPUT-001 | 数据流追踪输出格式 | 新增字段存在且格式正确 | P0 |
| CT-OUTPUT-002 | 上下文压缩输出格式 | JSON Schema 验证通过 | P0 |
| CT-OUTPUT-003 | 架构漂移报告格式 | JSON Schema 验证通过 | P0 |
| CT-OUTPUT-004 | 混合检索输出格式 | 新增字段存在且格式正确 | P1 |
| CT-OUTPUT-005 | 异常检测输出格式 | JSONL 格式正确 | P2 |

---

### 6. 兼容性矩阵

| 契约类型 | 向前兼容 | 向后兼容 | 迁移需求 | 降级方案 |
|----------|----------|----------|----------|----------|
| CLI 接口 | ✅ | ✅ | 无 | N/A |
| 配置文件 | ✅ | ✅ | 无 | 使用默认值 |
| SQLite Schema | ✅ | ❌ | 自动迁移 | 恢复备份 |
| 输出格式 | ✅ | ✅ | 无 | 忽略新字段 |

**说明**：
- ✅ 向前兼容：新版本可处理旧版本数据
- ✅ 向后兼容：旧版本可处理新版本数据（忽略新字段）
- ❌ SQLite Schema 不向后兼容：旧版本无法读取 v2 Schema

---

### 7. 弃用策略

**本次变更无弃用项**。所有变更为新增或扩展，不删除现有功能。

---

### 8. 迁移路径

#### 8.1 用户升级路径

**从 v0.x 升级到 v1.0**：

1. **备份数据**：
   ```bash
   cp .devbooks/graph.db .devbooks/graph.db.backup
   cp config/features.yaml config/features.yaml.backup
   ```

2. **拉取最新代码**：
   ```bash
   git pull origin master
   npm install
   ```

3. **运行迁移**：
   ```bash
   # 自动迁移（推荐）
   npm start  # 启动时自动检测并迁移

   # 手动迁移
   scripts/graph-store.sh --migrate
   ```

4. **验证迁移**：
   ```bash
   sqlite3 .devbooks/graph.db "SELECT * FROM schema_version;"
   # 预期输出：version = 2

   npm test -- tests/graph-store.bats
   ```

5. **配置新功能**（可选）：
   ```bash
   # 编辑 config/features.yaml
   # 启用/禁用新功能
   ```

**预计升级时间**：
- 小型项目（< 1000 符号）：< 1 分钟
- 中型项目（1000-5000 符号）：1-3 分钟
- 大型项目（> 5000 符号）：3-10 分钟

---

#### 8.2 回滚路径

**如果升级失败**：

1. **停止服务**：
   ```bash
   pkill -f "node.*server.ts"
   ```

2. **恢复数据库**：
   ```bash
   mv .devbooks/graph.db.backup .devbooks/graph.db
   ```

3. **恢复配置**：
   ```bash
   mv config/features.yaml.backup config/features.yaml
   ```

4. **回退代码**：
   ```bash
   git checkout <previous-commit>
   npm install
   ```

5. **重启服务**：
   ```bash
   npm start
   ```

---

## B) 追溯摘要

### AC → 契约文件 → Contract Test IDs

| AC-ID | 契约文件 | Contract Test IDs |
|-------|----------|-------------------|
| AC-001 | CLI: context-compressor.sh | CT-CLI-003, CT-CLI-004 |
| AC-001 | 输出: 上下文压缩格式 | CT-OUTPUT-002 |
| AC-002 | CLI: drift-detector.sh | CT-CLI-005, CT-CLI-006, CT-CLI-007 |
| AC-002 | 输出: 架构漂移报告格式 | CT-OUTPUT-003 |
| AC-003 | CLI: call-chain.sh | CT-CLI-001, CT-CLI-002 |
| AC-003 | 输出: 数据流追踪格式 | CT-OUTPUT-001 |
| AC-004 | CLI: graph-store.sh | CT-CLI-008, CT-CLI-009 |
| AC-004 | Schema: 闭包表和路径索引 | CT-SCHEMA-001, CT-SCHEMA-002, CT-SCHEMA-003 |
| AC-004 | Schema: 迁移逻辑 | CT-MIGRATION-001 |
| AC-005 | CLI: embedding.sh | CT-CLI-010, CT-CLI-011 |
| AC-005 | 配置: 混合检索权重 | CT-CONFIG-001 |
| AC-005 | 输出: 混合检索格式 | CT-OUTPUT-004 |
| AC-006 | CLI: graph-rag.sh | CT-CLI-012, CT-CLI-013 |
| AC-006 | 配置: 重排序策略 | CT-CONFIG-001 |
| AC-007 | 配置: 上下文信号 | CT-CONFIG-001 |
| AC-007 | Schema: user_signals 表 | CT-SCHEMA-004 |
| AC-008 | 输出: 异常检测格式 | CT-OUTPUT-005 |
| AC-009 | CLI: benchmark.sh | CT-CLI-014, CT-CLI-015, CT-CLI-016 |
| AC-010 | 配置: 功能开关 | CT-CONFIG-001 |
| AC-011 | CLI: benchmark.sh --compare | CT-CLI-016 |
| AC-012 | Schema: 迁移逻辑 | CT-MIGRATION-001 |

---

## C) Contract Tests 实现计划

### 测试框架

使用 Bats (Bash Automated Testing System) 实现契约测试。

### 测试文件组织

```
tests/
├── contract/
│   ├── cli-contract.bats          # CLI 接口契约测试
│   ├── config-contract.bats       # 配置文件契约测试
│   ├── schema-contract.bats       # Schema 契约测试
│   ├── migration-contract.bats    # 迁移契约测试
│   └── output-contract.bats       # 输出格式契约测试
```

### 测试优先级

- **P0（阻断）**：CLI 核心参数、Schema 迁移、配置解析
- **P1（重要）**：混合检索、重排序、输出格式
- **P2（一般）**：上下文信号、异常检测

### 测试覆盖目标

- CLI 契约测试覆盖率：100%
- Schema 契约测试覆盖率：100%
- 输出格式契约测试覆盖率：≥90%

---

**契约计划结束**
