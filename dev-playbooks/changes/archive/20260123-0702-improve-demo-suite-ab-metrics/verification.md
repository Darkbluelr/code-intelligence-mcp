# 验证计划：20260123-0702-improve-demo-suite-ab-metrics

> truth-root=`dev-playbooks/specs`；change-root=`dev-playbooks/changes`
>
> 目标：把 DoD 锚定到**可执行测试/可重复命令**与**证据落点**，并提供 `AC → REQ/SC → CT/Test → Evidence` 的可追溯链路。

---

## 元信息

- Change ID：`20260123-0702-improve-demo-suite-ab-metrics`
- Status: Archived
- 状态：`Archived`
  - 状态说明：保持 `Archived`（已归档）。本次仅补齐测试与 Green 证据，不回滚归档状态。
  - 备注：因反归档修复后重新采证。
  - 补充说明：因反归档修复后重新采证，Green 证据已更新。
  - 生命周期：`Draft → Ready → Implementation Done → Verified → Done → Archived`
  - 权限：
    - `Ready/Verified`：Test Owner
    - `Implementation Done`：Coder
    - `Done`：Reviewer
    - `Archived`：Archiver
    - 约束：Coder 禁止修改 `Status`
- 关联（真理源）：
  - Proposal：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/proposal.md`
  - Design：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/design.md`
  - Spec：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/specs/demo-suite/spec.md`
  - Tasks（仅供实现方执行，不作为测试真理源）：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/tasks.md`
- 维护者：Test Owner（Codex CLI 子代理）
- 更新时间：`2026-01-23`
- Archived At：`2026-01-24T05:55:33Z`
- Archived By：`devbooks-archiver`
- Test Owner（独立对话）：Codex CLI（`devbooks-test-owner`）
- Coder（独立对话）：Codex CLI（`devbooks-coder`）
- Red 基线证据目录：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/red-baseline/`
- Red 基线日志（最新）：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/red-baseline/bats-demo-suite-20260123-124920.log`
- Green 证据目录：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/green-final/`
- Green 证据日志（最新）：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/green-final/bats-demo-suite-20260124-131213.log`
- 增量测试入口：`bats tests/demo-suite.bats`

---

## 测试策略（阶段 1：Red 基线）

### 测试类型分布（本变更）

| 类型 | 数量 | 用途 | 预期耗时 |
|---|---:|---|---|
| 契约测试（schema/paths，fixture 驱动） | 12 | 固化 `metrics.json`/`compare.json`/`scorecard.json` 的 `jq -e` 契约与稳定路径布局 | 秒级 |
| 静态闸门（ShellCheck） | 1 | 固化 AC-008 的“仅 demo/ 范围”质量闸门 | 秒级 |
| Smoke（入口存在性） | 1 | 固化单入口脚本 `demo/demo-suite.sh` 的存在性/可执行性（当前预期失败以建立 Red） | 秒级 |

### 测试环境与依赖（最小集）

- 必需：`bats`、`bash`、`jq`
- 必需（AC-008）：`shellcheck`
- 约束：测试不修改 `src/`、`scripts/`、`hooks/`；仅使用临时目录写入 fixture

---

========================
A) 测试计划指令表
========================

### 主线计划区 (Main Plan Area)

- [ ] TP1.1 单入口脚本存在性（P0）
  - Why：把“单入口”作为可执行锚点，避免后续产物/对比/归档无法统一编排。
  - Acceptance Criteria：AC-001（入口要求）
  - Test Type：`smoke`
  - Non-goals：不在本阶段运行 demo-suite（避免依赖未实现与环境漂移）。
  - Candidate Anchors：`tests/demo-suite.bats` → `T-DS-ENTRYPOINT-001`

- [ ] TP1.2 单次运行标准产物契约（fixture + jq）
  - Why：固化 `metrics.json` 与 `report.md` 的最小契约与路径布局，支持后续 compare 与归档。
  - Acceptance Criteria：AC-001；REQ-DS-001；SC-DS-001
  - Test Type：`contract`
  - Non-goals：不覆盖“真实运行时耗时/性能数值”；仅闭合最小 schema/路径契约。
  - Candidate Anchors：`CT-DS-001`、`CT-DS-002`

