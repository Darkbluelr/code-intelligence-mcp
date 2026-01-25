# Code Review Report: 20260123-0702-improve-demo-suite-ab-metrics（第 1 次）

## 概览

- 评审日期：2026-01-24
- 评审范围：`demo/demo-suite.sh`、`demo/DEMO-GUIDE.md`、`docs/demos/README.md`
- 代码变更类型：演示编排脚本 + 文档（不触达 `src/`、不改变业务逻辑）

## 主要优点

1. **入口与失败语义清晰**：`demo/demo-suite.sh` 使用 `set -euo pipefail`，并通过 `die()` 统一错误出口；`--dry-run` 支持快速确认 out-dir。  
2. **安全边界意识强**：对 out-dir 做非空/`.`/`..` 检查，并拒绝路径组件为符号链接；同时提供 `write-boundary/` 证据与扫描结果，便于审计。  
3. **可复核产物契约**：`metrics.json`/`compare.json` 生成后用 `jq -e .` 做结构校验（当 `jq` 存在时），并将 `ai_ab.status` 与 `skipped_reason` 显式落盘。  
4. **资源清理可预期**：A/B 版本通过 `git worktree` 隔离，并使用 `trap cleanup_worktrees EXIT` 做兜底清理，降低污染风险。  

## 问题与建议

### Major（建议修复）

1. **[M-001] out-dir 极端值风险**：当前允许 `--out-dir /` 等高风险路径（会在根目录下创建 `.tmp/.worktrees/...`）。  
   - 建议：在 `assert_out_dir_safe()` 增加最小保护（至少拒绝 `/`），并在 `--help` 明确“建议 out-dir 位于仓库目录下或 DevBooks evidence 目录”。  

### Minor（可选优化）

1. **[m-001] 代码重复可抽象**：`single/ab-version/ab-config` 三段存在类似的数组过滤、reasons 组装逻辑。  
   - 建议：抽出 1~2 个小函数（如 `filter_non_empty_array`、`merge_unique_reasons`）降低重复与后续维护成本。  

2. **[m-002] AI A/B 的“skipped 但生成占位 scorecard”可能引发误读**：当前 `init_ai_ab_scorecards()` 无条件生成占位 `scorecard.json`，但 `metrics.json.ai_ab.status="skipped"`。  
   - 建议：在 `report.md` 中进一步强调“占位文件仅用于手工步骤对接，不代表已执行”，或在未来迭代将生成动作改为 `--ai-ab` 显式触发。  

## 依赖健康检查（抽样）

- `demo/demo-suite.sh` 依赖：`bash`（必需），`jq/git/shellcheck/sqlite3`（按需降级或 fail-fast），无新增 npm 依赖。  
- 未发现循环依赖或跨层引入（脚本不依赖 `src/`，符合薄壳约束）。  

## 评审结论

**结论：APPROVED WITH COMMENTS**

- 不阻断归档；建议在下一次迭代优先补上 out-dir 极端值保护（M-001）。  
- `verification.md` 当前已为 `Status: Done`，无需变更。  

---
*此报告依据 `devbooks-reviewer` 的职责边界生成（只评审，不直接改代码）。*

