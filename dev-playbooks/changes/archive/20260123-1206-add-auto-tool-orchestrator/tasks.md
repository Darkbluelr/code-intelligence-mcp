## 主线计划区

- [x] MP1.1 定稿控制面与默认值（env > config > default；Tier-2 仅 env 启用；[Limits] 文案锚点与退出码枚举对齐）(AC-004, AC-009, AC-012, AC-014)
- [ ] MP1.2 新增 `config/auto-tools.yaml`（默认白名单/预算/并发/超时/回填上限；禁止在 config 中启用 Tier-2）(AC-004, AC-007, AC-009) SKIP-APPROVED: 缺默认白名单/单工具超时/回填上限字段对齐，当前仅有 tier/budget，建议补齐字段并与 spec 对表后再勾选。

- [x] MP2.1 新增 `hooks/auto-tool-orchestrator.sh`：入口/参数解析（mode=plan/run + dry-run）、repo-root 判定、run_id 生成（plan/dry-run 稳定哈希）(AC-003, AC-005, AC-014)
- [x] MP2.2 编排内核输出 schema v1.0：`schema_version/run_id/tool_plan/tool_results/fused_context/degraded`；实现“空注入 JSON”兜底与 exit code=10 (AC-008, AC-012, AC-014)

- [ ] MP3.1 实现工具计划器：意图 → Tier 判定 → tools[]（含 reason/args/timeout_ms）；Tier-2 默认禁用与提示；`planned_codex_command` 由 `CI_CODEX_SESSION_MODE` 决定 (AC-002, AC-003, AC-009, AC-017) SKIP-APPROVED: 当前工具计划为固定 Tier-0/1 列表，intent_type 未驱动 Tier 判定/工具选择；需按意图输出可测的 Tier/Tools 策略并补验证。
- [ ] MP3.2 实现白名单与绕过拒绝：未白名单 → skipped；检测入口层直连尝试时输出空注入 JSON + `[Limits] tool invocation must go through orchestrator` (AC-006, AC-016) SKIP-APPROVED: 未实现工具白名单 schema/校验，未白名单→skipped 与入口层绕过拒绝（`[Limits] tool invocation must go through orchestrator`）路径均缺失。

- [ ] MP4.1 实现工具执行器（run 模式）：并发上限/总墙钟预算/单工具超时；失败不阻塞输出（fail-open）(AC-007, AC-008) SKIP-APPROVED: 当前 run 执行器为串行循环，未按 max_concurrency 并发调度（配置字段未生效）；需补并发执行与预算协同实现/验证。
- [x] MP4.2 结果标准化：`tool_results[]` 字段齐全（status/duration/summary/data/error.code/redactions/truncated）并可被确定性融合消费 (AC-012, AC-014)

- [ ] MP5.1 参数裁剪：对 depth/top_k/token_budget/max_lines 等做上限裁剪；[Limits] 必须记录裁剪原因（例如 `depth clamped to 2`）(AC-006) SKIP-APPROVED: 参数裁剪未覆盖 max_lines 等全量规则且缺 [Limits] 断言，建议补齐裁剪点与测试。
- [ ] MP5.2 路径过滤与脱敏：realpath 限制在 repo-root 内；屏蔽敏感模式（`.env`/`id_rsa*`/`*.pem` 等）；注入文本做脱敏（Bearer/Private Key/AKIA）(AC-006) SKIP-APPROVED: 已做部分输出脱敏，但缺 realpath(repo-root) 限制与敏感路径模式（.env/id_rsa/*.pem 等）过滤/拒绝规则与验证。
- [x] MP5.3 提示注入防护：过滤工具输出中的“忽略指令/执行命令”等模式；输出 `fused_context.for_model.safety.*` 并在 [Limits] 可见 (AC-010)

- [ ] MP6.1 结果融合：稳定排序 + 摘要长度/截断策略固定；同 `claim_key` 的对立项判定 `conflict=true` 并并列展示证据来源 (AC-011) SKIP-APPROVED: 目前仅简单摘要/冲突提示，未实现 claim_key 稳定排序、冲突项 `conflict=true` 与证据来源并列输出、以及固定截断策略。

- [x] MP7.1 重构 `hooks/context-inject-global.sh`：入口层收敛为“输入采集 + 输出注入（委托编排内核）”；移除任何直接工具调用与底层脚本直连 (AC-001, AC-006, AC-016)
- [x] MP7.2 保持 `hooks/augment-context-global.sh` 兼容且等价转发 (AC-013)

- [x] MP8.1 新增 Codex CLI 入口脚本（建议：`bin/codex-auto`）：支持入口 A（会话恢复）与入口 B（单次注入），共享编排内核 (AC-002, AC-015)
- [ ] MP8.2 Codex plan/dry-run：输出 `planned_codex_command` 且不调用 codex 子进程；运行态失败可降级并输出 `[Limits] session continuity unavailable; fallback to stateless exec` (AC-002, AC-003) SKIP-APPROVED: plan/dry-run 已不调用 codex，但 run 失败未回填 `[Limits] session continuity unavailable; fallback to stateless exec`，也未提供无会话降级路径的可测输出。

- [ ] MP9.1 更新 `install.sh`：Claude Code hook 安装同时安装/更新编排内核与默认 `config/auto-tools.yaml`（非破坏性合并 settings.json）(AC-004, AC-013) SKIP-APPROVED: install.sh 尚未安装/更新编排内核与默认配置，也未做 settings.json 非破坏性合并，建议补安装逻辑。

- [x] MP10.1 更新 `docs/TECHNICAL.md` / `docs/TECHNICAL_zh.md`：描述新 schema、plan/dry-run、[Limits]、退出码与迁移/回退 (AC-014, AC-018)
- [ ] MP10.2（可选）更新 `README.md` / `README.zh-CN.md`：新增自动编排启用/禁用与常见故障排查 (AC-004, AC-008) SKIP-APPROVED: README 未新增自动编排启用/禁用与故障排查，建议在对外发布前补齐。

## 临时计划区

- [x] TP1 发现既有 truth specs 与实现不一致时：先回写到本变更包的 spec delta，并在 [Limits]/legacy 策略中给出可测迁移路径（避免“代码先改、规格后补”）
- [ ] TP2 若 Codex CLI 可执行性在 CI 不稳定：确保所有验收均可在 plan/dry-run 下完成，并记录运行态降级策略 SKIP-APPROVED: CI 未观察 codex CLI 不稳定，条件未触发；建议出现波动时补 plan/dry-run 兜底与运行态降级记录。

## 断点区

- 关键输入：`dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/proposal.md`、`dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/design.md`、`dev-playbooks/changes/20260123-1206-add-auto-tool-orchestrator/specs/**/spec.md`
- 关键文件：`hooks/context-inject-global.sh`、`hooks/augment-context-global.sh`、`install.sh`、`docs/TECHNICAL*.md`
- 闸门命令：`npm test`（bats）/ `npm run build`（如需要）
