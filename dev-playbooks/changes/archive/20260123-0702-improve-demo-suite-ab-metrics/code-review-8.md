truth-root: dev-playbooks/specs；change-root: dev-playbooks/changes（来源：dev-playbooks/project.md）

# 代码评审 第 8 次：20260123-0702-improve-demo-suite-ab-metrics

- reviewer: devbooks-reviewer（System Architect / Security Expert）
- 评审范围（只读）：
  - `demo/demo-suite.sh`
  - `demo/DEMO-GUIDE.md`
  - `dev-playbooks/docs/长期可复用演示方案.md`
  - `docs/demos/README.md`
  - `README.zh-CN.md`
  - `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/tasks.md`
  - `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/verification.md`
  - `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/green-final/bats-demo-suite-20260124-131213.log`
  - `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/green-final/bats-demo-suite-20260124-131213.no-fail-scan.txt`
  - 对照：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/code-review-7.md`

## 严重问题（必须修复）

- `docs/demos/README.md` 在本地仓库中不存在，导致“公开归档约束 + 可选敏感信息扫描建议”无法核验，且形成悬挂引用与交付不一致：`demo/DEMO-GUIDE.md:143`、`dev-playbooks/docs/长期可复用演示方案.md:11`、`dev-playbooks/docs/长期可复用演示方案.md:127`、`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/tasks.md:212`。最小修复：补齐 `docs/demos/README.md` 并包含公开归档约束与可选敏感信息扫描建议；或回滚上述引用并同步修正任务状态。

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
| 测试全绿（非 Skip） | ✅ | 16 通过 / 0 跳过 / 0 失败（见 `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/green-final/bats-demo-suite-20260124-131213.log`） |
| Green 证据存在 | ✅ | `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/green-final/` 存在（共 19 个文件） |
| 无失败模式在证据中 | ✅ | `dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/green-final/bats-demo-suite-20260124-131213.no-fail-scan.txt` 显示 FAIL/ERROR 无匹配 |

## 已核验要点（通过）

- Green 日志为全量 ok（1..16），且未出现 `not ok` 记录：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/green-final/bats-demo-suite-20260124-131213.log`。
- no-fail 扫描文件确认 FAIL/ERROR 无命中：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/green-final/bats-demo-suite-20260124-131213.no-fail-scan.txt`。

## 限制与未验证项

- 未运行测试，仅基于现有 Green 证据日志进行核验。
- `docs/demos/README.md` 缺失，无法核验“公开归档约束 + 可选敏感信息扫描建议”。

## 推荐的下一步

**下一步：交回 `devbooks-coder`**

原因：存在阻断项（`docs/demos/README.md` 缺失）。修复后再进入评审，方可交给 `devbooks-archiver`。

## 评审结论

**REVISE REQUIRED**
