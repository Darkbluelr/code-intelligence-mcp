# 提案：弥合 Augment 最后 10% 轻资产差距

> **Change ID**: `augment-final-10-percent`
> **Version**: 1.1.0
> **Status**: Approved (Revised)
> **Created**: 2026-01-17
> **Author**: AI Assistant
> **Last Modified**: 2026-01-17

---

## 1. Why（为什么要做）

### 1.1 背景

根据与 Augment Code 的深度对比分析，本项目已实现约 **85%** 的代码智能能力对等。在"轻资产"范围内（代码、算法，不含自研模型和大数据），理论可达上限为 **95%**，存在约 **10%** 的提升空间。

### 1.2 当前差距总览

| # | 差距项 | 当前状态 | 目标 | 优先级 |
|---|--------|---------|------|--------|
| 1 | LLM 重排序抽象接口 | 硬编码 Anthropic | 可插拔多厂商 | P0 |
| 2 | 语义异常检测 | 未实现 | 基于模式学习 | P0 |
| 3 | 跨函数数据流追踪 | 单函数级 | 多函数链式 | P0 |
| 4 | 击键级请求取消 | 50ms | <10ms | P1 |
| 5 | 上下文智能压缩 | 未实现 | AST 语义摘要 | P1 |
| 6 | 对话长期记忆 | 10 轮 | 无限 + 摘要 | P1 |
| 7 | 联邦图查询 | 本地单仓库 | 跨仓库查询 | P2 |
| 8 | COD 实时更新 | 静态快照 | 文件监听增量 | P2 |
| 9 | A-B 路径可视化 | JSON 输出 | Mermaid 集成 | P2 |
| 10 | 架构漂移检测 | 未实现 | 快照对比告警 | P2 |

### 1.3 业务价值

- **提升 Bug 定位准确率**：语义异常 + 跨函数数据流 → 预计 +15%
- **降低响应延迟**：击键级取消 + 智能压缩 → P95 从 3s 降至 <1s
- **增强企业级能力**：联邦查询 + 架构漂移检测 → 支持大规模微服务
- **提升开发者体验**：长期记忆 + 实时更新 → 减少重复上下文

---

## 2. What（做什么）

### 2.1 核心交付物

#### M1: LLM 重排序抽象接口（P0）

**目标**：实现可插拔的 LLM Provider 架构，方便扩展不同厂商。

```
┌─────────────────────────────────────────────────────────┐
│                    Reranker Interface                    │
├─────────────────────────────────────────────────────────┤
│  rerank(query, candidates) → RankedResult               │
│  get_provider_info() → ProviderInfo                     │
│  validate_config() → bool                               │
└─────────────────────────────────────────────────────────┘
        ▲               ▲               ▲
        │               │               │
┌───────┴───────┐ ┌─────┴─────┐ ┌───────┴───────┐
│ AnthropicImpl │ │ OpenAIImpl│ │  OllamaImpl   │
└───────────────┘ └───────────┘ └───────────────┘
```

**交付物**：
- `scripts/llm-provider.sh` - Provider 抽象层
- `scripts/llm-providers/` - 各厂商实现
- 配置驱动的 Provider 选择

#### M2: 语义异常检测（P0）

**目标**：基于已有的 pattern-learner 扩展，检测违反项目隐式规范的代码。

**检测类型**：
- 缺失的错误处理模式
- 不一致的 API 调用方式
- 违反命名约定
- 遗漏的日志/监控

**交付物**：
- `scripts/semantic-anomaly.sh` - 异常检测器
- 与 pattern-learner 集成

#### M3: 跨函数数据流追踪（P0）

**目标**：扩展 call-chain.sh，支持变量在多函数间的传递追踪。

```
函数 A: x = input()
    ↓ 传参
函数 B: y = process(x)
    ↓ 返回
函数 C: output(y)  ← Bug 在这里，但根因在 A
```

**交付物**：
- `call-chain.sh --data-flow` 选项
- 变量污点追踪算法

#### M4: 击键级请求取消（P1）

**目标**：将请求取消延迟从 50ms 优化到 <10ms。

**优化方向**：
- 使用信号机制（SIGUSR1）替代轮询
- 预分配取消令牌
- 零拷贝状态检查

**交付物**：
- `daemon.sh` 优化
- 新增 `--cancel-token` 参数

#### M5: 上下文智能压缩（P1）

**目标**：将大型代码库压缩为高信噪比的上下文。

