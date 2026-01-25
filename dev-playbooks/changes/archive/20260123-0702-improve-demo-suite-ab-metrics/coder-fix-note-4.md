# coder-fix-note-4

## 重复收敛
- 抽取 compare 共享流程：阈值加载、输入元信息读取、单指标 verdict 计算、compare.json/compare.md 输出统一收敛。
- ab-config 的 variable_drift 仍在通用判定后覆盖 overall_verdict 并追加 reasons，保持既有语义不变。

## 文档一致性补充
- 在 `docs/demos/README.md` 增加“可选的敏感信息扫描”建议（token/密钥模式、绝对路径/用户名等）。

## 验证
- `shellcheck demo/*.sh`：退出码 0（无输出）
