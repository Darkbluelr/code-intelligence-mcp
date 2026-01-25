# 设计文档：算法优化对齐 (Algorithm Optimization Parity)

> **Change ID**: algorithm-optimization-parity
> **Status**: Draft
> **版本**: 1.0
> **创建日期**: 2025-01-17

## 1. What（做什么）

本次变更对 Code Intelligence MCP 的核心算法模块进行性能优化和质量提升，实现与竞品 Augment（及其预设的目标指标）对齐。主要覆盖以下 11 个优化项：

### 1.1 优化项清单

| 优化项 | 目标模块 | 优化类型 | 提案依据 |
|--------|----------|----------|----------|
| ALG-001 | graph-rag.sh | 优先级排序算法 | MP4.2 |
| ALG-002 | graph-rag.sh | 贪婪选择策略 | MP4.4 |
| ALG-003 | impact-analyzer.sh | BFS + 置信度衰减 | M2 |
| ALG-004 | intent-learner.sh | 偏好分数计算 | AC-F06 |
| ALG-005 | intent-learner.sh | 对话连续性加权 | AC-G04 |
| ALG-006 | federation-lite.sh | 虚拟边置信度 | AC-F05 |
| ALG-007 | pattern-learner.sh | 频率+时间衰减 | AC-003 |
| ALG-008 | hotspot-analyzer.sh | 复杂度加权热点 | AC-001 |
| ALG-009 | boundary-detector.sh | 快速路径匹配 | AC-004 |
| ALG-010 | cache-manager.sh | LRU + 版本校验 | AC-F08 |
| ALG-011 | common.sh | 意图四分类 | AC-012 |

### 1.2 非目标（Out of Scope）

- 新增功能模块
- UI/UX 变更
- 外部 API 契约变更（内部实现优化，对外接口保持兼容）

---

## 2. Constraints（约束条件）

### 2.1 性能约束

| 约束 ID | 约束描述 | 度量标准 |
|---------|----------|----------|
| CON-PERF-001 | Graph-RAG 端到端延迟 | P95 < 3s |
| CON-PERF-002 | 影响分析 5 跳遍历 | < 500ms |
| CON-PERF-003 | 意图分类响应 | < 50ms |
| CON-PERF-004 | 缓存命中时延迟 | < 100ms |

### 2.2 质量约束

| 约束 ID | 约束描述 | 度量标准 |
|---------|----------|----------|
| CON-QUAL-001 | 相关性评分准确度 | 10 预设查询 ≥ 70% |
| CON-QUAL-002 | 影响分析置信度正确性 | 5 跳内衰减公式正确 |
| CON-QUAL-003 | 意图分类准确率 | ≥ 85% |

### 2.3 兼容性约束

| 约束 ID | 约束描述 |
|---------|----------|
| CON-COMPAT-001 | 对外 JSON Schema 保持不变 |
| CON-COMPAT-002 | CLI 参数向后兼容 |
| CON-COMPAT-003 | 功能开关默认值不改变 |

### 2.4 技术栈约束

| 约束 ID | 约束描述 |
|---------|----------|
| CON-TECH-001 | 使用 Bash + jq 实现，不引入新运行时依赖 |
| CON-TECH-002 | SQLite 作为图存储，WAL 模式 |
| CON-TECH-003 | 仅依赖 POSIX 标准工具和已有依赖 |

---

## 3. 验收标准（Acceptance Criteria）

### 3.1 ALG-001: 优先级排序算法

**AC-001**: Graph-RAG 优先级计算
- **Given**: 候选列表包含 relevance、hotspot、distance 字段
- **When**: 调用 `calculate_priority()` 函数
- **Then**: 返回 `Priority = relevance × 0.4 + hotspot × 0.3 + (1/distance) × 0.3`
- **验证方法**: 单元测试 + 数值断言

**AC-002**: 权重可配置
- **Given**: `config/features.yaml` 中定义 `smart_pruning.priority_weights`
- **When**: 计算优先级
- **Then**: 使用配置文件中的权重值
- **验证方法**: 配置变更后重新计算验证

### 3.2 ALG-002: 贪婪选择策略

**AC-003**: Token 预算裁剪
- **Given**: 候选列表按优先级排序，Token 预算为 N
- **When**: 调用 `trim_by_budget()` 函数
- **Then**: 贪婪选择不超过预算的最高优先级候选
- **验证方法**: 边界测试（预算刚好、预算不足、单片段超预算）

**AC-004**: Token 估算准确性
- **Given**: 任意文本内容
- **When**: 调用 `estimate_tokens()` 函数
- **Then**: 估算值误差 < 20%（使用 char_count/4 + 10% 裕量）
- **验证方法**: 与已知 token 数对比

### 3.3 ALG-003: BFS + 置信度衰减

