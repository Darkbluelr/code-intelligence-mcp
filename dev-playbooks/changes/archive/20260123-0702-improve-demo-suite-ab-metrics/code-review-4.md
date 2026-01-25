truth-root: dev-playbooks/specs；change-root: dev-playbooks/changes（来源：dev-playbooks/project.md）

# Code Review（第 4 次）：演示与文档层（对照 code-review-3 阻断项）

- change-id: 20260123-0702-improve-demo-suite-ab-metrics
- reviewer: devbooks-reviewer（System Architect / Security Expert）
- 评审范围（只读）：
  - demo/demo-suite.sh
  - demo/DEMO-GUIDE.md
  - dev-playbooks/docs/长期可复用演示方案.md
  - docs/demos/README.md（当前仓库未发现该文件）
  - README.zh-CN.md
  - dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/tasks.md
  - dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/verification.md
  - dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/green-final/（仅列清单与大小）
  - dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/code-review-2.md
  - dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/code-review-3.md
- 限制：
  - 未读取 dev-playbooks/specs/**（超出评审范围）
  - 未运行任何测试/脚本；未读取 tests/**/src/**/scripts/**/hooks/**
  - 证据日志仅列文件名与大小，未打开内容

## 对照 code-review-3 的阻断项

### 已解决项

- compare 输出逻辑已抽取为 `write_compare_outputs`，`write_ab_version_compare` 与 `write_ab_config_compare` 的重复逻辑明显收敛：`demo/demo-suite.sh:1261`、`demo/demo-suite.sh:1348`、`demo/demo-suite.sh:1375`
- tasks 完成度已闭合：`tasks.md` 无未勾选项（20/20）：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/tasks.md`
- Green 证据目录已存在且有文件：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/green-final/`（共 11 个文件）

### 仍遗留项

- “公开归档自检补充可选敏感信息扫描”仍未落地；且 `docs/demos/README.md` 在仓库中缺失，导致两处文档引用失效：`demo/DEMO-GUIDE.md:143`、`dev-playbooks/docs/长期可复用演示方案.md:11`、`dev-playbooks/docs/长期可复用演示方案.md:127`
- 交付完整性仍未闭合：未运行测试，亦未读取 green-final 日志确认无 FAIL/ERROR，无法满足 Reviewer 全绿证据闸门：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/verification.md`

## 严重问题（必须修复）

- `docs/demos/README.md` 缺失，文档引用失效且与任务结论冲突，公开归档约束无法被验证：`demo/DEMO-GUIDE.md:143`、`dev-playbooks/docs/长期可复用演示方案.md:11`、`dev-playbooks/docs/长期可复用演示方案.md:127`、`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/tasks.md`
- 交付完整性闸门未满足：未验证测试全绿且未检查 evidence 日志失败模式，无法给出 APPROVED：`dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/verification.md`

## 可维护性风险（建议修复）

- 未发现新增可维护性风险（在当前评审范围内）

## 风格与一致性建议（可选）

- 无

## 新增质量闸门建议（如需）

- 无

## 产出物完整性检查

| 检查项 | 状态 | 说明 |
|--------|------|------|
| tasks.md 完成度 | ✅ | 20/20 已完成（未发现 `- [ ]`） |
| 测试全绿（非 Skip） | ❌ | 未运行测试（范围限制） |
| Green 证据存在 | ✅ | evidence/green-final/ 有 11 个文件 |
| 无失败模式在证据中 | ❌ | 未读取日志内容（范围限制） |

## evidence/green-final/ 文件清单（名称与大小）

- ab-config-mp5-20260123-120449.log — 228 B
- ab-version-HEAD-HEAD~1-20260123-191725.log — 2625 B
- ab-version-abtest-1-20260123-111134.log — 1243 B
- bats-demo-suite-20260123-143750.log — 1120 B
- bats-demo-suite-20260123-202344.log — 1120 B
- mp1.2-mp2.3-20260123-083401.log — 2866 B
- mp2.1-mp2.2-20260123-083517.log — 729 B
- mp6-mp7-mp8-single-20260123-142709.log — 974 B
- mp6-mp7-mp8-single-20260123-153524.log — 1096 B
- shellcheck-demo-20260123-142709.log — 12 B
- shellcheck-demo-20260123-153524.log — 12 B

## 限制与未验证项

- 未读取 `dev-playbooks/specs/**`，无法核对术语与契约一致性（按评审范围限制）
- 未运行 `npm test` 或 `bats tests/demo-suite.bats`，无法确认全绿
- 未打开 green-final 日志，无法确认无 FAIL/ERROR

## 评审结论：REVISE REQUIRED
