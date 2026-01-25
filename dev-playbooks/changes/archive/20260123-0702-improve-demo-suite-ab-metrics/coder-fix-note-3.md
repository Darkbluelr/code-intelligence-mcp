# Coder Fix Note 3

## 修复的 Major 点

- 统一“最小骨架”表述：脚本/指南改为描述当前已实现的产物闭合与边界能力，并注明未覆盖的真实基准/AI 自动化。
- 对齐降级兜底：当状态非 success 时生成 `degraded/metrics.json` 与 `degraded/report.md`，保持与本次运行的 status/reasons/missing_fields 一致，且不影响 `single/` 与 `ab-*` 目录。
- 明确 TMPDIR 策略：运行期 `TMPDIR` 绑定到 `<out-dir>/.tmp`，与 `metrics.json.write_boundary.tmp_dir` 一致，避免 `mktemp` 污染系统 `/tmp`。
- 降低诊断锚点耦合：锚点文件与符号改为可配置（CLI/环境变量），并写入 `metrics.json` 与 `report.md`；同时为 `eval` 增加前缀白名单校验与安全前提说明。
- 文档/README 对齐：更新 spec 真理源路径、降级目录语义、A/B/简单-复杂叙事与依赖矩阵，补充 `ci-search` 与 `ci_search` 的关系说明。

## 涉及文件

- `demo/demo-suite.sh`
- `demo/DEMO-GUIDE.md`
- `dev-playbooks/docs/长期可复用演示方案.md`
- `README.zh-CN.md`

## 验证命令

- `shellcheck demo/*.sh`（退出码 0，无输出）
- `demo/demo-suite.sh --help`（退出码 0，确认帮助文案与能力一致）