**压缩策略**：
- AST 骨架提取（保留结构，移除实现）
- 符号签名摘要
- 热点优先选择

**交付物**：
- `scripts/context-compressor.sh`
- Token 预算感知的压缩算法

#### M6: 对话长期记忆（P1）

**目标**：突破 10 轮限制，实现无限对话历史。

**实现方案**：
- 滚动摘要（每 10 轮生成摘要）
- 关键符号向量化索引
- 按需召回历史上下文

**交付物**：
- `intent-learner.sh` 扩展
- `.devbooks/conversation-memory.db`

#### M7: 联邦图查询（P2）

**目标**：支持跨仓库的符号查询。

**实现方案**：
- SQLite 附加数据库（ATTACH）
- HTTP 桥接远程仓库索引
- 虚拟边合并算法

**交付物**：
- `federation-lite.sh --query-remote`
- 联邦查询协议

#### M8: COD 实时更新（P2）

**目标**：文件变更时自动更新架构图。

**实现方案**：
- fswatch/inotify 监听
- 增量图更新（仅变更节点）
- 防抖动机制（500ms）

**交付物**：
- `cod-visualizer.sh --watch`
- 增量更新 API

#### M9: A-B 路径可视化（P2）

**目标**：将符号间路径渲染为 Mermaid 图。

**交付物**：
- `graph-store.sh find-path --format mermaid`
- 集成到 cod-visualizer

#### M10: 架构漂移检测（P2）

**目标**：检测架构随时间的退化。

**检测指标**：
- 模块边界模糊化
- 依赖方向违规增长
- 热点文件耦合度上升

**交付物**：
- `scripts/drift-detector.sh`
- 定期快照对比报告

---

## 3. Impact（影响范围）

### 3.1 受影响模块

| 模块 | 变更类型 | 影响程度 |
|------|----------|----------|
| `scripts/common.sh` | 扩展 | 中 |
| `scripts/reranker.sh` | 重构 | 高 |
| `scripts/call-chain.sh` | 扩展 | 中 |
| `scripts/daemon.sh` | 优化 | 中 |
| `scripts/intent-learner.sh` | 扩展 | 中 |
| `scripts/pattern-learner.sh` | 扩展 | 低 |
| `scripts/federation-lite.sh` | 扩展 | 中 |
| `scripts/cod-visualizer.sh` | 扩展 | 中 |
| `scripts/graph-store.sh` | 扩展 | 低 |
| `config/features.yaml` | 新增配置 | 低 |

### 3.2 新增文件

```
scripts/
├── llm-provider.sh           # LLM 抽象层
├── llm-providers/
│   ├── anthropic.sh          # Anthropic 实现
│   ├── openai.sh             # OpenAI 实现
│   ├── ollama.sh             # Ollama 实现
│   └── mock.sh               # Mock 实现（测试）
├── semantic-anomaly.sh       # 语义异常检测
├── context-compressor.sh     # 上下文压缩
└── drift-detector.sh         # 架构漂移检测
```

### 3.3 风险评估

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| LLM API 兼容性差异 | 中 | 中 | 统一响应解析层 |
| 数据流追踪性能 | 中 | 高 | 深度限制 + 缓存 |
| 请求取消竞态条件 | 低 | 高 | 原子操作 + 测试覆盖 |
| 联邦查询延迟 | 中 | 中 | 本地缓存 + 超时 |

---

## 4. Debate Packet（决策点）

### DP-001: LLM Provider 抽象层级

**选项 A**：Bash 函数级抽象（推荐）
- 优点：简单、与现有架构一致
- 缺点：扩展性有限

**选项 B**：独立脚本 + 配置注册
- 优点：高度可扩展
- 缺点：增加复杂度

**建议**：选项 A，后续按需升级

### DP-002: 数据流追踪算法

**选项 A**：静态 AST 分析
- 优点：准确、确定性
- 缺点：不支持动态类型

**选项 B**：SCIP + 类型推断
- 优点：支持动态语言
- 缺点：依赖 SCIP 质量

**建议**：选项 B，充分利用现有 SCIP 索引

### DP-003: 长期记忆存储

**选项 A**：JSON 文件
- 优点：简单
- 缺点：查询慢

**选项 B**：SQLite 数据库
- 优点：支持复杂查询、向量搜索扩展
- 缺点：额外依赖

**建议**：选项 B，与现有 graph.db 保持一致

---

## 5. 验收标准（AC）

