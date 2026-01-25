# 验证计划：augment-final-10-percent

> **Change ID**: `augment-final-10-percent`
> **Version**: 1.0.0
> **Status**: Archived
> **Test Owner**: AI Assistant
> **Created**: 2026-01-17
> **Last Updated**: 2026-01-17
> **Archived-At**: 2026-01-17T18:45:00Z
> **Archived-By**: devbooks-archiver

---

## 1. AC 到测试的追溯矩阵

| AC ID | AC 描述 | 测试文件 | 测试用例 | 优先级 | 状态 |
|-------|--------|----------|----------|:------:|:----:|
| AC-001 | 支持 Anthropic/OpenAI/Ollama/Mock 四种 Provider | tests/llm-provider.bats | SC-LPA-001, SC-LPA-002, SC-LPA-003, SC-LPA-005 | P0 | [ ] |
| AC-002 | Provider 切换无需修改调用代码，切换延迟 <100ms | tests/llm-provider.bats | SC-LPA-004 | P0 | [ ] |
| AC-003 | 语义异常检测：召回率 >=80%，误报率 <20% | tests/semantic-anomaly.bats | SC-SA-001, SC-SA-002, SC-SA-003, SC-SA-004 | P0 | [ ] |
| AC-004 | 跨函数数据流追踪：最大深度 5 跳，支持跨文件 | tests/data-flow-tracing.bats | SC-DFT-001, SC-DFT-002, SC-DFT-003, SC-DFT-004 | P0 | [ ] |
| AC-004a | 追踪性能约束：单跳 P95 <100ms，总时间 <500ms | tests/data-flow-tracing.bats | PERF-DFT-001 | P0 | [ ] |
| AC-005 | 请求取消延迟 P95 <10ms（热启动），<50ms（冷启动） | tests/keystroke-cancel.bats | SC-KC-001, SC-KC-002, SC-KC-003, SC-KC-004 | P1 | [ ] |
| AC-005a | 测试环境：MacBook Pro M2 16GB / Intel i7-10th 16GB | tests/keystroke-cancel.bats | PERF-KC-001 | P1 | [ ] |
| AC-006 | 上下文压缩率 >=50%，语义保留度 >=90% | tests/context-compressor.bats | SC-CC-001, SC-CC-002, SC-CC-003, SC-CC-004 | P1 | [ ] |
| AC-006a | TypeScript 必须支持，Python/Go 可选 | tests/context-compressor.bats | SC-CC-005, SC-CC-006 | P1 | [ ] |
| AC-007 | 对话记忆 >=100 轮历史，存储 <50MB/100轮 | tests/long-term-memory.bats | SC-LTM-001, SC-LTM-003 | P1 | [ ] |
| AC-007a | Top-5 召回准确率 >=80% | tests/long-term-memory.bats | SC-LTM-002, SC-LTM-004 | P1 | [ ] |
| AC-008 | 联邦查询延迟 P95 <500ms（缓存），<2s（远程） | tests/federation-lite.bats | SC-FED-001, SC-FED-002 | P2 | [ ] |
| AC-008a | 支持 Bearer Token 认证 | tests/federation-lite.bats | SC-FED-003 | P2 | [ ] |
| AC-008b | 离线模式降级到本地缓存，TTL 24h | tests/federation-lite.bats | SC-FED-004 | P2 | [ ] |
| AC-009 | COD 增量更新延迟 <1s（单文件），<5s（批量 <=10） | tests/cod-visualizer.bats | SC-COD-001, SC-COD-002 | P2 | [ ] |
| AC-009a | 跨平台支持：macOS (fswatch) + Linux (inotify) | tests/cod-visualizer.bats | SC-COD-003 | P2 | [ ] |
| AC-009b | 防抖动阈值：默认 500ms，可配置 100-2000ms | tests/cod-visualizer.bats | SC-COD-004 | P2 | [ ] |
| AC-009c | Mermaid 图输出：节点上限 50，超出提供文本摘要 | tests/graph-store.bats | SC-GS-001 | P2 | [ ] |
| AC-010 | 架构漂移检测：耦合度变化 >10%、依赖违规、边界模糊 | tests/drift-detector.bats | SC-DD-001, SC-DD-002, SC-DD-003 | P2 | [ ] |
| AC-010a | 快照格式：JSON Schema，支持 diff 对比 | tests/drift-detector.bats | SC-DD-004 | P2 | [ ] |