**AC-005**: 影响分析置信度计算
- **Given**: 起始符号 S，衰减系数 0.8，最大深度 5
- **When**: 调用 `bfs_impact_analysis()` 函数
- **Then**:
  - 深度 1 置信度 = 0.8
  - 深度 2 置信度 = 0.64
  - 深度 3 置信度 = 0.512
  - 深度 4 置信度 = 0.4096
  - 深度 5 置信度 = 0.328
- **验证方法**: 数值断言

**AC-006**: 阈值过滤
- **Given**: 阈值 threshold = 0.1
- **When**: 遍历深度超过使置信度 < 0.1
- **Then**: 停止遍历该分支
- **验证方法**: 结果不包含低于阈值的节点

### 3.4 ALG-004: 偏好分数计算

**AC-007**: 偏好公式正确性
- **Given**: 符号 S 被查询 N 次，操作权重 W，最后查询距今 D 天
- **When**: 调用 `cmd_get_preferences()` 函数
- **Then**: `Preference = sum(W × (1 / (1 + D)))`
- **验证方法**: 单元测试 + 数值断言

**AC-008**: 操作权重
- **Given**: 操作类型 view/edit/ignore
- **When**: 计算权重
- **Then**: view=1.0, edit=2.0, ignore=0.5
- **验证方法**: 单元测试

### 3.5 ALG-005: 对话连续性加权

**AC-009**: 累积焦点加权
- **Given**: 符号在 `accumulated_focus` 中
- **When**: 应用连续性加权
- **Then**: 分数 +0.2
- **验证方法**: 对比加权前后分数

**AC-010**: 近期焦点加权
- **Given**: 符号在最近 3 轮 `focus_symbols` 中
- **When**: 应用连续性加权
- **Then**: 分数 +0.3
- **验证方法**: 对比加权前后分数

**AC-011**: 同文件加权
- **Given**: 符号与最近查询同文件
- **When**: 应用连续性加权
- **Then**: 分数 +0.1
- **验证方法**: 对比加权前后分数

**AC-012**: 加权上限
- **Given**: 原始分数为 S，所有加权条件满足
- **When**: 计算总加权
- **Then**: 加权不超过 S × 0.5
- **验证方法**: 边界测试

### 3.6 ALG-006: 虚拟边置信度

**AC-013**: 置信度计算
- **Given**: 跨仓库符号引用
- **When**: 计算虚拟边置信度
- **Then**: 基于名称相似度 + 路径相似度 + 版本兼容性计算
- **验证方法**: 单元测试

**AC-014**: 置信度阈值
- **Given**: 配置 `confidence_threshold: 0.5`
- **When**: 计算得出置信度 < 0.5
- **Then**: 不生成虚拟边
- **验证方法**: 边界测试

### 3.7 ALG-007: 频率+时间衰减

**AC-015**: 模式分数计算
- **Given**: 模式 P 出现 N 次，最后出现距今 D 天
- **When**: 计算模式分数
- **Then**: `Score = frequency × (1 / (1 + D/30))`
- **验证方法**: 数值断言

**AC-016**: 最小频率阈值
- **Given**: 配置 `min_frequency: 3`
- **When**: 模式出现次数 < 3
- **Then**: 不记录该模式
- **验证方法**: 边界测试

### 3.8 ALG-008: 复杂度加权热点

**AC-017**: 热点分数公式
- **Given**: 文件 F，修改次数 C，圈复杂度 M
- **When**: 计算热点分数
- **Then**: `Score = C × (1 + log(M))`（复杂度启用时）
- **验证方法**: 数值断言

**AC-018**: 功能开关
- **Given**: `features.complexity_weighted_hotspot: false`
- **When**: 计算热点分数
- **Then**: `Score = C`（不使用复杂度加权）
- **验证方法**: 配置切换测试

### 3.9 ALG-009: 快速路径匹配

**AC-019**: 库代码检测
- **Given**: 文件路径为 `node_modules/...` 或 `vendor/...`
- **When**: 调用 `is_library_code()` 函数
- **Then**: 返回 0（是库代码）
- **验证方法**: 边界测试

**AC-020**: 快速路径优先
- **Given**: 路径匹配快速规则
- **When**: 检测边界
- **Then**: 不调用完整边界检测器（性能优化）
- **验证方法**: 性能测试

### 3.10 ALG-010: LRU + 版本校验

**AC-021**: 缓存失效
- **Given**: 文件 F 的缓存条目，F 已被修改
- **When**: 获取缓存
- **Then**: 返回缓存未命中
- **验证方法**: 修改文件后验证缓存失效

**AC-022**: LRU 淘汰
- **Given**: 缓存已满
- **When**: 添加新条目
- **Then**: 淘汰最久未使用的条目
- **验证方法**: 容量边界测试

### 3.11 ALG-011: 意图四分类