> **更新说明**：根据 Challenger 质疑，补充量化指标、边界条件和测试环境定义。

### 5.1 LLM Provider 抽象（M1）

| AC ID | 描述 | 量化指标 | 验证方式 |
|-------|------|----------|----------|
| AC-001 | 支持 Anthropic/OpenAI/Ollama/Mock 四种 Provider | 100% Provider 覆盖 | 单元测试 |
| AC-002 | Provider 切换无需修改调用代码，切换延迟 <100ms | 切换延迟 P95 <100ms | 集成测试 |

### 5.2 语义异常检测（M2）

| AC ID | 描述 | 量化指标 | 验证方式 |
|-------|------|----------|----------|
| AC-003 | 识别以下异常模式：(1)缺失错误处理 (2)不一致API调用 (3)命名约定违规 (4)遗漏日志/监控 | 召回率 >=80%，误报率 <20% | 场景测试 |

### 5.3 数据流追踪（M3）

| AC ID | 描述 | 量化指标 | 验证方式 |
|-------|------|----------|----------|
| AC-004 | 支持跨函数数据流追踪 | 最大深度 5 跳，支持跨文件，循环依赖报告 `CYCLE_DETECTED` | 场景测试 |
| AC-004a | 追踪性能约束 | 单跳延迟 P95 <100ms，总时间上限 500ms | 性能测试 |

### 5.4 击键级请求取消（M4）

| AC ID | 描述 | 量化指标 | 验证方式 |
|-------|------|----------|----------|
| AC-005 | 请求取消延迟优化 | P95 <10ms（热启动），P95 <50ms（冷启动） | 性能测试 |
| AC-005a | 测试环境 | MacBook Pro M2 16GB / Intel i7-10th 16GB，10 并发 | 基准测试 |

### 5.5 上下文智能压缩（M5）

| AC ID | 描述 | 量化指标 | 验证方式 |
|-------|------|----------|----------|
| AC-006 | 上下文压缩率（Token 计） | >=50% 压缩率，语义保留度 >=90%（人工评估） | 基准测试 |
| AC-006a | 多语言支持 | TypeScript 必须支持，Python/Go 可选 | 功能测试 |

### 5.6 对话长期记忆（M6）

| AC ID | 描述 | 量化指标 | 验证方式 |
|-------|------|----------|----------|
| AC-007 | 对话记忆容量 | >=100 轮历史，存储空间 <50MB/100轮 | 功能测试 |
| AC-007a | 召回准确率 | Top-5 召回准确率 >=80% | 基准测试 |

### 5.7 联邦图查询（M7）

| AC ID | 描述 | 量化指标 | 验证方式 |
|-------|------|----------|----------|
| AC-008 | 联邦查询延迟 | P95 <500ms（本地缓存命中），P95 <2s（远程查询） | 性能测试 |
| AC-008a | 认证机制 | 支持 Bearer Token 认证 | 集成测试 |
| AC-008b | 离线模式 | 远程不可用时降级到本地缓存，TTL 24h | 功能测试 |

### 5.8 COD 实时更新（M8）

| AC ID | 描述 | 量化指标 | 验证方式 |
|-------|------|----------|----------|
| AC-009 | COD 增量更新延迟 | <1s（单文件变更），<5s（批量变更 <=10 文件） | 性能测试 |
| AC-009a | 跨平台支持 | macOS (fswatch) + Linux (inotify) | 功能测试 |
| AC-009b | 防抖动阈值 | 默认 500ms，用户可配置 100-2000ms | 配置测试 |

### 5.9 A-B 路径可视化（M9）

| AC ID | 描述 | 量化指标 | 验证方式 |
|-------|------|----------|----------|
| AC-009c | Mermaid 图输出 | 节点数上限 50，超出提供文本摘要 | 功能测试 |

### 5.10 架构漂移检测（M10）

| AC ID | 描述 | 量化指标 | 验证方式 |
|-------|------|----------|----------|
| AC-010 | 架构漂移检测报告 | 检测耦合度变化 >10%、依赖方向违规、模块边界模糊 | 验收测试 |
| AC-010a | 快照格式 | JSON Schema 定义，支持 diff 对比 | 功能测试 |

---

## 6. 排期建议

### Phase 1: P0 功能（核心能力）
- M1: LLM 重排序抽象接口
- M2: 语义异常检测
- M3: 跨函数数据流追踪

### Phase 2: P1 功能（性能优化）
- M4: 击键级请求取消
- M5: 上下文智能压缩
- M6: 对话长期记忆