**覆盖摘要**：
- AC 总数：20
- 已有测试覆盖：0（待编写）
- 覆盖率：0%（Red 基线）

---

## 2. 测试计划

### 2.1 测试类型分布

| 测试类型 | 数量 | 用途 | 预期耗时 |
|----------|:----:|------|----------|
| 单元测试 | 48 | 核心逻辑、边界条件 | < 5s/文件 |
| 集成测试 | 12 | API 契约、数据流 | < 30s/文件 |
| 性能测试 | 8 | 延迟、吞吐量基准 | < 60s/文件 |
| 契约测试 | 4 | Provider 接口兼容 | < 10s/文件 |

### 2.2 测试分层标签

| 标签 | 用途 | 测试数量 | 预期执行时间 |
|------|------|:--------:|--------------|
| `@smoke` | 快速反馈，核心路径 | 15 | < 30s 总计 |
| `@critical` | 关键功能验证 | 25 | < 3min 总计 |
| `@full` | 完整验收测试 | 72 | < 15min 总计 |

### 2.3 单元测试清单

#### M1: LLM Provider 抽象（tests/llm-provider.bats）

| Test ID | 测试用例 | 对应场景 | 标签 |
|---------|----------|----------|------|
| T-LPA-001 | Provider 接口加载测试 | SC-LPA-001 | @smoke |
| T-LPA-002 | Anthropic Provider 配置测试 | SC-LPA-001 | @critical |
| T-LPA-003 | OpenAI Provider 配置测试 | SC-LPA-001 | @critical |
| T-LPA-004 | Ollama Provider 配置测试 | SC-LPA-001 | @critical |
| T-LPA-005 | Mock Provider 配置测试 | SC-LPA-005 | @smoke |
| T-LPA-006 | Provider 自动检测测试 | SC-LPA-002 | @critical |
| T-LPA-007 | Provider 降级测试 | SC-LPA-003 | @critical |
| T-LPA-008 | 新 Provider 注册测试 | SC-LPA-004 | @full |
| T-LPA-009 | 统一响应格式验证 | REQ-LPA-005 | @smoke |
| T-LPA-010 | API Key 缺失错误处理 | REQ-LPA-006 | @critical |
| T-LPA-011 | 超时错误处理 | REQ-LPA-006 | @critical |
| T-LPA-012 | 速率限制重试测试 | REQ-LPA-006 | @full |

#### M2: 语义异常检测（tests/semantic-anomaly.bats）

| Test ID | 测试用例 | 对应场景 | 标签 |
|---------|----------|----------|------|
| T-SA-001 | 缺失错误处理检测 | SC-SA-001 | @smoke |
| T-SA-002 | 不一致 API 调用检测 | SC-SA-002 | @critical |
| T-SA-003 | 命名约定违规检测 | SC-SA-003 | @critical |
| T-SA-004 | 缺失日志检测 | REQ-SA-001 | @critical |
| T-SA-005 | 未使用导入检测 | REQ-SA-001 | @full |
| T-SA-006 | 废弃模式检测 | REQ-SA-001 | @full |
| T-SA-007 | Pattern Learner 集成 | SC-SA-004 | @critical |
| T-SA-008 | AST 分析准确性 | REQ-SA-003 | @critical |
| T-SA-009 | 输出格式验证 | REQ-SA-004 | @smoke |
| T-SA-010 | 严重程度分级 | REQ-SA-005 | @full |
| T-SA-011 | 召回率基准测试 | AC-003 | @full |
| T-SA-012 | 误报率基准测试 | AC-003 | @full |

#### M3: 跨函数数据流追踪（tests/data-flow-tracing.bats）

