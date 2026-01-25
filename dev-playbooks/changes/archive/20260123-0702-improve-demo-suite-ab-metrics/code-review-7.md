truth-root: dev-playbooks/specs；change-root: dev-playbooks/changes（来源：dev-playbooks/project.md）

# 代码评审 第 7 次：20260123-0702-improve-demo-suite-ab-metrics

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
  - 对照：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/code-review-6.md`

## 严重问题（必须修复）

- `docs/demos/README.md` 在仓库中不存在，导致“公开归档约束 + 可选敏感信息扫描建议”无法核验，且已出现悬挂引用与交付不一致：`demo/DEMO-GUIDE.md:143`、`dev-playbooks/docs/长期可复用演示方案.md:11`、`dev-playbooks/docs/长期可复用演示方案.md:127`、`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/tasks.md:212`。建议补齐 `docs/demos/README.md` 并补充“可选敏感信息扫描”说明，或同步回滚引用与任务状态。

## 可维护性风险（建议修复）

- 未发现新增可维护性风险（限本次评审范围）。

## 风格与一致性建议（可选）

- 无。

## 新增质量闸门建议（如需）

- 无。

## 产出物完整性检查

| 检查项 | 状态 | 说明 |
|--------|------|------|
| tasks.md 完成度 | ✅ | 20/20 已完成；但 MP9.3 产物缺失见“严重问题” |
| 测试全绿（非 Skip） | ❌ | 未运行测试；仅有 `bats-demo-suite-20260124-081912.no-fail-scan.txt` 作为日志扫描证据 |
| Green 证据存在 | ✅ | `evidence/green-final/` 存在（共 13 个文件） |
| 无失败模式在证据中 | ✅ | `bats-demo-suite-20260124-081912.no-fail-scan.txt` 显示 FAIL/ERROR 无匹配 |

## 已核验要点（通过）

- `README.zh-CN.md` 已包含 demo-suite 特性级依赖矩阵与 `ci-search`/`ci_search` 命令名映射说明：`README.zh-CN.md:46`、`README.zh-CN.md:80`。
- compare 逻辑仍为共享函数收敛，`ab-version` 与 `ab-config` 复用 `init_compare_thresholds`/`read_compare_inputs`/`compute_compare_metric_outcome`/`write_compare_outputs`：`demo/demo-suite.sh:1068`、`demo/demo-suite.sh:1137`、`demo/demo-suite.sh:1150`、`demo/demo-suite.sh:1233`、`demo/demo-suite.sh:1348`、`demo/demo-suite.sh:1375`。
- `verification.md` 的 Green 证据日志已指向 `20260124-081912`：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/verification.md:35`、`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/verification.md:36`。

## 限制与未验证项

- 未运行测试（按要求），仅读取 `bats-demo-suite-20260124-081912.no-fail-scan.txt`，未读取对应 Green 日志正文。
- 未读取 `dev-playbooks/specs/**` 与 `dev-playbooks/specs/_meta/**`，因此未核验术语一致性与规格一致性。
- 未读取 `src/**`、`scripts/**`、`hooks/**`、`tests/**`（按范围限制）。

## 推荐的下一步

**下一步：交回 `devbooks-coder`**  
原因：存在阻断项（`docs/demos/README.md` 缺失）需要补齐或修复引用后再评审。

## 评审结论

**REVISE REQUIRED**