### Phase 3: P2 功能（企业增强）
- M7: 联邦图查询
- M8: COD 实时更新
- M9: A-B 路径可视化
- M10: 架构漂移检测

---

## 7. 性能基线（Performance Baseline）

> **对应质疑**：遗漏-002，AC-005/006/008/009 缺少基线数据

### 7.1 当前性能基线

| 指标 | 当前值 | 测试环境 | 测量方式 |
|------|--------|----------|----------|
| 请求取消延迟 | 50ms (P95) | MacBook Pro M2, 16GB | `daemon.sh --benchmark cancel` |
| 上下文压缩率 | N/A（未实现） | - | - |
| 联邦查询延迟 | 200ms (P95, 本地) | SQLite 单库 | `federation-lite.sh --benchmark` |
| COD 增量更新 | 3-5s (全量重建) | 中型项目 ~10K 符号 | `cod-visualizer.sh --benchmark` |

### 7.2 目标性能指标

| 指标 | 当前值 | 目标值 | 提升幅度 | 验证脚本 |
|------|--------|--------|----------|----------|
| 请求取消延迟 (P95) | 50ms | <10ms | 5x | `scripts/benchmark.sh cancel` |
| 上下文压缩率 | 0% | >=50% | - | `scripts/benchmark.sh compress` |
| 联邦查询延迟 (P95) | 200ms | <500ms | - | `scripts/benchmark.sh federation` |
| COD 增量更新 | 3000ms | <1000ms | 3x | `scripts/benchmark.sh cod` |

### 7.3 测试环境标准化

**基准测试环境定义**：
- **CPU**: Apple M2 或 Intel i7-10th 等效
- **内存**: 16GB RAM
- **存储**: SSD
- **并发**: 单线程基准，10 并发压力
- **数据集**: 中型项目（10K 符号，500 文件）

**测试方法**：
```bash
# 运行完整性能基准测试
scripts/benchmark.sh --all --output evidence/baseline/

# 单项测试
scripts/benchmark.sh cancel --iterations 1000
scripts/benchmark.sh compress --dataset tests/fixtures/medium-project/
```

### 7.4 性能回归检测

- 每次 CI 运行 `@smoke` 级性能测试
- PR 合并前运行 `@critical` 级性能测试
- Release 前运行 `@full` 级性能测试（含压力测试）
- 性能回归阈值：P95 延迟上升 >20% 触发告警

---

## 8. 功能开关策略（Feature Toggle Strategy）

> **对应质疑**：遗漏-004，缺少功能开关/渐进发布策略

### 8.1 功能开关命名规范

所有新功能遵循 `config/features.yaml` 现有格式：

```yaml
features:
  <module_name>:
    enabled: <bool>        # 主开关
    <sub_config>: <value>  # 子配置项
```

### 8.2 新增功能开关清单

| 模块 | 开关名称 | 默认值 | 灰度阶段 | 说明 |
|------|----------|--------|----------|------|
| M1 | `llm_provider.enabled` | true | GA | Provider 抽象层 |
| M1 | `llm_provider.default_provider` | anthropic | GA | 默认 Provider |
| M2 | `semantic_anomaly.enabled` | false | Beta | 语义异常检测 |
| M2 | `semantic_anomaly.patterns` | [error_handling, api_consistency, naming] | Beta | 启用的检测模式 |
| M3 | `data_flow_tracing.enabled` | false | Beta | 跨函数数据流追踪 |
| M3 | `data_flow_tracing.max_depth` | 5 | Beta | 最大追踪深度 |
| M4 | `daemon.cancel.signal_mode` | file | Alpha | 取消机制（file/signal） |
| M5 | `context_compressor.enabled` | false | Alpha | 上下文压缩 |
| M6 | `conversation_memory.enabled` | true | GA | 对话记忆 |
| M6 | `conversation_memory.storage` | json | Beta | 存储后端（json/sqlite） |
| M7 | `federation.remote_query` | false | Alpha | 远程联邦查询 |
| M8 | `cod_visualizer.watch_mode` | false | Beta | 实时监听模式 |
| M9 | `graph_store.mermaid_output` | true | GA | Mermaid 输出 |
| M10 | `drift_detector.enabled` | false | Alpha | 架构漂移检测 |

### 8.3 灰度阶段定义