**AC-023**: 分类优先级
- **Given**: 用户输入包含多种意图关键词
- **When**: 调用 `get_intent_type()` 函数
- **Then**: 按 debug > refactor > docs > feature 优先级返回
- **验证方法**: 优先级边界测试

**AC-024**: 分类准确率
- **Given**: 10 个预设测试用例
- **When**: 分类
- **Then**: 准确率 ≥ 85%
- **验证方法**: 回归测试

---

## 4. 技术决策

### 4.1 算法选择

| 决策 | 选项 | 选择 | 理由 |
|------|------|------|------|
| 图遍历 | DFS / BFS | BFS | 层级置信度衰减需要按深度处理 |
| 裁剪策略 | 动态规划 / 贪婪 | 贪婪 | 性能优先，O(n) vs O(n²) |
| Token 估算 | Tiktoken / 字符估算 | 字符估算 | 避免引入新依赖 |
| 缓存策略 | LRU / LFU | LRU | 实现简单，符合访问模式 |

### 4.2 数据结构

```
# 优先级排序后的候选结构
{
  "file_path": "src/auth.ts",
  "symbol_id": "src/auth.ts::handleAuth",
  "relevance_score": 0.85,
  "hotspot": 0.6,
  "distance": 1,
  "priority": 0.71,      // 计算得出
  "tokens": 150          // 估算得出
}

# 影响分析结果结构
{
  "id": "sym:func:handleAuth",
  "symbol": "handleAuth",
  "kind": "function",
  "file_path": "src/auth.ts",
  "depth": 2,
  "confidence": 0.64     // 0.8 ^ 2
}
```

---

## 5. Documentation Impact（文档影响）

### 需要更新的文档

| 文档 | 更新原因 | 优先级 |
|------|----------|--------|
| README.md | 无需更新（内部优化） | - |
| docs/Augment.md | 更新对齐状态表 | P1 |
| CHANGELOG.md | 记录本次优化 | P0 |

### 无需更新的文档

- [x] 本次变更为内部算法优化，不影响用户可见功能
- [x] CLI 接口保持不变
- [x] JSON Schema 保持不变

### 文档更新检查清单

- [x] 新增脚本/命令已在使用文档中说明 - 无新增
- [x] 新增配置项已在配置文档中说明 - 无新增
- [ ] CHANGELOG.md 需记录性能改进

---

## 6. Architecture Impact（架构影响）

### 无架构变更

- [x] 本次变更不影响模块边界、依赖方向或组件结构
- 原因说明：所有优化均在现有模块内部进行，不新增模块、不改变模块间依赖关系

### 影响的组件

本次优化涉及以下 Component 的内部实现，但不改变其对外接口：

| Component | 优化内容 |
|-----------|----------|
| graph-rag.sh | 优先级计算、贪婪选择 |
| impact-analyzer.sh | BFS 遍历、置信度衰减 |
| intent-learner.sh | 偏好计算、连续性加权 |
| federation-lite.sh | 虚拟边置信度 |
| pattern-learner.sh | 模式分数计算 |
| hotspot-analyzer.sh | 复杂度加权 |
| boundary-detector.sh | 快速路径匹配 |
| cache-manager.sh | LRU 淘汰策略 |
| common.sh | 意图分类函数 |

### 分层约束影响

- [x] 本次变更遵守现有分层约束
- Shell 脚本层保持独立
- 不引入对 TypeScript 层的新依赖

---

## 7. 回滚策略

### 7.1 功能开关回滚

所有优化均可通过 `config/features.yaml` 禁用：

```yaml
features:
  smart_pruning:
    enabled: false
  impact_analyzer:
    enabled: false
  intent_learner:
    enabled: false
  # ...
```

### 7.2 代码回滚

- 通过 Git revert 回滚提交
- 回滚不影响数据文件（缓存、历史记录）

---

## 8. 风险评估

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| 性能回归 | 低 | 中 | 性能基准测试 + CI 门禁 |
| 兼容性问题 | 低 | 高 | 完整回归测试 |
| 算法错误 | 中 | 中 | 数值断言 + 边界测试 |

---

## 9. 测试策略

### 9.1 单元测试

- 每个算法函数独立测试
- 数值断言验证公式正确性
- 边界条件测试

### 9.2 集成测试

- 端到端工作流测试
- 性能基准测试（P95 延迟）

### 9.3 回归测试

- 现有测试套件全部通过
- 10 个预设查询相关性 ≥ 70%

---

## 附录 A: 算法伪代码

### A.1 优先级计算

```python
def calculate_priority(candidate):
    relevance = candidate.get('relevance_score', 0)
    hotspot = candidate.get('hotspot', 0)
    distance = max(candidate.get('distance', 1), 1)

    # 权重从配置获取
    w_r = config.priority_weights.relevance  # 0.4
    w_h = config.priority_weights.hotspot    # 0.3
    w_d = config.priority_weights.distance   # 0.3

    return relevance * w_r + hotspot * w_h + (1 / distance) * w_d
```