| Test ID | 测试用例 | 对应场景 | 标签 |
|---------|----------|----------|------|
| T-DFT-001 | 正向追踪测试 | SC-DFT-001 | @smoke |
| T-DFT-002 | 反向追踪测试 | SC-DFT-002 | @smoke |
| T-DFT-003 | 双向追踪测试 | REQ-DFT-002 | @critical |
| T-DFT-004 | 跨文件追踪测试 | SC-DFT-003 | @critical |
| T-DFT-005 | 参数传递追踪 | REQ-DFT-003 | @critical |
| T-DFT-006 | 返回值追踪 | REQ-DFT-003 | @critical |
| T-DFT-007 | 赋值追踪 | REQ-DFT-003 | @full |
| T-DFT-008 | 属性访问追踪 | REQ-DFT-003 | @full |
| T-DFT-009 | 深度限制测试 | SC-DFT-004 | @critical |
| T-DFT-010 | 循环依赖检测 | AC-004 | @critical |
| T-DFT-011 | 输出格式验证 | REQ-DFT-005 | @smoke |
| T-DFT-012 | 性能基准测试 | AC-004a | @full |

#### M4: 击键级请求取消（tests/keystroke-cancel.bats）

| Test ID | 测试用例 | 对应场景 | 标签 |
|---------|----------|----------|------|
| T-KC-001 | 单进程取消延迟测试 | SC-KC-001 | @smoke |
| T-KC-002 | 子进程取消传播 | SC-KC-002 | @critical |
| T-KC-003 | 资源清理测试 | SC-KC-003 | @critical |
| T-KC-004 | 并发取消处理 | SC-KC-004 | @full |
| T-KC-005 | 取消超时保护 | SC-KC-005 | @full |
| T-KC-006 | 部分结果返回 | SC-KC-006 | @full |
| T-KC-007 | 取消令牌生命周期 | REQ-KC-003 | @critical |
| T-KC-008 | 信号驱动机制验证 | REQ-KC-002 | @critical |
| T-KC-009 | 取消状态码验证 | REQ-KC-005 | @smoke |
| T-KC-010 | P95 延迟基准测试 | AC-005 | @full |

#### M5: 上下文智能压缩（tests/context-compressor.bats）

| Test ID | 测试用例 | 对应场景 | 标签 |
|---------|----------|----------|------|
| T-CC-001 | 骨架提取测试 | SC-CC-001 | @smoke |
| T-CC-002 | Token 预算控制 | SC-CC-002 | @critical |
| T-CC-003 | 热点优先选择 | SC-CC-003 | @critical |
| T-CC-004 | 完整签名保留 | SC-CC-004 | @smoke |
| T-CC-005 | 增量压缩测试 | SC-CC-005 | @full |
| T-CC-006 | 多文件聚合测试 | SC-CC-006 | @critical |
| T-CC-007 | TypeScript 支持 | AC-006a | @critical |
| T-CC-008 | Python 支持（可选） | AC-006a | @full |
| T-CC-009 | 压缩率验证 | AC-006 | @critical |
| T-CC-010 | 语义保留度验证 | AC-006 | @full |

#### M6: 对话长期记忆（tests/long-term-memory.bats）

| Test ID | 测试用例 | 对应场景 | 标签 |
|---------|----------|----------|------|
| T-LTM-001 | 100 轮对话存储 | SC-LTM-001 | @critical |
| T-LTM-002 | 符号精确召回 | SC-LTM-002 | @smoke |
| T-LTM-003 | 滚动摘要生成 | SC-LTM-003 | @critical |
| T-LTM-004 | 跨会话记忆继承 | SC-LTM-004 | @critical |
| T-LTM-005 | 并发会话隔离 | SC-LTM-005 | @full |
| T-LTM-006 | 记忆清理测试 | SC-LTM-006 | @full |
| T-LTM-007 | SQLite 存储验证 | REQ-LTM-004 | @smoke |
| T-LTM-008 | 符号索引测试 | REQ-LTM-003 | @critical |
| T-LTM-009 | 自动符号提取 | REQ-LTM-006 | @critical |
| T-LTM-010 | 召回准确率验证 | AC-007a | @full |
| T-LTM-011 | 存储效率验证 | AC-007 | @full |

