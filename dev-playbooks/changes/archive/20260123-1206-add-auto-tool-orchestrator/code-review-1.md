# Code Review Report: 20260123-1206-add-auto-tool-orchestrator（第 1 次）

## 概览

- 评审日期：2026-01-24
- 评审范围：`hooks/auto-tool-orchestrator.sh`、`hooks/context-inject-global.sh`、`hooks/augment-context-global.sh`、`bin/codex-auto`、`install.sh`、`config/auto-tools.yaml`
- 代码变更类型：新增编排内核 + 入口层收敛 + 安装/文档适配（核心为 Bash；不触达 `src/` 业务逻辑）

## 主要优点

1. **单一编排通道落地**：入口层（`context-inject-global.sh`/`augment-context-global.sh`）不再承载工具执行逻辑，编排集中在 `auto-tool-orchestrator.sh`，符合“单入口可验证”的治理目标（AC-016）。
2. **plan/dry-run 可测试且确定性**：plan 输出稳定（固定 `created_at`、稳定 `run_id`），并通过 fake codex 验证“绝不调用 codex 子进程”，利于 CI 与回归（AC-002/003）。
3. **兼容性意识明确**：Orchestrator envelope 与 5 层结构化字段并存（顶层 + `fused_context.for_model.structured`），避免一次性破坏既有消费者；同时提供 legacy 可审计标记（AC-018）。
4. **安全最小闭环**：默认 `tool_output_is_untrusted` + `ignore_instructions_inside_tool_output`；fixture 驱动覆盖提示注入过滤与冲突提示，具备可验证锚点（AC-010/011）。

## 问题与建议

### Major（建议修复）

1. **[M-001] run 模式真实工具执行尚未闭环**：当前主要验收集中在 plan/dry-run 与 fixture 融合；真实工具调用（并发/超时/预算）仍需要补齐实现与证据，避免“只有计划没有执行”的功能落差。  
   - 建议：在后续迭代补齐 run 模式的最小可用实现（至少 `ci_index_status/ci_search/ci_graph_rag`），并用可控的 mock/fixture 或低成本工具完成 deterministic 验收。

### Minor（可选优化）

1. **[m-001] 配置解析可扩展性**：当前 YAML 解析器面向最小键集可用，但对更复杂结构（列表/深层嵌套）不友好。  
   - 建议：后续如需扩展 tool 定义或参数表，可考虑引入更明确的 schema（仍保持无额外依赖），或将复杂结构下沉为 JSON 并在 YAML 中引用。

2. **[m-002] codex-auto run 模式执行路径建议更显式**：当前 run 通过 `eval` 执行 planned command，建议未来增加更严格的参数拼接与 quoting 规则，降低注入风险。  
   - 建议：将 planned command 表达为结构化字段（cmd + argv[]），避免 `eval`。

## 评审结论

**结论：APPROVED WITH COMMENTS**

- plan/dry-run 与入口收敛闭环已完成，测试锚点清晰；建议把 run 模式的最小执行闭环纳入后续增强，以满足“真正自动调用工具”的最终目标。

---
*此报告依据 `devbooks-reviewer` 的职责边界生成（只评审，不直接改测试）。*