### A.2 贪婪选择

```python
def trim_by_budget(candidates, budget):
    result = []
    total_tokens = 0

    for c in sorted(candidates, key=lambda x: -x['priority']):
        tokens = estimate_tokens(c)
        if tokens > budget:
            continue  # 单片段超预算，跳过
        if total_tokens + tokens > budget:
            break     # 累计超预算，停止
        result.append(c)
        total_tokens += tokens

    return result
```

### A.3 BFS 置信度衰减

```python
def bfs_impact_analysis(start, max_depth, decay, threshold):
    queue = [(start, 0, 1.0)]  # (node, depth, impact)
    visited = set()
    result = []

    while queue:
        node, depth, impact = queue.pop(0)
        if node in visited:
            continue
        visited.add(node)

        if node != start and impact >= threshold:
            result.append({
                'id': node.id,
                'depth': depth,
                'confidence': round(impact, 3)
            })

        if depth < max_depth:
            new_impact = impact * decay
            if new_impact >= threshold:
                for neighbor in get_downstream(node):
                    queue.append((neighbor, depth + 1, new_impact))

    return sorted(result, key=lambda x: -x['confidence'])
```

---

## 10. 契约计划（Contract）

### 10.1 契约类型

本次变更**不涉及外部 API 契约变更**，所有优化均为内部实现。

| 契约类型 | 是否变更 | 说明 |
|----------|----------|------|
| CLI 接口 | 否 | 参数保持向后兼容 |
| JSON Schema | 否 | 输出格式不变 |
| MCP Tool Schema | 否 | 工具定义不变 |
| 配置文件格式 | 否 | 新增配置项均有默认值 |

### 10.2 内部行为契约

虽然外部接口不变，但内部算法行为有明确契约，通过单元测试验证。

| 契约 ID | 模块 | 契约描述 |
|---------|------|----------|
| BC-001 | graph-rag.sh | 优先级公式：`P = r×0.4 + h×0.3 + (1/d)×0.3` |
| BC-002 | graph-rag.sh | 贪婪选择不超过 Token 预算 |
| BC-003 | impact-analyzer.sh | 置信度衰减：`c = base × (decay ^ depth)` |
| BC-004 | intent-learner.sh | 偏好公式：`P = Σ(w × 1/(1+d))` |
| BC-005 | intent-learner.sh | 加权上限：`boost ≤ score × 0.5` |
| BC-006 | federation-lite.sh | 虚拟边阈值：`confidence ≥ 0.5` |
| BC-007 | pattern-learner.sh | 模式分数：`S = freq × 1/(1+d/30)` |
| BC-008 | hotspot-analyzer.sh | 热点公式：`S = C × (1 + log(M))` |
| BC-009 | boundary-detector.sh | 快速路径匹配优先 |
| BC-010 | cache-manager.sh | LRU 淘汰 + 版本校验 |
| BC-011 | common.sh | 意图优先级：debug > refactor > docs > feature |

### 10.3 兼容策略

**向后兼容**: 是

- 所有 CLI 参数保持不变
- 所有输出 JSON Schema 保持不变
- 新增配置项均有向后兼容的默认值

**弃用策略**: 无

**迁移方案**: 无需迁移

### 10.4 Contract Test IDs 汇总

详见各规格文档的 Contract Test IDs 章节。

**总计**: 57 个 Contract Tests

| 规格 | Test 数量 |
|------|-----------|
| priority-sorting | 4 |
| greedy-selection | 5 |
| impact-analysis | 5 |
| preference-scoring | 5 |
| context-weighting | 6 |
| virtual-edge | 5 |
| pattern-decay | 5 |
| hotspot-weighting | 6 |
| boundary-detection | 6 |
| cache-lru | 6 |
| intent-classification | 10 |

---

## 规格文件索引

| 能力 | 规格路径 |
|------|----------|
| ALG-001 优先级排序 | `specs/priority-sorting/spec.md` |
| ALG-002 贪婪选择 | `specs/greedy-selection/spec.md` |
| ALG-003 影响分析 | `specs/impact-analysis/spec.md` |
| ALG-004 偏好计算 | `specs/preference-scoring/spec.md` |
| ALG-005 连续性加权 | `specs/context-weighting/spec.md` |
| ALG-006 虚拟边置信度 | `specs/virtual-edge/spec.md` |
| ALG-007 模式衰减 | `specs/pattern-decay/spec.md` |
| ALG-008 热点加权 | `specs/hotspot-weighting/spec.md` |
| ALG-009 边界检测 | `specs/boundary-detection/spec.md` |
| ALG-010 缓存 LRU | `specs/cache-lru/spec.md` |
| ALG-011 意图分类 | `specs/intent-classification/spec.md` |