### 2.4 集成测试清单

| Test ID | 测试用例 | 覆盖模块 | 标签 |
|---------|----------|----------|------|
| T-INT-001 | LLM Provider + Graph RAG 集成 | M1 | @critical |
| T-INT-002 | Semantic Anomaly + Pattern Learner 集成 | M2 | @critical |
| T-INT-003 | Data Flow + Call Chain 集成 | M3 | @critical |
| T-INT-004 | Cancel + Daemon 集成 | M4 | @critical |
| T-INT-005 | Compressor + Hotspot 集成 | M5 | @critical |
| T-INT-006 | Memory + Intent Learner 集成 | M6 | @critical |
| T-INT-007 | Federation + Graph Store 集成 | M7 | @full |
| T-INT-008 | COD + Watch Mode 集成 | M8 | @full |
| T-INT-009 | Path Visualization + Mermaid 集成 | M9 | @full |
| T-INT-010 | Drift Detector + Snapshot 集成 | M10 | @full |
| T-INT-011 | 端到端工作流测试 | All | @full |
| T-INT-012 | 回归测试套件 | All | @full |

### 2.5 性能测试清单

| Test ID | 测试用例 | 指标 | 阈值 | 标签 |
|---------|----------|------|------|------|
| T-PERF-001 | Provider 切换延迟 | P95 | <100ms | @full |
| T-PERF-002 | 数据流单跳延迟 | P95 | <100ms | @full |
| T-PERF-003 | 数据流总时间 | Max | <500ms | @full |
| T-PERF-004 | 取消延迟（热启动） | P95 | <10ms | @critical |
| T-PERF-005 | 取消延迟（冷启动） | P95 | <50ms | @full |
| T-PERF-006 | 压缩率 | Min | >=50% | @critical |
| T-PERF-007 | 记忆召回延迟 | P95 | <100ms | @full |
| T-PERF-008 | 联邦查询延迟（缓存） | P95 | <500ms | @full |

---

## 3. Red 基线

> 测试必须先失败（Red），然后通过实现让测试通过（Green）

### 3.1 预期失败的测试

| 测试文件 | 预期失败原因 | 优先级 |
|----------|--------------|:------:|
| tests/llm-provider.bats | `llm-provider.sh` 脚本不存在 | P0 |
| tests/semantic-anomaly.bats | `semantic-anomaly.sh` 脚本不存在 | P0 |
| tests/data-flow-tracing.bats | `call-chain.sh --data-flow` 选项未实现 | P0 |
| tests/keystroke-cancel.bats | `daemon.sh` 信号机制未实现 | P1 |
| tests/context-compressor.bats | `context-compressor.sh` 脚本不存在 | P1 |
| tests/long-term-memory.bats | `intent-learner.sh` 记忆功能未实现 | P1 |
| tests/drift-detector.bats | `drift-detector.sh` 脚本不存在 | P2 |

### 3.2 Red 基线建立流程

```bash
# 1. 创建证据目录
mkdir -p dev-playbooks/changes/augment-final-10-percent/evidence/red-baseline

# 2. 运行测试并记录失败
bats tests/llm-provider.bats 2>&1 | tee evidence/red-baseline/llm-provider-$(date +%Y%m%d-%H%M%S).log
bats tests/semantic-anomaly.bats 2>&1 | tee evidence/red-baseline/semantic-anomaly-$(date +%Y%m%d-%H%M%S).log
bats tests/data-flow-tracing.bats 2>&1 | tee evidence/red-baseline/data-flow-$(date +%Y%m%d-%H%M%S).log

# 3. 生成基线摘要
echo "Red Baseline Summary - $(date)" > evidence/red-baseline/summary.md
```

### 3.3 预期的 Red 基线输出

