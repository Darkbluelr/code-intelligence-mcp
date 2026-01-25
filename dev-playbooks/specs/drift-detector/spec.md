# 规格：架构漂移检测

> **Capability**: drift-detector
> **Version**: 1.0.0
> **Status**: Active
> **Created**: 2026-01-19
> **Last Referenced By**: 20260118-2112-enhance-code-intelligence-capabilities
> **Last Verified**: 2026-01-22
> **Health**: active

---

## Requirements（需求）

### REQ-DD-001：架构快照生成

系统应支持生成当前架构快照：

```bash
drift-detector.sh --snapshot
```

**快照内容**：
- 模块列表（基于目录结构）
- 组件列表（基于 C4 架构图）
- 依赖关系（基于 import/require）
- 边界定义（基于 boundary-detector.sh）

**快照存储**：`.devbooks/snapshots/architecture-<timestamp>.json`

**Trace**: AC-002

---

### REQ-DD-002：架构 Diff 算法

系统应实现架构快照对比算法：

```bash
drift-detector.sh --compare <snapshot1> <snapshot2>
```

**检测项**：
| 检测类型 | 说明 | 权重 |
|----------|------|------|
| 新增未记录的组件 | 代码中存在但 C4 图中不存在 | 30% |
| 删除已记录的组件 | C4 图中存在但代码中不存在 | 20% |
| 修改组件职责 | 组件依赖关系发生变化 | 25% |
| 新增未记录的依赖 | 跨模块依赖未在 C4 图中声明 | 25% |

**Trace**: AC-002

---

### REQ-DD-003：漂移评分计算

系统应计算漂移评分（0-100）：

```
drift_score = Σ (detected_changes * weight) / total_components * 100

其中：
- detected_changes: 检测到的变更数量
- weight: 变更类型权重（见 REQ-DD-002）
- total_components: 总组件数
```

**阈值**：
- 0-30：正常（绿色）
- 31-50：警告（黄色）
- 51-100：严重（红色）

**Trace**: AC-002

---

### REQ-DD-004：漂移报告生成

系统应生成 Markdown 格式的漂移报告：

```bash
drift-detector.sh --report
```

**报告内容**：
1. 漂移评分和等级
2. 检测到的变更列表（按类型分组）
3. 建议的修复措施
4. C4 架构图更新建议

**报告存储**：`evidence/drift-detection-report.md`

**Trace**: AC-002

---

### REQ-DD-005：首次运行处理

系统应正确处理首次运行（无历史快照）：

```bash
# 首次运行
drift-detector.sh --snapshot
# 输出：Generated initial snapshot, drift_score = 0
```

**行为**：
- 生成初始快照
- 漂移评分 = 0
- 不输出告警

**Trace**: AC-002

---

## Scenarios（场景）

### SC-DD-001：生成初始快照

**Given**: 项目目录下不存在架构快照
**When**: 运行 `drift-detector.sh --snapshot`
**Then**:
- 生成快照文件 `.devbooks/snapshots/architecture-<timestamp>.json`
- 快照包含所有模块、组件、依赖关系
- 输出成功消息

**Trace**: AC-002

---

### SC-DD-002：检测新增组件

**Given**:
- 历史快照包含 10 个组件
- 当前代码包含 12 个组件（新增 2 个）
- 新增组件未在 C4 架构图中声明

**When**: 运行 `drift-detector.sh --compare`
**Then**:
- 检测到 2 个新增未记录的组件
- 漂移评分 = (2 * 0.3) / 12 * 100 = 5
- 输出警告：`Detected 2 undocumented components`

**Trace**: AC-002

---

### SC-DD-003：检测依赖变更

**Given**:
- 模块 A 原本依赖模块 B
- 当前代码中模块 A 新增依赖模块 C
- 新依赖未在 C4 架构图中声明

**When**: 运行 `drift-detector.sh --compare`
**Then**:
- 检测到 1 个新增未记录的依赖
- 漂移评分增加
- 输出建议：`Update C4 diagram to include A -> C dependency`

**Trace**: AC-002

---

### SC-DD-004：漂移评分超过阈值

**Given**: 漂移评分 = 55（严重）
**When**: 运行 `drift-detector.sh --report`
**Then**:
- 输出红色告警
- 生成详细漂移报告
- 报告包含所有检测到的变更和修复建议

**Trace**: AC-002

---

### SC-DD-005：无变更场景

**Given**: 当前架构与历史快照完全一致
**When**: 运行 `drift-detector.sh --compare`
**Then**:
- 漂移评分 = 0
- 输出：`No architecture drift detected`
- 不生成告警

**Trace**: AC-002

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-DD-001 | SC-DD-001 | AC-002 |
| REQ-DD-002 | SC-DD-002, SC-DD-003 | AC-002 |
| REQ-DD-003 | SC-DD-002, SC-DD-004, SC-DD-005 | AC-002 |
| REQ-DD-004 | SC-DD-004 | AC-002 |
| REQ-DD-005 | SC-DD-001 | AC-002 |

---

## 依赖关系

**依赖的现有能力**：
- `graph-store.sh`：查询模块依赖关系
- `boundary-detector.sh`：检测模块边界
- C4 架构图：`dev-playbooks/specs/architecture/c4.md`

**被依赖的能力**：无

---

## 非功能需求

### 性能基准

| 场景 | 指标 | 阈值 |
|------|------|------|
| 快照生成（100 组件） | 延迟 | < 2s |
| 快照对比 | 延迟 | < 500ms |
| 报告生成 | 延迟 | < 1s |

### 准确性要求

| 检查项 | 要求 |
|--------|------|
| 组件检测准确率 | > 90% |
| 依赖检测准确率 | > 85% |
| 误报率 | < 10% |
