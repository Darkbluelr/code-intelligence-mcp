# Test Review Report: 20260123-0702-improve-demo-suite-ab-metrics（第 1 次）

## 概览

- 评审日期：2026-01-24
- 评审范围：`tests/demo-suite.bats`
- 测试文件数：1
- 问题总数：2（Critical: 0, Major: 1, Minor: 1）

## 覆盖率分析

> 覆盖状态基于“测试用例存在性”判断，与运行结果（Pass/Fail/Skip）无关。

| AC-ID | 测试文件 | 覆盖状态 | 备注 |
|---|---|---|---|
| AC-001 | `tests/demo-suite.bats` | ✅ 已覆盖 | `T-DS-ENTRYPOINT-001`、`CT-DS-001`、`CT-DS-002` |
| AC-002 | `tests/demo-suite.bats` | ✅ 已覆盖 | `CT-DS-003`、`CT-DS-004`、`CT-DS-005` |
| AC-003 | `tests/demo-suite.bats` | ✅ 已覆盖 | `CT-DS-006`、`CT-DS-007` |
| AC-004 | `tests/demo-suite.bats` | ✅ 已覆盖 | `CT-DS-008`、`CT-DS-009` |
| AC-005 | `tests/demo-suite.bats` | ✅ 已覆盖 | `CT-DS-007`、`CT-DS-008`（compare schema） |
| AC-006 | `tests/demo-suite.bats` | ✅ 已覆盖 | `CT-DS-010`、`CT-DS-011`（降级/缺失表示法） |
| AC-007 | `tests/demo-suite.bats` | ✅ 已覆盖 | `CT-DS-012`（scorecard schema） |
| AC-008 | `tests/demo-suite.bats` | ✅ 已覆盖 | `GATE-DS-001`（`shellcheck demo/*.sh`） |

## 问题清单

### Major（建议修复）

1. **[M-001]** `CT-DS-005` 依赖全局路径 `/tmp/ci-drift-snapshot.json` 的“存在性”作为断言，存在环境污染导致的误报风险  
   - 风险：只要本机其他任务/历史运行留下同名文件，本用例会无关失败，降低可重复性。  
   - 建议：把“/tmp 不应作为最终落盘”的断言收敛为**run-id 前缀的可审计扫描**（例如只检查 `demo-suite` 约定的前缀），或把该检查迁移到 demo-suite 运行产物的 `write-boundary/tmp-scan.txt` 契约上，避免依赖全局状态。

### Minor（可选优化）

1. **[m-001]** 文件头部注释仍描述“入口锚点当前预期失败以建立 Red”，但当前已是 Green 流程  
   - 建议：更新注释为“历史说明：Red 基线曾失败，现已转绿”，避免误导后续维护者。

## 建议

1. 继续保持 fixture 驱动 + `jq` 表达式集中化（`*_JQ_EXPR`）的模式，利于与 `verification.md` 的执行锚点长期同步。  
2. 若后续要提升对 AC-007 条件性的表达力，可增加 1 个小用例：当 `ai_ab.status="skipped"` 时 `metrics.json` 不要求 scorecard（以 fixture 表达，不引入真实 AI 运行）。

## 评审结论

**结论：APPROVED WITH COMMENTS**

**判定依据**：
- Critical：0
- Major：1（不阻断归档，但建议在下一次迭代修复以降低偶发失败）
- AC 覆盖率：8/8（≥ 90%）

---
*此报告依据 `devbooks-test-reviewer` 输出格式生成。*

