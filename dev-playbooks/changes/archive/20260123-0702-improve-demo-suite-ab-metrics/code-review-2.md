# Code Review（第 2 次）：演示与文档层

- change-id: 20260123-0702-improve-demo-suite-ab-metrics
- truth-root: dev-playbooks/specs
- change-root: dev-playbooks/changes/archive
- reviewer: devbooks-reviewer（System Architect / Security Expert）

## 评审范围

本次评审严格限定在演示与文档层，仅阅读与评审以下文件：

- `demo/demo-suite.sh`
- `demo/DEMO-GUIDE.md`
- `docs/demos/README.md`
- `README.zh-CN.md`

显式未读取/未评审（按硬性约束）：

- `src/**`
- `scripts/**`
- `hooks/**`
- `bin/**`

同时，本次未运行任何脚本/命令以验证行为；以下结论基于静态可读性/一致性/依赖健康/坏味道检查。

## 主要优点

- `demo/demo-suite.sh`：具备较完整的工程化骨架（参数解析、out-dir 安全校验、标准目录初始化、write-boundary 扫描、shellcheck gate、A/B worktree 清理），对“可复用 + 可审计”的 demo 目标友好。
- `demo/DEMO-GUIDE.md`：按“单入口 → out-dir → 目录契约 → compare/原因码 → 公开归档”的叙事组织，读者路径清晰，且强调了 report 与 metrics 一致性要求。
- `docs/demos/README.md`：公开归档约束写得明确，能有效降低大文件/运行期目录/敏感信息误提交风险，并给出推荐结构与复制流程。

## 问题清单

### Critical

- 未发现 Critical 问题（在“仅审查演示与文档层”的约束下，未覆盖实现层与测试证据，因此不对整体交付质量作 Critical 级判断）。

### Major

- 文档/脚本对“最小骨架”的描述与实际实现不一致，容易误导读者预期：
  - `demo/DEMO-GUIDE.md:5` 声称 `demo/demo-suite.sh` “只做 out-dir 安全校验 + run-id 生成 + 标准目录初始化”
  - 但脚本已包含 A/B compare 与 metrics/report 生成、阈值配置读取、变量漂移检测等实现路径（例如 `demo/demo-suite.sh:981-1364`、`demo/demo-suite.sh:1776-2080`）。
  - 同时脚本文件头部注释仍写“后续 MP3+ 将补齐 A/B/compare”等（`demo/demo-suite.sh:2-8`），与当前实现状态冲突。

- “降级兜底（degraded）”目录的文档承诺与脚本当前落盘策略不一致：
  - 文档描述降级时应闭合 `degraded/metrics.json` 与 `degraded/report.md`（`demo/DEMO-GUIDE.md:60-67`）
  - 但脚本在发现 reasons 时主要通过 `status="degraded"` 写入 `single/` 或 `ab-*` 目录（例如 `demo/demo-suite.sh:1768-1833`），未看到写入 `degraded/` 产物的对应实现。

- out-dir“避免污染系统 /tmp”的规则与脚本的临时文件策略存在冲突风险：
  - 文档明确提出避免污染系统 `/tmp`（`demo/DEMO-GUIDE.md:25`）
  - 但脚本多处使用 `mktemp` 且未显式设置 `TMPDIR`（`demo/demo-suite.sh:298`、`demo/demo-suite.sh:376`、`demo/demo-suite.sh:658`、`demo/demo-suite.sh:1167`、`demo/demo-suite.sh:1453`）；在默认环境下这通常会使用系统临时目录。
  - 另外 `metrics.json` 固定写入 `write_boundary.allow_system_tmp=false`（`demo/demo-suite.sh:772-775`），建议澄清该字段语义（“禁止残留”还是“禁止写入”）并与实现对齐。

- README 的“可选依赖”说明未区分到“特性级强依赖”，会导致按 README 准备环境后在 A/B 场景直接失败：
  - `README.zh-CN.md:41-44` 将 `jq` 标注为可选
  - 但 compare 生成在 A/B 路径硬依赖 `jq`（`demo/demo-suite.sh:985`、`demo/demo-suite.sh:1231`）。

- demo-suite 的诊断锚点与仓库内部实现文件强耦合，影响可演进性：
  - `demo/demo-suite.sh:530-536` 直接依赖 `src/server.ts` 与字符串 `handleToolCall`。
  - 这会让实现层重构（文件移动/重命名/符号改名）导致 demo 指标与降级原因发生漂移，且漂移原因对演示者不直观。

### Minor

- README 中 CLI 示例与 MCP 工具命名风格并列但缺少解释映射，增加读者理解成本：
  - CLI 示例使用 `ci-search`（`README.zh-CN.md:65-76` 等）
  - MCP 工具表使用 `ci_search`（`README.zh-CN.md:102-115`）。

- compare 生成逻辑在 `write_ab_version_compare()` 与 `write_ab_config_compare()` 中存在较大重复，后续维护容易出现“修一处漏一处”的不一致风险（可考虑抽取公共函数或模板化输出）。

- `eval "$(diagnosis_export_vars ...)”` 用于回传数组虽采用 `%q` 进行转义（`demo/demo-suite.sh:1785`、`demo/demo-suite.sh:1865`、`demo/demo-suite.sh:1906`、`demo/demo-suite.sh:2043`），但仍属于高风险模式；建议增加注释说明安全前提（prefix 仅来自内部常量）并加入 prefix 白名单校验，避免未来引入用户可控输入后产生注入风险。

- `docs/demos/README.md` 的“公开归档前自检”当前只覆盖 `raw/` 与后缀约束（`docs/demos/README.md:55-61`）；可考虑补充可选的敏感信息扫描建议（例如 token/密钥模式），进一步提升公开归档安全性。

## 可执行建议

1) 统一“当前能力边界”叙述：同步修订 `demo/demo-suite.sh` 文件头部注释（`demo/demo-suite.sh:2-8`）与 `demo/DEMO-GUIDE.md:5`，明确哪些能力已实现（metrics/report/compare、漂移检测等），哪些仍是占位或未实现（例如真实基准执行、AI A/B 自动化闭环等）。

2) 对齐降级策略：二选一并落实到文档与实现同一口径：
   - 方案 A：实现 `degraded/metrics.json` 与 `degraded/report.md` 的写入闭合；或
   - 方案 B：将 `degraded/` 从“稳定目录契约”降级为“预留目录”，并说明当前降级仅通过 `status/reasons` 表达。

3) 明确临时文件策略：建议显式将临时文件落点绑定到 out-dir（例如设置 `TMPDIR="$out_dir_abs/.tmp"` 或为 `mktemp` 指定目录），以满足“唯一落盘根目录”目标，并顺带让 write-boundary 的 `/tmp` 扫描语义更清晰。

4) 在 `README.zh-CN.md` 增加“依赖矩阵（按特性）”：例如 “基础 single：bash + git(可选)；A/B compare：git + jq 必需；impact：sqlite3 + graph.db 可选”等，并解释 `ci-search` 与 `ci_search` 的关系（CLI wrapper vs MCP tool 名称）。

5) 降低诊断锚点耦合：将 `src/server.ts + handleToolCall` 这样的内部锚点迁移为可配置项（环境变量/配置文件），或改为基于稳定的公开资源（dataset/产物契约/命令输出）进行校验，降低重构敏感度。

## 评审结论

**REVISE REQUIRED**

理由：存在多处“文档-实现不一致”与“特性级依赖说明缺口”（Major），会直接影响演示者按文档执行与对外归档的可靠性；建议修订后再进入归档/对外传播。

