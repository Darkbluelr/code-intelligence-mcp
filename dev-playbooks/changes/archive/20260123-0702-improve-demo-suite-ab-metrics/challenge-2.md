1) **结论（第 2 次 Challenge，`<truth-root>`=`dev-playbooks/specs`，`<change-root>`=`dev-playbooks/changes`）**：`Revise` —— Proposal v2 已基本覆盖 Judge-1 的“必须修改项”（写入边界、/tmp 策略、A/B 语义、metrics/compare/scorecard 契约、双场景锚点、证据树与闸门命令），但仍存在少量“会让验收锚点不可落地/不可通过”的缺口与不一致，尤其是 **质量闸门可通过性** 与 **写入边界检查命令的可复现一致性**。

> 专家视角：System Architect + Product Manager（关注可审计性、可复现性、范围可控与长期维护成本）。

2) **阻断项（Blocking）**

- **质量闸门命令虽“可跑”，但按 Proposal v2 当前定义无法形成可通过的闸门（会阻塞 AC-008）**
  - Proposal v2 定义的 ShellCheck 闸门命令为：`shellcheck scripts/*.sh hooks/*.sh demo/*.sh`（见 proposal.md“Quality gates”）。
  - 我已在当前仓库运行该命令，ShellCheck 报错（非仅告警），至少包含：
    - `scripts/show-context.sh`：存在空 `elif ...; then` 分支导致语法错误（ShellCheck 报 `SC1073/SC1048/SC1072`）。
    - `scripts/scip-to-graph.sh`：存在反引号扩展解析错误（ShellCheck 报 `SC1073/SC1072`）。
  - 这意味着若不调整“闸门范围/严重级别/基线策略”，本变更将被迫把既有脚本的 ShellCheck 历史债务一并清理，显著放大范围与不确定性。
  - **最小改动集**（二选一即可闭合）：
    - A) 将本变更闸门范围收敛到“demo-suite 相关脚本”（例如 `demo/*.sh` + 新增 runner/compare 脚本），并明确不以全仓 `scripts/*.sh hooks/*.sh` 的 ShellCheck 作为本变更 DoD；
    - B) 若坚持全仓 ShellCheck：在 proposal 中显式承诺“会修复现有 ShellCheck 阻断错误并给出范围边界（至少列出需修的脚本清单）”，否则属于隐性范围膨胀。

- **写入边界“哨兵文件命名/落点”存在不一致，会导致证据树不可复现**
  - Proposal v2 的写入边界检查说明中，哨兵文件示例为：`<out-dir>/.write-boundary-sentinel`；但 Evidence 最小结构里要求留存：`write-boundary/write-boundary-sentinel`（两者文件名与路径不一致）。
  - **最小改动集**：统一为同一文件名与同一路径（任选其一，但必须贯穿“检查命令 + evidence 结构”一致）。

- **写入边界“find 排除 out-dir”示例命令存在路径匹配风险，可能把 out-dir 内文件误判为越界写入**
  - 现有示例：`find . ... -not -path "<out-dir>/*"`；但 `find .` 的输出与 `-path` 匹配通常以 `./` 开头，若 `<out-dir>` 未含 `./` 前缀，存在排除失效风险（从而把 out-dir 内更新也列出来）。
  - **最小改动集**：在 proposal 中把该示例命令修正为与实际路径前缀一致的形式（例如显式以 `./` 作为基准，或改用绝对路径策略），并声明“从哪个工作目录执行该命令”。

- **scorecard 契约缺少“可执行校验方式”，与 v2 强调的“可审计契约层”不一致**
  - Proposal v2 给出了 `metrics.json` 与 `compare.json` 的 `jq -e ...` 校验命令，但 `scorecard.json` 仅给出字段清单与评分规则，缺少最小可跑的校验方式。
  - **最小改动集**：补一条 `jq -e`（或等价）对 `scorecard.json` 的最小契约校验命令，并把它纳入“Quality gates / Evidence”之一（至少落到 `gates/scorecard-schema.txt` 或类似证据文件）。

3) **遗漏项（Missing）**

- **A/B 隔离策略与 `.devbooks` 本地配置文件的关系需在 Proposal 明确（否则 ref A/B 的“同环境”不自证）**
  - 事实：`.devbooks/config.yaml` 在本仓库被 `.gitignore` 忽略（`git check-ignore -v .devbooks/config.yaml` 可见来源于 `.gitignore` 规则），因此 `git worktree`/临时 clone 默认不会携带该文件。
  - 但同时，现有 hooks/脚本（例如 `hooks/context-inject-global.sh`）会读取 `CWD/.devbooks/config.yaml` 来决定行为；若隔离工作目录缺少该文件，A/B 运行可能在“看似同 ref、实则不同配置”的情况下产生不可解释差异。
  - **最小改动集**：在 proposal 中明确以下之一：
    - A) A/B 运行不依赖 `.devbooks/config.yaml`（并在 `metrics.json` 记录“未使用/缺失”的事实）；或
    - B) runner 必须将该配置复制/生成到隔离工作目录（并记录其 hash/路径到 `metrics.json`），作为“同环境”的审计锚点。

- **compare 的“默认阈值”虽可写入 `compare.json.thresholds.used`，但建议在 Proposal 给出最小默认阈值集合清单**
  - 否则实现方仍需在未明确基准的情况下拍脑袋选阈值，影响结论可信度与跨版本对比的一致性。
  - （不要求写实现步骤；只需列出核心指标的默认 tolerance 值与单位口径即可。）

4) **非阻断项（Non-blocking）**

- **双场景锚点可判真已显著改善，但“简单场景固定输入”建议去掉虚构行号，避免误导**
  - 当前固定输入包含 `src/server.ts:1`，而真实 `handleToolCall` 在 `src/server.ts` 的更靠后位置；这不会阻止“文件/符号存在”锚点，但会降低示例的直觉可信度。

- **证据树最小结构很完整，但可补一句“哪些证据必须来自同一次 run-id”以避免拼装证据**

5) **替代方案（范围收缩建议）**

- 若希望尽快进入 Judge-2 并降低返工：优先把本次“质量闸门”限定为 demo-suite 新增/修改脚本 + `npm run build`，把全仓 ShellCheck 修复单独立案（否则本变更容易被历史债务拖死）。

6) **风险与证据缺口**

- **验收锚点与闸门耦合风险**：若 ShellCheck 闸门范围不收敛/不声明基线策略，本变更 DoD 将不可控扩大到“修全仓脚本告警”，导致交付不可预测。
- **同环境自证风险**：未定义 `.devbooks/config.yaml` 的隔离/复制/禁用策略时，版本 A/B 与配置 A/B 的“同环境”无法被 `metrics.json` 充分自证，compare 结论会被质疑为配置漂移造成。

