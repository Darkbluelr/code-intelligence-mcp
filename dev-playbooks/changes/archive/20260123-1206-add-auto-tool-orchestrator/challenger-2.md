# Challenger Attempt #2：自动工具编排的注入可见性与信息密度复核

> Change ID：`20260123-1206-add-auto-tool-orchestrator`  
> 关注点：Claude/Codex 入口可用性、注入是否“摘要+溯源+片段”、Graph‑RAG 检索质量是否退化

## 结论（本轮挑战裁决）

- **主要阻断已解除**：Claude Code “看不到注入上下文/工具”的根因在安装链路（`settings.json` 指向旧 hook + 新脚本未被正确安装/委托）与注入内容过度摘要化；两者均已补齐为可工作的链路与更高信息密度的上下文块。
- **仍有残余风险**：注入片段的相关性与安全过滤粒度仍偏粗；全局安装/入口脚本在“符号链接/路径解析”场景存在潜在坑点（本轮已补关键修复，但建议后续补端到端安装验收）。

## 发现的问题（对应 proposal/design 的承诺缺口）

### 1) Claude Code 触发链路不成立（导致“根本没有实现”）

**现象**：`~/.claude/settings.json` 仍指向 `~/.claude/hooks/augment-context-global.sh`，且该脚本是旧版独立实现，并未委托到本仓库的 `hooks/context-inject-global.sh`/`hooks/auto-tool-orchestrator.sh`。  
**影响**：Claude Code 实际没有运行 Orchestrator，用户自然看不到 `[Auto Tools]` 计划/结果或注入的上下文块。  
**与设计冲突**：proposal “设计要点 1：hooks 关系与调用链”明确要求 `~/.claude/hooks/context-inject-global.sh -> hooks/context-inject-global.sh -> hooks/auto-tool-orchestrator.sh`。

### 2) 注入内容只有概览摘要，对模型“几乎无用”

**现象**：`hookSpecificOutput.additionalContext` 过去主要是 `tool_results[].summary` 的一行拼接，缺少“溯源 + 片段”，不满足 proposal “默认只回填摘要 + 溯源 + 片段（严格限额）”的承诺。  
**影响**：模型拿不到可直接阅读/定位的代码片段，无法缩短“打开文件、找函数”的往返轮次。  

### 3) Graph‑RAG 语义检索退化（隐性降低注入质量）

**现象**：`scripts/graph-rag-retrieval.sh` 引用不存在的 `devbooks-embedding.sh`，导致向量检索不可用并回退到关键词路径；候选质量降低，进而降低注入价值密度。  

### 4) 全局安装（--global）在符号链接场景下可能失效

**现象**：`install.sh --global` 使用 `ln -sf`，但 `bin/ci-search`/`bin/codex-auto` 等脚本依赖 `SCRIPT_DIR` 相对定位；若通过 symlink 执行，`SCRIPT_DIR` 会变成 `/usr/local/bin`，相对路径失效。  
**影响**：用户以为“已全局安装”，实际运行时找不到脚本/编排器。  

## 本轮已修复（满足设计承诺的关键补丁）

### A) Claude Code 可见触发：安装链路自愈

- `install.sh`：`--with-hook` 现在会安装 `~/.claude/hooks/context-inject-global.sh`（**launcher**，委托到本仓库真实脚本）以及 `~/.claude/hooks/augment-context-global.sh`（兼容 wrapper），避免既有 settings 仍指向 augment 时失效。
- `hooks/context-inject-global.sh`：补齐 PATH（Homebrew 路径），降低 Claude Code 非交互环境下 `jq/rg` 不可见导致“空注入”的概率。

### B) 注入信息密度：从“摘要”升级为“摘要+片段”

- `hooks/auto-tool-orchestrator.sh`：基于 `ci_graph_rag`/`ci_search` 的结构化输出提取候选文件，并在 `max_files=3`、`max_lines_per_snippet=20`、`max_total_chars=6000` 的限额内回填 **实际代码片段**；同时把片段元信息写入 `task_context.relevant_snippets`。
- 片段读取受 **repo-root 约束**、**敏感路径过滤**（`.env`/`*.pem`/`id_rsa*`/`.ssh`/`secrets`/`.npmrc` 等）与 **脱敏**/注入文本粗过滤约束，降低泄露与提示注入风险。

### C) Graph‑RAG 语义检索修复

- `scripts/graph-rag-retrieval.sh`：切换为使用本仓库 `scripts/embedding.sh --format json`，并将其 `candidates[{file,score}]` 映射到 Graph‑RAG 期望的 `{file_path,relevance_score}`，减少“向量路径缺失”导致的降级。

### D) 全局安装可用性：symlink 解析

- `bin/ci-search`、`bin/codex-auto`：增加 symlink 解析逻辑，确保 `SCRIPT_DIR` 指向真实安装目录而非 `/usr/local/bin`。
- `bin/code-intelligence-mcp`：用 `realpathSync(import.meta.url)` 计算真实路径，避免 symlink 下 `../dist/server.js` 解析错误。

## 仍存风险 / 未覆盖场景（后续建议）

1) **片段相关性**：当前片段选择策略以“候选文件 +（可选）关键词命中行”驱动，仍可能回填文件头部而非最相关函数体；建议后续把 Graph‑RAG 的子图节点（若带 line range）纳入片段切片依据，或在 embedding 输出中携带 hit 行号。
2) **提示注入过滤粒度**：`should_filter_injection` 为粗规则（且大小写/变体覆盖有限），建议引入更细粒度的行级过滤与“仅过滤可疑行、不丢整段”的策略。
3) **安装端到端验收**：建议新增一条“安装后 Claude Code 必然可见”的最小验收脚本（读取 `~/.claude/settings.json` + hooks 文件存在性 + 运行一次 hook dry-run），避免再次出现“安装成功但不生效”的体验回归。

## 建议的快速验证命令（人工冒烟）

- 注入是否包含片段：  
  `echo '{"prompt":"graph rag implementation"}' | hooks/context-inject-global.sh | jq -r '.hookSpecificOutput.additionalContext'`
- Orchestrator 是否输出 `relevant_snippets`：  
  `echo '{"prompt":"graph rag implementation"}' | hooks/auto-tool-orchestrator.sh | jq -c '.task_context.relevant_snippets'`
- Claude 安装链路（不依赖手改 settings）：  
  `./install.sh --with-hook --skip-deps`