```
llm-provider.bats
 - test_provider_interface_load FAILED (llm-provider.sh not found)
 - test_anthropic_provider FAILED (provider not implemented)
 - test_openai_provider FAILED (provider not implemented)
 - test_ollama_provider FAILED (provider not implemented)
 - test_mock_provider FAILED (mock not implemented)

semantic-anomaly.bats
 - test_missing_error_handler_detection FAILED (semantic-anomaly.sh not found)
 - test_inconsistent_api_detection FAILED (script not found)
 - test_naming_violation_detection FAILED (script not found)

data-flow-tracing.bats
 - test_forward_tracking FAILED (--data-flow option not recognized)
 - test_backward_tracking FAILED (--data-flow option not recognized)
 - test_cross_file_tracking FAILED (feature not implemented)
```

---

## 4. 边界条件检查清单

### 4.1 输入验证

- [ ] 空输入 / null 值处理
- [ ] 超长查询字符串（>10K 字符）
- [ ] 无效 JSON 格式的候选列表
- [ ] 不存在的文件路径
- [ ] 无效的 Provider 名称
- [ ] 缺失的 API Key

### 4.2 状态边界

- [ ] 空图谱（无符号）
- [ ] 单节点图谱
- [ ] 循环依赖检测
- [ ] 最大深度边界（5 跳）
- [ ] 最大并发请求（10 个）

### 4.3 并发与时序

- [ ] 并发取消同一请求
- [ ] 请求超时处理（30s）
- [ ] 竞态条件：同时写入记忆
- [ ] 文件监听事件防抖

### 4.4 错误处理

- [ ] 网络故障（LLM API 不可达）
- [ ] SQLite 数据库锁定
- [ ] 磁盘空间不足
- [ ] 无效的 AST（语法错误文件）

---

## 5. 测试优先级

| 优先级 | 定义 | 测试数量 | Red 基线要求 |
|:------:|------|:--------:|--------------|
| P0 | 阻塞发布，核心功能 | 24 | 必须在 Red 基线中失败 |
| P1 | 重要，应该覆盖 | 28 | 应该在 Red 基线中失败 |
| P2 | 锦上添花，可以后补 | 20 | Red 基线中可选 |

### 5.1 P0 测试（必须在 Red 基线中）

1. T-LPA-001: Provider 接口加载测试
2. T-LPA-002: Anthropic Provider 配置测试
3. T-LPA-003: OpenAI Provider 配置测试
4. T-LPA-005: Mock Provider 配置测试
5. T-LPA-009: 统一响应格式验证
6. T-SA-001: 缺失错误处理检测
7. T-SA-002: 不一致 API 调用检测
8. T-SA-009: 输出格式验证
9. T-DFT-001: 正向追踪测试
10. T-DFT-002: 反向追踪测试
11. T-DFT-009: 深度限制测试
12. T-DFT-010: 循环依赖检测
13. T-DFT-011: 输出格式验证

### 5.2 P1 测试（应该在 Red 基线中）

1. T-KC-001: 单进程取消延迟测试
2. T-KC-002: 子进程取消传播
3. T-KC-009: 取消状态码验证
4. T-CC-001: 骨架提取测试
5. T-CC-004: 完整签名保留
6. T-CC-007: TypeScript 支持
7. T-LTM-002: 符号精确召回
8. T-LTM-007: SQLite 存储验证

---

## 6. 手动验证检查清单

### MANUAL-001: LLM Provider 切换验证

- [ ] 步骤 1: 配置 `provider: anthropic`，运行 `llm_rerank` 查询
- [ ] 步骤 2: 修改配置为 `provider: openai`
- [ ] 步骤 3: 无需重启，再次运行查询
- [ ] 预期结果: 查询使用 OpenAI API，响应格式一致

### MANUAL-002: 数据流可视化验证

- [ ] 步骤 1: 选择一个跨 3 文件的变量传递路径
- [ ] 步骤 2: 运行 `call-chain.sh --data-flow <symbol>`
- [ ] 步骤 3: 检查输出的 Mermaid 图
- [ ] 预期结果: 图中清晰显示变量在各函数间的转换

### MANUAL-003: 长期记忆召回验证

- [ ] 步骤 1: 进行 20 轮关于特定函数的对话
- [ ] 步骤 2: 等待 1 小时后开始新会话
- [ ] 步骤 3: 询问 "之前讨论的 xxx 函数"
- [ ] 预期结果: 系统召回相关历史上下文