| 阶段 | 默认状态 | 准入条件 | 说明 |
|------|----------|----------|------|
| **Alpha** | false | 需手动启用 | 实验性功能，可能有 breaking changes |
| **Beta** | false | 测试通过可启用 | 功能完整但未充分验证 |
| **GA** | true | 生产就绪 | 稳定功能，默认启用 |

### 8.4 回滚机制

每个功能开关支持运行时切换，无需重启：

```bash
# 禁用特定功能
devbooks config set features.semantic_anomaly.enabled false

# 回滚到安全模式（禁用所有 Alpha/Beta 功能）
devbooks config apply --safe-mode
```

**回滚检查点**：
- M1 回滚：切换 `llm_provider.default_provider` 回 `anthropic`
- M3 回滚：设置 `data_flow_tracing.enabled=false`
- M6 回滚：设置 `conversation_memory.storage=json`

---

## 9. 数据迁移计划（Data Migration Plan）

> **对应质疑**：风险-005，JSON -> SQLite 迁移路径未定义

### 9.1 迁移范围

| 数据源 | 当前格式 | 目标格式 | 数据量估算 |
|--------|----------|----------|------------|
| 意图历史 | `intent-history.json` | SQLite `intent.db` | ~10K 条目 |
| 对话上下文 | `conversation-context.json` | SQLite `conversation.db` | ~1K 条目 |

### 9.2 迁移策略

采用**增量迁移 + 双写**策略，确保零停机：

```
阶段 1: 双读单写 (JSON)
  ┌─────────┐    读取优先    ┌─────────┐
  │  JSON   │ <────────────  │  应用   │
  │ (主存储) │               └─────────┘
  └─────────┘

阶段 2: 双读双写
  ┌─────────┐    写入    ┌─────────┐
  │  JSON   │ <──────────│  应用   │
  └─────────┘            └────┬────┘
  ┌─────────┐    写入         │
  │ SQLite  │ <───────────────┘
  └─────────┘

阶段 3: 双读单写 (SQLite)
  ┌─────────┐                 ┌─────────┐
  │  JSON   │    只读备份      │  应用   │
  └─────────┘                 └────┬────┘
  ┌─────────┐    读写主存储        │
  │ SQLite  │ <───────────────────┘
  └─────────┘
```

### 9.3 迁移脚本

```bash
# 迁移命令
devbooks migrate intent-history --from json --to sqlite --dry-run
devbooks migrate intent-history --from json --to sqlite --execute

# 验证迁移
devbooks migrate verify --source .devbooks/intent-history.json \
                        --target .devbooks/intent.db
```

### 9.4 迁移验证检查清单

- [ ] 记录总数一致
- [ ] 时间戳精度无损（毫秒级）
- [ ] UTF-8 编码正确
- [ ] 索引完整性验证
- [ ] 回滚测试通过

### 9.5 向量化扩展

**Embedding 模型选择**：
- **默认**: Ollama `nomic-embed-text`（本地，768 维）
- **可选**: OpenAI `text-embedding-3-small`（1536 维，需 API Key）

**向量搜索配置**：
```yaml
conversation_memory:
  storage: sqlite
  vector_search:
    enabled: true
    model: ollama/nomic-embed-text
    dimensions: 768
    index_type: ivfflat  # SQLite VSS 扩展
    recall_target: 0.85  # Top-5 召回率目标
```

### 9.6 风险缓解

| 风险 | 缓解措施 |
|------|----------|
| 迁移数据丢失 | 迁移前自动备份 JSON 文件 |
| 迁移中断 | 支持断点续传，记录迁移进度 |
| 性能退化 | 迁移后运行基准测试对比 |
| 向量维度不匹配 | 配置校验 + 自动转换 |

---

## 10. Decision Log

| 日期 | 决策 | 状态 |
|------|------|------|
| 2026-01-17 | 提案创建 | Draft |
| 2026-01-17 | Judge 初次裁决：Approved（有条件通过） | Conditional |
| 2026-01-17 | Challenger 质疑：P0 问题需修订 | Challenged |
| 2026-01-17 | 根据质疑修订：新增性能基线(7章)、功能开关策略(8章)、数据迁移计划(9章)；更新 AC 定义 | Revised |

### 修订详情（2026-01-17）

**修订版本**：1.0.0 -> 1.1.0

**修复的 P0 问题**：

