# Test Review Report（第 3 次）：20260123-0702-improve-demo-suite-ab-metrics

## 概览
- 评审日期：2026-01-24
- 评审范围：`tests/demo-suite.bats`，`tests/helpers/common.bash`
- 测试文件数：1（不含 helper）
- 问题总数：5（Critical: 0, Major: 3, Minor: 2）

## 覆盖率分析

> **注意**：覆盖状态基于测试代码存在性判断，与测试运行结果（Pass/Fail/Skip）无关。

| AC-ID | 测试文件 | 覆盖状态 | 备注 |
|---|---|---|---|
| AC-001 | tests/demo-suite.bats | ✅ 已覆盖 | T-DS-ENTRYPOINT-001 + CT-DS-001/002 |
| AC-002 | tests/demo-suite.bats | ⚠️ 部分覆盖 | 缺少 write-boundary/tmp-scan.txt 的存在性与内容断言 |
| AC-003 | tests/demo-suite.bats | ⚠️ 部分覆盖 | 缺少 ab-version 的 report.md/compare.md 断言 |
| AC-004 | tests/demo-suite.bats | ⚠️ 部分覆盖 | 缺少 ab-config 的 run-a/run-b report.md 与 compare.md 断言 |
| AC-005 | tests/demo-suite.bats | ⚠️ 部分覆盖 | compare.md 与报告一致性未覆盖 |
| AC-006 | tests/demo-suite.bats | ⚠️ 部分覆盖 | 仅降级路径，缺少正常路径锚点字段断言 |
| AC-007 | tests/demo-suite.bats | ⚠️ 部分覆盖 | 未覆盖 ai_ab.status="skipped" 的契约 |
| AC-008 | tests/demo-suite.bats | ✅ 已覆盖 | GATE-DS-001 |

## 问题清单

### Major (建议修复)
1. **[M-001]** `tests/demo-suite.bats:232` - AC-002 的写入边界证据缺少 `write-boundary/tmp-scan.txt` 的存在性与内容断言，无法闭合“默认无 /tmp 残留”的可审计证据链。
   - 建议：补充对 `write-boundary/tmp-scan.txt` 的存在性与内容规则断言。
2. **[M-002]** `tests/demo-suite.bats:257` - AC-003/AC-004 仅覆盖 metrics/compare.json，未覆盖 `ab-version` 与 `ab-config` 的 `report.md`/`compare.md` 必备产物。
   - 建议：补充 run-a/run-b 的 `report.md` 与 `compare/compare.md` 存在性断言。
3. **[M-003]** `tests/demo-suite.bats:311` - AC-006 仅覆盖降级路径（missing_jq/impact_db_missing），缺少正常路径下锚点字段（simple/complex）存在性与非降级语义断言。
   - 建议：增加“依赖可用”的正向场景 fixture，断言关键锚点字段存在与类型。

### Minor (可选修复)
1. **[m-001]** `tests/demo-suite.bats:253` - 直接依赖 `/tmp/ci-drift-snapshot.json` 的全局状态，存在环境残留导致非确定性失败风险。
   - 建议：在测试内显式清理/隔离或通过可控前置条件降低外部干扰。
2. **[m-002]** `tests/demo-suite.bats:359` - AC-007 未覆盖 `ai_ab.status="skipped"` 时的 `skipped_reason` 与 `report.md` 一致性。
   - 建议：补充 skipped 场景 fixture 断言，完善可审计路径。

## 建议
1. 优先补齐写入边界与 A/B 报告产物的缺口，避免 AC-002/003/004 的关键产物未被测试约束。
2. 为 AC-006 增加“非降级”正向路径测试，确保锚点字段在正常场景下可判真。
3. 对 /tmp 全局状态测试做隔离处理，降低偶发失败概率。

## 评审结论

**结论**：APPROVED WITH COMMENTS

**判定依据**：
- Critical 问题数：0
- Major 问题数：3
- AC 覆盖率：8/8（其中 6 项部分覆盖）

---
*此报告由 devbooks-test-reviewer 生成*