---

## 7. 追溯矩阵

| 需求文档 | 设计 (AC) | 测试文件 | 证据路径 |
|----------|-----------|----------|----------|
| proposal.md 5.1 | AC-001, AC-002 | tests/llm-provider.bats | evidence/red-baseline/llm-provider-*.log |
| proposal.md 5.2 | AC-003 | tests/semantic-anomaly.bats | evidence/red-baseline/semantic-anomaly-*.log |
| proposal.md 5.3 | AC-004, AC-004a | tests/data-flow-tracing.bats | evidence/red-baseline/data-flow-*.log |
| proposal.md 5.4 | AC-005, AC-005a | tests/keystroke-cancel.bats | evidence/red-baseline/keystroke-cancel-*.log |
| proposal.md 5.5 | AC-006, AC-006a | tests/context-compressor.bats | evidence/red-baseline/context-compressor-*.log |
| proposal.md 5.6 | AC-007, AC-007a | tests/long-term-memory.bats | evidence/red-baseline/long-term-memory-*.log |
| proposal.md 5.7 | AC-008, AC-008a, AC-008b | tests/federation-lite.bats | evidence/red-baseline/federation-*.log |
| proposal.md 5.8 | AC-009, AC-009a, AC-009b | tests/cod-visualizer.bats | evidence/red-baseline/cod-*.log |
| proposal.md 5.9 | AC-009c | tests/graph-store.bats | evidence/red-baseline/graph-store-*.log |
| proposal.md 5.10 | AC-010, AC-010a | tests/drift-detector.bats | evidence/red-baseline/drift-detector-*.log |

---

## 8. 测试环境要求

### 8.1 硬件要求

| 测试类型 | CPU | 内存 | 存储 |
|----------|-----|------|------|
| 单元测试 | 任意 | 4GB | 1GB |
| 集成测试 | 2+ 核心 | 8GB | 5GB |
| 性能测试 | M2/i7-10th | 16GB | 10GB |

### 8.2 软件依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| Bash | >=4.0 | 脚本执行 |
| BATS | >=1.9.0 | 测试框架 |
| SQLite | >=3.35 | 数据存储 |
| jq | >=1.6 | JSON 处理 |
| tree-sitter | >=0.20 | AST 解析 |

### 8.3 测试数据集

| 数据集 | 路径 | 用途 |
|--------|------|------|
| 中型项目 | tests/fixtures/medium-project/ | 性能基准 |
| 边界用例 | tests/fixtures/edge-cases/ | 边界测试 |
| Mock 响应 | tests/fixtures/mock-responses/ | LLM Mock |

---

## 9. 验收检查清单

- [ ] 所有 AC 都有对应测试
- [ ] Red 基线已建立
- [ ] P0 测试全部编写完成
- [ ] P1 测试全部编写完成
- [ ] 性能基准已定义
- [ ] 测试环境要求已文档化
- [ ] 边界条件检查清单已完成
- [ ] 追溯矩阵已建立

---

## 10. 测试文件创建清单

以下测试文件需要创建或更新：

| 文件路径 | 状态 | 优先级 |
|----------|:----:|:------:|
| tests/llm-provider.bats | 待创建 | P0 |
| tests/semantic-anomaly.bats | 待创建 | P0 |
| tests/data-flow-tracing.bats | 已存在，需更新 | P0 |
| tests/keystroke-cancel.bats | 待创建 | P1 |
| tests/context-compressor.bats | 待创建 | P1 |
| tests/long-term-memory.bats | 待创建 | P1 |
| tests/drift-detector.bats | 待创建 | P2 |

---

## Decision Log

| 日期 | 决策 | 理由 |
|------|------|------|
| 2026-01-17 | 使用 BATS 作为测试框架 | 与现有测试保持一致 |
| 2026-01-17 | 测试分层标签（@smoke/@critical/@full） | 支持快速反馈循环 |
| 2026-01-17 | Red 基线证据路径使用变更包目录 | 遵循 DevBooks 协议 |