| # | 问题 | 修复位置 | 状态 |
|---|------|----------|------|
| 1 | 性能基线数据缺失 | 第 7 章 性能基线 | ✅ 已修复 |
| 2 | 功能开关策略未定义 | 第 8 章 功能开关策略 | ✅ 已修复 |
| 3 | 数据迁移计划缺失 | 第 9 章 数据迁移计划 | ✅ 已修复 |
| 4 | AC 定义不精确 | 第 5 章 验收标准 | ✅ 已修复 |

**主要变更**：
1. **性能基线**：补充当前 P95 延迟（50ms）、压缩率基线（N/A），定义测试环境标准
2. **功能开关**：为 M1-M10 定义 feature flag 名称、默认值、灰度阶段和回滚机制
3. **数据迁移**：定义 JSON -> SQLite 增量迁移 + 双写策略，向量化扩展方案
4. **AC 更新**：
   - AC-001 增加 Mock Provider（测试用）
   - AC-003 枚举具体异常模式，定义误报率
   - AC-004 明确最大深度 5 跳，循环依赖处理
   - AC-005 区分冷/热启动场景
   - AC-007 增加召回率指标
   - AC-008 增加认证和离线模式
   - AC-009 增加跨平台和防抖动配置
   - AC-010 定义漂移量化指标和快照格式

### 首次裁决详情

**裁决**：Approved（有条件通过）

**理由**：

提案整体方向正确，覆盖了与 Augment 对标的关键差距，核心价值主张清晰，范围定义合理。Challenger 提出的问题大多属于实现细节层面，可在后续设计阶段（design.md）中解决，无需重写提案。

主要判断依据：
1. **业务价值明确**：Bug 定位准确率 +15%、P95 延迟降至 <1s 等目标可量化、可验证
2. **技术路径可行**：利用现有 SCIP 索引、pattern-learner 等基础设施扩展
3. **分阶段交付**：P0/P1/P2 优先级划分合理，允许渐进实现
4. **风险可控**：Challenger 指出的技术风险通过设计阶段的 spike 和约束定义可缓解

**必须修复的问题**（进入设计阶段前）：

| # | 问题 | 要求 | 负责阶段 |
|---|------|------|----------|
| 1 | 性能基线数据缺失 | 在 design.md 中补充当前 P95 延迟、压缩率等基线数据 | Design |
| 2 | 功能开关策略未定义 | 在 design.md 中为 P0 功能定义 feature flag 名称和默认值 | Design |
| 3 | 数据迁移计划缺失 | 在 M6 设计中明确 JSON -> SQLite 迁移策略（增量/全量） | Design |
| 4 | 最大追踪深度未明确 | 在 M3 设计中定义最大跳数（建议 5-6）和降级策略 | Design |

**可延后处理的问题**（实现阶段解决）：

| # | 问题 | 处理方式 |
|---|------|----------|
| 1 | 跨平台兼容性（M4/M8） | 在 tasks.md 中拆分平台特定任务 |
| 2 | 联邦查询认证机制（M7） | P2 功能，实现时设计 |
| 3 | 架构漂移量化指标（M10） | P2 功能，实现时定义 |
| 4 | 模块依赖图 | 在 design.md Architecture Impact 章节补充 |
| 5 | 用户文档更新计划 | 使用 devbooks-docs-sync 在 Archive 阶段处理 |

**Challenger 建议的采纳情况**：

| 建议 | 采纳 | 说明 |
|------|------|------|
| 分阶段交付 | ✓ | 保持现有 P0/P1/P2 分阶段，P0 可进一步拆分子任务 |
| 技术 Spike | ✓ | M3（数据流追踪）和 M4（击键级取消）建议先做 spike |
| 定义回滚计划 | △ | 可在 tasks.md 中为每个 Milestone 定义检查点 |
| 可观测性设计 | △ | 作为 design.md 的非功能性需求补充 |

**下一步**：
1. 运行 `devbooks-design-doc skill` 生成 design.md
2. 在 design.md 中解决"必须修复的问题"
3. 对 M3/M4 进行技术 spike 验证可行性

---

## 附录：对等度提升预估

```
变更前后对等度对比

核心图谱能力    ████████████████████░░░░  85% → ██████████████████████░░  92%
上下文引擎      ██████████████████░░░░░░  80% → ████████████████████████  95%
延迟优化        ████████████████████░░░░  85% → ██████████████████████░░  92%
意图理解        ████████████████░░░░░░░░  75% → ██████████████████████░░  90%
企业治理        ██████████████████████░░  90% → ████████████████████████  95%

总体对等度      ████████████████████░░░░  85% → ████████████████████████  95%
```