- [ ] TP1.3 写入边界证据闭合（fixture + 文件断言）
  - Why：固化 out-dir 唯一最终落盘边界的可审计证据文件与默认 `/tmp` 策略。
  - Acceptance Criteria：AC-002；REQ-DS-002；SC-DS-002
  - Test Type：`contract`
  - Non-goals：不在本阶段对真实仓库写入做扫描（等 demo-suite 实现后再做集成覆盖）。
  - Candidate Anchors：`CT-DS-003`、`CT-DS-004`、`CT-DS-005`

- [ ] TP1.4 版本 A/B 的最小闭合（fixture + jq）
  - Why：固化 `ab-version/*` 的目录布局与 compare schema 闭合锚点。
  - Acceptance Criteria：AC-003、AC-005；REQ-DS-003；SC-DS-003
  - Test Type：`contract`
  - Non-goals：不验证“真实 ref 隔离策略/依赖安装/缓存污染”等实现细节；只锁定产物契约。
  - Candidate Anchors：`CT-DS-006`、`CT-DS-007`

- [ ] TP1.5 配置 A/B 的最小闭合（fixture + jq + reason code）
  - Why：固化 `ab-config/*` 的 compare schema 与“变量漂移即不可下结论”的原因码锚点。
  - Acceptance Criteria：AC-004、AC-005；REQ-DS-004；SC-DS-004
  - Test Type：`contract`
  - Non-goals：不对“漂移检测算法”做实现层断言；只断言产物中可审计结论与原因码落点。
  - Candidate Anchors：`CT-DS-008`、`CT-DS-009`

- [ ] TP1.6 双场景降级语义（fixture）
  - Why：固化 `missing_fields[] + reasons[] + null` 的降级表示法，避免“假结论”。
  - Acceptance Criteria：AC-006；REQ-DS-005；SC-DS-005、SC-DS-006
  - Test Type：`contract`
  - Non-goals：不保证依赖缺失一定发生；通过 fixture 固化输出契约。
  - Candidate Anchors：`CT-DS-010`、`CT-DS-011`

- [ ] TP1.7 AI 双代理 scorecard 最小契约（fixture + jq）
  - Why：固化 `scorecard.json` 最小字段与可执行校验命令，确保可审计/可 compare。
  - Acceptance Criteria：AC-007；REQ-DS-006；SC-DS-007
  - Test Type：`contract`
  - Non-goals：不评估 AI 结论质量；只验证结构化产物契约；`ai_ab.status="skipped"` 时不要求 scorecard。
  - Candidate Anchors：`CT-DS-012`

- [ ] TP1.8 质量闸门可复现（仅 demo/）（ShellCheck）
  - Why：固化闸门范围，避免把历史债务（`scripts/`/`hooks/`）误纳入本变更 DoD。
  - Acceptance Criteria：AC-008
  - Test Type：`static`
  - Non-goals：不对 `scripts/`、`hooks/` 做 ShellCheck（范围红线）。
  - Candidate Anchors：`GATE-DS-001`

### 临时计划区 (Temporary Plan Area)

- 无

### 断点区 (Context Switch Breakpoint Area)

- 上次进度：已落盘 `verification.md`，已新增 `tests/demo-suite.bats`，并建立 Red 基线（失败点：入口脚本缺失）。
- 当前阻塞：无（等待 Coder 实现 `demo/demo-suite.sh` 与 compare/产物落盘）。
- 下一步最短路径：Coder 按 `tests/demo-suite.bats` 的失败用例实现，使其转绿。

---

========================
B) 追溯矩阵（Traceability Matrix）
========================

> 说明：本阶段（Red）追溯链要求至少闭合到 `evidence/red-baseline/`；Green/Verified 阶段再补充 `evidence/green-final/`。

