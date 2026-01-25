# 测试评审报告（第 4 次）：20260123-0702-improve-demo-suite-ab-metrics

## 概览
- 评审日期：2026-01-24
- 评审范围：`tests/demo-suite.bats`、`tests/fixtures/demo-suite/**`、`tests/helpers/common.bash`
- 测试文件数：1
- 问题总数：4（Critical: 0, Major: 3, Minor: 1）

## 覆盖率分析

> **注意**：覆盖状态基于测试代码存在性判断，与测试运行结果（Pass/Fail/Skip）无关。

| AC-ID | 测试文件 | 覆盖状态 | 备注 |
|---|---|---|---|
| AC-001 | `tests/demo-suite.bats` | ✅ 已覆盖 | T-DS-ENTRYPOINT-001、CT-DS-001/002 |
| AC-002 | `tests/demo-suite.bats` | ⚠️ 部分覆盖 | 缺少 `/tmp/ci-drift-snapshot.json` 的直接断言 |
| AC-003 | `tests/demo-suite.bats` | ✅ 已覆盖 | CT-DS-006/007 |
| AC-004 | `tests/demo-suite.bats` | ✅ 已覆盖 | CT-DS-008/009 |
| AC-005 | `tests/demo-suite.bats` | ⚠️ 部分覆盖 | compare.json 的 `thresholds.*` 必填字段未覆盖 |
| AC-006 | `tests/demo-suite.bats` | ✅ 已覆盖 | CT-DS-010/011 |
| AC-007 | `tests/demo-suite.bats` | ✅ 已覆盖 | CT-DS-012 |
| AC-008 | `tests/demo-suite.bats` | ✅ 已覆盖 | GATE-DS-001 |

## 问题清单

### Major (建议修复)
1. **[M-001]** `tests/demo-suite.bats:97` - CT-DS-005 仅检查 `tmp-scan.txt` 为空，未按规格断言 `/tmp/ci-drift-snapshot.json` 不存在，导致 AC-002 的默认 /tmp 策略未被直接覆盖。参考：`dev-playbooks/specs/demo-suite/spec.md:404`、`dev-playbooks/specs/demo-suite/spec.md:329`。
2. **[M-002]** `tests/demo-suite.bats:38` - compare.json 断言仅覆盖 `schema_version/overall_verdict/metrics`，未校验 `thresholds.source/path/sha256` 必填字段，与规格 4.1 不一致。参考：`dev-playbooks/specs/demo-suite/spec.md:288`。
3. **[M-003]** `tests/demo-suite.bats:76` - report.md 仅做“存在且非空”检查，未验证与同目录 `metrics.json.status` 和 `metrics.json.reasons[]` 一致（规格 3）。参考：`dev-playbooks/specs/demo-suite/spec.md:282`。

### Minor (可选修复)
1. **[m-001]** `tests/demo-suite.bats:53` - 测试依赖 `rg`，但最小依赖列表未包含该工具，可能导致环境不一致下的非预期失败。参考：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/verification.md:51`。

## 建议
1. 补充 CT-DS-005 的 `/tmp/ci-drift-snapshot.json` 断言，或将现有检查对齐规格并更新追溯说明。
2. 扩展 compare.json 的断言覆盖 `thresholds.*` 必填字段，避免 compare 元数据回归。
3. 为 report.md 增加与 `metrics.json.status/reasons` 一致性的断言（可基于 fixture 校验）。
4. 若继续使用 `rg`，建议在验证计划中补充依赖，或改为使用 `grep -F` 以降低环境耦合。

## 评审结论

**结论**：APPROVED WITH COMMENTS

**判定依据**：
- Critical 问题数：0
- Major 问题数：3
- AC 覆盖率：7/8（87.5%，含 2 项部分覆盖）

---
*此报告由 devbooks-test-reviewer 生成*
