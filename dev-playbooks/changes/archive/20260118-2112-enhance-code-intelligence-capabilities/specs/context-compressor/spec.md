# 规格 Delta：上下文压缩增强

> **Change-ID**: `20260118-2112-enhance-code-intelligence-capabilities`
> **Capability**: context-compressor
> **Delta Type**: EXTEND
> **Version**: 2.0.0
> **Created**: 2026-01-19

---

## MODIFIED Requirements

### REQ-CC-001：压缩率目标（修改）

**原要求**：≥50% 压缩率

**新要求**：30-50% 压缩率，信息保留率 > 85%

| 指标 | 目标 | 验证方式 |
|------|------|----------|
| 压缩率 | 30-50% | 输出 token 数 / 输入 token 数 |
| 信息保留率 | > 85% | LLM 评分或人工评估 |
| 签名完整性 | 100% | 自动化测试验证 |

**Trace**: AC-001

---

### REQ-CC-009：压缩级别配置（新增）

系统应支持三种压缩级别：

```bash
context_compress --compress <low|medium|high> <files>
```

| 级别 | 压缩率 | 保留内容 | 适用场景 |
|------|--------|----------|----------|
| low | 30-40% | 完整骨架 + 关键注释 | 详细分析 |
| medium | 40-50% | 完整骨架 | 常规使用（默认） |
| high | 50-60% | 签名摘要 | Token 受限 |

**Trace**: AC-001

---

### REQ-CC-010：热点优先策略集成（新增）

系统应集成 `hotspot-analyzer.sh` 实现热点优先压缩：

```bash
# 热点权重计算
hotspot_weight = churn_count * 0.4 + recent_edits * 0.3 + coupling_score * 0.3

# 选择策略
1. 调用 hotspot-analyzer.sh 获取热点分数
2. 按热点分数降序排列文件
3. 在 Token 预算内优先保留高热点文件的完整骨架
4. 低热点文件使用更高压缩级别
```

**依赖**：`scripts/hotspot-analyzer.sh`（已存在）

**Trace**: AC-001

---

## ADDED Scenarios

### SC-CC-007：压缩级别选择

**Given**: 一个 1000 行的 TypeScript 文件
**When**: 运行 `context_compress --compress low src/service.ts`
**Then**:
- 压缩率 30-40%
- 保留完整骨架和关键注释
- 信息保留率 > 90%

**Trace**: AC-001

---

### SC-CC-008：热点优先压缩

**Given**:
- 文件 A：高热点（hotspot_score = 0.85）
- 文件 B：低热点（hotspot_score = 0.30）
- Token 预算 3000

**When**: 运行 `context_compress --budget 3000 --hotspot src/`
**Then**:
- 文件 A 使用 low 压缩级别（保留更多内容）
- 文件 B 使用 high 压缩级别（仅保留签名）
- 总 Token 不超过 3000

**Trace**: AC-001

---

### SC-CC-009：信息保留率验证

**Given**: 压缩后的上下文
**When**: 使用 LLM 评估信息保留率

- LLM 能正确回答关于代码结构的问题
- 信息保留率评分 > 85%

**Trace**: AC-001

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-CC-001（修改） | SC-CC-001, SC-CC-002, SC-CC-007, SC-CC-009 | AC-001 |
| REQ-CC-009（新增） | SC-CC-007 | AC-001 |
| REQ-CC-010（新增） | SC-CC-008 | AC-001 |

---

## 与现有规格的关系

**扩展自**：`dev-playbooks/specs/context-compressor/spec.md` v1.0.0

**主要变更**：
1. 调整压缩率目标（50% → 30-50%）
2. 新增信息保留率指标（> 85%）
3. 新增压缩级别配置（low/medium/high）
4. 新增热点优先策略集成

**兼容性**：向后兼容，默认行为保持不变