| AC | Requirement/Scenario | Test IDs / Commands | Evidence（Red） | 状态（Red） |
|---|---|---|---|---|
| AC-001 | REQ-DS-001；SC-DS-001 | `T-DS-ENTRYPOINT-001`、`CT-DS-001`、`CT-DS-002` | `evidence/red-baseline/bats-demo-suite-20260123-124920.log` | 已建立 |
| AC-002 | REQ-DS-002；SC-DS-002 | `CT-DS-003`、`CT-DS-004`、`CT-DS-005` | `evidence/red-baseline/bats-demo-suite-20260123-124920.log` | 已建立 |
| AC-003 | REQ-DS-003；SC-DS-003 | `CT-DS-006`、`CT-DS-007` | `evidence/red-baseline/bats-demo-suite-20260123-124920.log` | 已建立 |
| AC-004 | REQ-DS-004；SC-DS-004 | `CT-DS-008`、`CT-DS-009` | `evidence/red-baseline/bats-demo-suite-20260123-124920.log` | 已建立 |
| AC-005 | REQ-DS-003/004；SC-DS-003/004 | `CT-DS-007`、`CT-DS-008` | `evidence/red-baseline/bats-demo-suite-20260123-124920.log` | 已建立 |
| AC-006 | REQ-DS-005；SC-DS-005/006 | `CT-DS-010`、`CT-DS-011` | `evidence/red-baseline/bats-demo-suite-20260123-124920.log` | 已建立 |
| AC-007 | REQ-DS-006；SC-DS-007 | `CT-DS-012`（仅当 `ai_ab.status="executed"`） | `evidence/red-baseline/bats-demo-suite-20260123-124920.log` | 已建立 |
| AC-008 |（Spec delta 未建模；以 design 为准）| `GATE-DS-001`（`shellcheck demo/*.sh`） | `evidence/red-baseline/bats-demo-suite-20260123-124920.log` | 已建立 |

---

========================
C) 执行锚点（Deterministic Anchors）
========================

### 1) 契约测试（Bats）

```bash
bats tests/demo-suite.bats
```

### 2) 关键 jq 契约（来自 spec.md，可复制执行）

- `metrics.json`（Contract 2.6）：
  - `jq -e '(.schema_version|type=="string") and (.run_id|type=="string") and (.git.ref_resolved|type=="string") and (.dataset.queries.sha256|type=="string") and (.config.hash|type=="string") and (.config.devbooks_config.mode|type=="string") and (.metrics.demo_suite.total_duration_ms|type=="number") and (.steps|type=="array")' "<out-dir>/<run-scope>/metrics.json" >/dev/null`
- `compare.json`（Contract 4.5）：
  - `jq -e '(.schema_version|type=="string") and (.overall_verdict|type=="string") and (.metrics|type=="array")' "<out-dir>/<compare-scope>/compare/compare.json" >/dev/null`
- `scorecard.json`（Contract 7.4，仅当 `ai_ab.status="executed"` 时要求）：
  - `jq -e '(.schema_version=="1.0") and (.task_id|IN("simple_bug","complex_bug")) and (.agent_id|IN("A","B")) and (.git.ref_resolved|type=="string") and (.run.duration_ms|type=="number") and (.run.turns|type=="number") and (.variables.fixed|type=="array") and (.variables.varied|type=="array") and (.anchors|type=="array") and (all(.anchors[]; (.evidence_path|type=="string") and (.check_command|type=="string"))) and (.evidence.command_log_path|type=="string") and (.evidence.output_diff_path|type=="string")' "<out-dir>/ai-ab/<task-id>/<agent-id>/scorecard.json" >/dev/null`

### 3) 静态闸门（AC-008，仅 demo/）

```bash
shellcheck demo/*.sh
```

---

========================
D) MANUAL-* 清单（本变更无需人工验收项）
========================

- 无

---

========================
E) 风险与歧义记录（阶段 1）
========================

- 风险：Spec delta 未覆盖 AC-008（质量闸门），目前以 design.md 为真理源落地为 `GATE-DS-001`（ShellCheck demo/）。
- 风险：design.md 的 out-dir 目录结构示意与 spec.md 的稳定路径布局不一致；本次测试与追溯矩阵以 `specs/demo-suite/spec.md` 的 Contract 1（`single/`、`ab-version/`、`ab-config/` 等）为准。
- 歧义：CT-DS-009 的“原因码包含 variable_drift_detected”字段落点，当前测试约定为 `compare.json.reasons[]`（与 proposal.md 的 reasons 语义一致）。

---

========================
G) 价值流与度量（Value Stream and Metrics）
========================

- 目标价值信号：演示结果“可复核率”提升  
  - 定义：在同一仓库状态下重复执行 `bats tests/demo-suite.bats` 与 `demo/demo-suite.sh`，产物路径/字段/原因码稳定且可审计。
- 观测口径（最小集）：
  - Green 证据齐备：`evidence/green-final/` 非空
  - 产物契约通过：`tests/demo-suite.bats` 全绿
  - 写入边界闭合：`write-boundary/new-or-updated-files.txt` 为空且 `tmp-scan.txt` 无 leak

---
status: Archived
archived-at: 2026-01-24T05:55:33Z
archived-by: devbooks-archiver
---
