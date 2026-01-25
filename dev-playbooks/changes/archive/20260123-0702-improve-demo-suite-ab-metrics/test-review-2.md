# 测试评审报告（第 2 次）：20260123-0702-improve-demo-suite-ab-metrics

## 概览

- 评审日期：2026-01-23
- 评审角色：DevBooks Test Reviewer
- 评审范围：`tests/**`（重点：`tests/demo-suite.bats`；相关 helper：`tests/helpers/common.bash`）
- 问题总数：5（Critical: 0, Major: 2, Minor: 3）

## 覆盖率分析（逐 AC）

> 注意：覆盖状态基于测试代码存在性判断，与测试运行结果（Pass/Fail/Skip）无关。

| AC-ID | 测试文件 | 主要 Test IDs | 覆盖状态 | 备注 |
|---|---|---|---|---|
| AC-001 | `tests/demo-suite.bats` | `T-DS-ENTRYPOINT-001`, `CT-DS-001`, `CT-DS-002` | ✅ 已覆盖 | 入口存在性 + `single/` 产物契约均有用例 |
| AC-002 | `tests/demo-suite.bats` | `CT-DS-003`, `CT-DS-004`, `CT-DS-005` | ⚠️ 部分覆盖 | 写入边界的“证据文件存在/为空”覆盖到；但 `CT-DS-005` 为全局状态断言，契约力度偏弱（见 Major） |
| AC-003 | `tests/demo-suite.bats` | `CT-DS-006`, `CT-DS-007` | ✅ 已覆盖 | `ab-version/` 目录布局与 compare schema 均有用例 |
| AC-004 | `tests/demo-suite.bats` | `CT-DS-008`, `CT-DS-009` | ✅ 已覆盖 | `ab-config/` compare schema + reason code 用例覆盖 |
| AC-005 | `tests/demo-suite.bats` | `CT-DS-007`, `CT-DS-008` | ✅ 已覆盖 | A/B 两类 compare schema 均覆盖到 |
| AC-006 | `tests/demo-suite.bats` | `CT-DS-010`, `CT-DS-011` | ✅ 已覆盖 | `missing_fields[]`/`reasons[]`/`null` 的降级表示法有用例 |
| AC-007 | `tests/demo-suite.bats` | `CT-DS-012` | ⚠️ 部分覆盖 | 覆盖了“scorecard 存在时的 schema”；但缺少“未执行时不要求 scorecard”的契约用例（见 Minor） |
| AC-008 | `tests/demo-suite.bats` | `GATE-DS-001` | ✅ 已覆盖 | 有 ShellCheck gate；但实现方式存在确定性风险（见 Major） |

覆盖统计：
- ✅ 已覆盖：6 / 8
- ⚠️ 部分覆盖：2 / 8
- ❌ 缺失：0 / 8
- 覆盖得分（✅=1，⚠️=0.5）：(6 + 2*0.5) / 8 = 87.5%

## 问题清单

### Critical（必须修复）

- 无

### Major（建议修复）

1. **[M-001] `CT-DS-005` 使用全局 `/tmp` 状态断言，缺少用例动作绑定，且可能引入环境依赖**
   - 位置：`tests/demo-suite.bats:253`
   - 现状：仅断言 `/tmp/ci-drift-snapshot.json` 不存在；该断言不与“产物生成/写入边界”动作关联，且依赖机器全局状态。
   - 风险：可重复性与诊断性较弱（失败时难以判断是哪条契约被破坏），并可能出现非业务因素导致的失败。
   - 建议（测试层面）：
     - 若目标是“写入边界证据闭合”，优先用 **out-dir 内的可审计证据文件** 表达（例如 `write-boundary/new-or-updated-files.txt` 的内容约束、或 `metrics.json.write_boundary.*` 字段契约），避免绝对路径全局断言。
     - 若确需覆盖“系统临时目录不应产生某类文件”，建议改为与测试用例动作绑定且可控的路径（例如在 `TEMP_DIR` 下构造唯一文件名并断言不被创建），或将该断言移至更合适的集成层测试。

2. **[M-002] `GATE-DS-001` 通过 `bash -lc` 运行 ShellCheck，引入登录 shell 的不确定性**
   - 位置：`tests/demo-suite.bats:392-396`
   - 现状：`run bash -lc "cd '$PROJECT_ROOT' && shellcheck demo/*.sh"`
   - 风险：`-l` 可能加载用户本地 profile（PATH、alias、shell options 等），导致测试受个人环境影响，降低确定性与可移植性。
   - 建议（测试层面）：
     - 优先使用 `bash -c`（或不启子 shell，直接 `run shellcheck "$PROJECT_ROOT"/demo/*.sh`），并在必要时显式设置 PATH/工作目录，避免隐式依赖。
     - 额外增强：在运行前增加对 `demo/*.sh` 匹配结果的显式检查/错误信息，使失败更可诊断（避免“glob 未匹配”的非直观报错）。

### Minor（可选修复）

1. **[m-001] `AC-007` 的“未执行时不要求 scorecard”缺少对应契约用例**
   - 位置：`tests/demo-suite.bats:359-386`
   - 现状：`CT-DS-012` 覆盖了 scorecard 存在时的 schema 校验，但未体现“某些状态下 scorecard 可缺省”的契约。
   - 建议：补充一个 fixture 场景，明确表达“status=skipped 时 scorecard 缺省仍合法”的契约（例如通过目录不存在/文件缺失时的允许路径断言），以避免后续误把“可选”演进成“必选”。

2. **[m-002] `tests/demo-suite.bats` 内部自定义 `require_cmd` 与通用 helper 语义不一致**
   - 位置：`tests/demo-suite.bats:27-38`；对照 `tests/helpers/common.bash:274-281`
   - 现状：本文件使用 `require_cmd`（缺失即 fail），通用 helper 中已有 `skip_if_missing` 等工具。
   - 建议：统一依赖处理策略与命名（例如对“必须依赖”使用一致的 fail 形式；对“可选依赖”使用一致的 skip 形式），降低维护者理解成本。

3. **[m-003] 头部注释包含阶段性措辞，可能对维护者产生误导**
   - 位置：`tests/demo-suite.bats:10-15`、`tests/demo-suite.bats:197-204`
   - 现状：注释描述“当前预期失败”等阶段性语义；当测试套件进入稳定运行后，读者可能误解该用例的长期意图。
   - 建议：将注释改为“此用例用于验证入口脚本存在性/可执行性（历史上曾作为缺失时的保护）”这类与长期意图一致的表述。

## 建议（可执行清单）

1. 重写 `CT-DS-005`：避免依赖绝对路径 `/tmp` 的全局状态；将“写入边界”尽量表达为 out-dir 内的可审计证据契约（或明确将其上移/下移到合适的测试层级）。
2. 调整 `GATE-DS-001`：避免 `bash -lc`；改为确定性更强的调用方式，并增强 glob 未匹配时的诊断信息。
3. 为 AC-007 增补一个“scorecard 可缺省”的 fixture 用例，防止契约被无意收紧。

## 评审结论

**结论：APPROVED WITH COMMENTS**

判定依据：
- Critical：0
- Major：2（≤5）
- AC 覆盖：✅6 / ⚠️2 / ❌0；覆盖得分 87.5%（≥80%）

