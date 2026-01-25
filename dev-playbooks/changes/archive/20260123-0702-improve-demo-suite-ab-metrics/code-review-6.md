truth-root: dev-playbooks/specs；change-root: dev-playbooks/changes（来源：dev-playbooks/project.md）

# 代码评审 第 6 次：20260123-0702-improve-demo-suite-ab-metrics

- reviewer: devbooks-reviewer（System Architect / Security Expert）
- 评审范围（只读）：
  - `demo/demo-suite.sh`
  - `demo/DEMO-GUIDE.md`
  - `dev-playbooks/docs/长期可复用演示方案.md`
  - `docs/demos/README.md`
  - `README.zh-CN.md`
  - `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/tasks.md`
  - `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/verification.md`
  - `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/green-final/bats-demo-suite-20260124-081912.no-fail-scan.txt`
  - 对照：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/code-review-4.md`、`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/code-review-5.md`
- 评审基准：`dev-playbooks/specs/demo-suite/spec.md`、`dev-playbooks/specs/_meta/project-profile.md`、`dev-playbooks/specs/_meta/glossary.md`

## 严重问题（必须修复）

- `README.zh-CN.md` 未包含“特性级依赖矩阵”，也未提供 `ci-search`（CLI）与 `ci_search`（MCP 工具名）之间的显式映射说明，导致中文首页无法独立解释功能依赖与命令名一致性，和本次评审目标不一致：`README.zh-CN.md`
  - 建议：补一张“功能 → 必需/可选依赖”矩阵，并新增一段“命令名映射”说明（例如：`ci-search` 命令对应 MCP 工具 `ci_search`，命令行使用短横线、工具名使用下划线）。

## 可维护性风险（建议修复）

- 未发现新增可维护性风险（限本次评审范围）。

## 风格与一致性建议（可选）

- 无。

## 新增质量闸门建议（如需）

- 无。

## 产出物完整性检查

| 检查项 | 状态 | 说明 |
|--------|------|------|
| tasks.md 完成度 | ✅ | 20/20 已完成（未发现 `- [ ]`） | 
| 测试全绿（非 Skip） | ❌ | 未运行测试；仅有 `bats-demo-suite-20260124-081912.no-fail-scan.txt` 作为日志扫描证据 | 
| Green 证据存在 | ✅ | `evidence/green-final/` 目录存在（共 13 个文件） | 
| 无失败模式在证据中 | ✅ | `bats-demo-suite-20260124-081912.no-fail-scan.txt` 显示 FAIL/ERROR 无匹配 | 

## 已核验要点（通过）

- `docs/demos/README.md` 已包含“可选敏感信息扫描建议”并给出示例命令：`docs/demos/README.md`
- compare 逻辑已通过共享函数收敛（`init_compare_thresholds` / `read_compare_inputs` / `compute_compare_metric_outcome` / `write_compare_outputs`）：`demo/demo-suite.sh`
- `verification.md` 的 Green 证据引用已更新到 `20260124-081912`：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/verification.md`

## 限制与未验证项

- 未运行任何测试（按要求），无法直接确认“全绿且无 Skip”；仅能引用现有 Green 证据与 no-fail-scan 结果。
- 未读取 `src/**`、`scripts/**`、`hooks/**`、`tests/**`（按范围限制）。

## 评审结论

**REVISE REQUIRED**
