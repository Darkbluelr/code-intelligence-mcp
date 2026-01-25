# 验证计划：20260123-1206-add-auto-tool-orchestrator

> truth-root=`dev-playbooks/specs`；change-root=`dev-playbooks/changes`
>
> 目标：把 DoD 锚定到**可执行测试/可重复命令**与**证据落点**，并提供 `AC → (Spec/Scenario) → Test → Evidence` 的可追溯链路。

---

## 元信息

- Change ID：`20260123-1206-add-auto-tool-orchestrator`
- Status: Archived
- Archived At: 2026-01-24T09:16:55Z
- Archived By: devbooks-archiver（Codex CLI）
  - 生命周期：`Draft → Ready → Implementation Done → Verified → Done → Archived`
  - 权限：
    - `Ready/Verified`：Test Owner
    - `Implementation Done`：Coder
    - `Done`：Reviewer
    - `Archived`：Archiver
    - 约束：Coder 禁止修改 `Status`
- 关联（真理源）：
  - Proposal：`dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/proposal.md`
  - Design：`dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/design.md`
  - Specs：
    - `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/specs/auto-tool-orchestrator/spec.md`
    - `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/specs/structured-context-output/spec.md`
  - Tasks（仅供实现方执行，不作为测试真理源）：`dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/tasks.md`
- Test Owner：Codex CLI（`devbooks-test-owner`）
- Coder：Codex CLI（`devbooks-coder`）
- Red 基线证据目录：`dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/`
- Red 基线日志（最新）：`dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`
- Green 证据目录：`dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/`
- Green 基线日志（最新）：`dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log`
- 增量测试入口：`bats tests/auto-tools.bats`

---

## 测试策略（阶段 1：Red 基线）

### 测试类型分布（本变更）

| 类型 | 数量 | 用途 | 预期耗时 |
|---|---:|---|---|
| 契约测试（plan/dry-run，JSON schema） | 8 | 固化 Orchestrator 输出字段、退出码、[Limits] 文案锚点与确定性 | 秒级 |
| 静态闸门（入口层去编排化扫描） | 1 | 固化 AC-006/016：入口层不得直连工具 | 秒级 |
| 兼容性测试（augment wrapper） | 1 | 固化 AC-013：`augment-context-global.sh` 等价转发 | 秒级 |
| 融合测试（fixture 驱动） | 1 | 固化 AC-010/011：提示注入过滤 + 冲突判定 | 秒级 |

### 测试环境与依赖（最小集）

- 必需：`bats`、`bash`、`jq`、`rg`
- 约束：测试不依赖外部 `codex` 二进制（通过 plan/dry-run + fake codex 验证“不调用”）。

---

## A) 测试计划指令表（阶段 1：Red）

### 主线计划区

- [ ] TP1.1 Orchestrator schema v1.0 最小字段集（AC-001/014）
  - Test: `tests/auto-tools.bats` → `AC-001/014`
- [ ] TP1.2 plan/dry-run 确定性 + 不调用 codex（AC-002/003）
  - Test: `tests/auto-tools.bats` → `AC-002/003`
- [ ] TP1.3 env > config > default（AC-004/007）
  - Test: `tests/auto-tools.bats` → `AC-004/007`
- [ ] TP1.4 Tier-2 默认禁用且 config 绕过被忽略（AC-009/017）
  - Test: `tests/auto-tools.bats` → `AC-009/017`
- [ ] TP1.5 非代码意图空注入（AC-017）
  - Test: `tests/auto-tools.bats` → `AC-017`
- [ ] TP1.6 入口层去编排化静态扫描（AC-006/016）
  - Test: `tests/auto-tools.bats` → `AC-006/016`
- [ ] TP1.7 `augment-context-global.sh` 等价转发（AC-013）
  - Test: `tests/auto-tools.bats` → `AC-013`
- [ ] TP1.8 融合确定性 + 冲突判定 + 提示注入过滤（fixture）（AC-010/011）
  - Test: `tests/auto-tools.bats` → `AC-010/011`
- [ ] TP1.9 legacy 回退可审计（AC-018）
  - Test: `tests/auto-tools.bats` → `AC-018`

### 临时计划区

- 无

### 断点区

- 当前进度：已新增 `tests/auto-tools.bats` 与 fixtures，并准备建立 Red 基线日志。
- 下一步最短路径：运行增量测试并保存 Red 日志到 `evidence/red-baseline/`，然后将 Status 置为 `Ready`。

---

## B) 追溯矩阵（阶段 1：Red）

> 说明：Red 阶段只要求“测试已存在且可执行 + 失败证据已落盘”；Green 证据已落盘，待审计后勾选矩阵。

| AC | Spec/Scenario | Test / Command | Evidence（Red/Green） | 状态（证据） |
|---|---|---|---|---|
| AC-001 | REQ-ATO-001；SC-ATO-001 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-002 | REQ-ATO-003；SC-ATO-003 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-003 | REQ-ATO-003；SC-ATO-003 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-004 | REQ-ATO-002；SC-ATO-002 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-005 | proposal.md：AC-005 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-006 | REQ-ATO-004；SC-ATO-004 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-007 | REQ-ATO-005；SC-ATO-005 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-008 | REQ-ATO-006；SC-ATO-006 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-009 | REQ-ATO-002；SC-ATO-008 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-010 | proposal.md：AC-010 | `bats tests/auto-tools.bats`（fixture） | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-011 | proposal.md：AC-011 | `bats tests/auto-tools.bats`（fixture） | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-012 | REQ-ATO-006；SC-ATO-006 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-013 | REQ-ATO-007 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-014 | REQ-ATO-001 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-015 | proposal.md：AC-015 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-016 | REQ-ATO-007；SC-ATO-007 | `bats tests/auto-tools.bats`（static） | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-017 | REQ-ATO-008；SC-ATO-008 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |
| AC-018 | REQ-ATO-009；SC-ATO-009 | `bats tests/auto-tools.bats` | Red: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/red-baseline/bats-auto-tools-20260124-080149.log`<br>Green: `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/green-final/bats-auto-tools-20260124-062501.log` | Red 已留证；Green 已落盘（未审计） |

---

## C) 执行锚点（Deterministic Anchors）

### 1) 增量测试（阶段 1）

```bash
bats tests/auto-tools.bats
```

---

## D) MANUAL-* 清单（人工/混合验收）

### MANUAL-001 Claude Code Hook 运行态冒烟

步骤：
1) 在 Claude Code 中触发一次 UserPromptSubmit
2) 核对 hookSpecificOutput.additionalContext 来源于 fused_context.for_model.additional_context
3) 用户可见输出包含 [Auto Tools] 与 [Limits]

Pass/Fail 判据：步骤 2 与 3 同时满足

Evidence：验收时创建目录并保存截图或日志到 `dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/evidence/manual-acceptance/`

责任人/签字：Reviewer

---

## G) Value Stream and Metrics（价值流与度量）

- 目标价值信号：无
- 价值流瓶颈假设：无
- 交付与稳定性指标：无
- 观测窗口与触发点：无
- Evidence：无
