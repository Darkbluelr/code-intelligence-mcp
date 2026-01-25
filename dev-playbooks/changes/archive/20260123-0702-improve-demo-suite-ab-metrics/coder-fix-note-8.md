# coder-fix-note-8

## 变更说明

- 新增 `docs/demos/README.md`，补齐公开归档约束、run-id 命名规范、推荐目录结构示例、rsync 示例、自检清单与敏感信息扫描建议。

## 最小验证

- `test -f docs/demos/README.md`
- `rg -n "敏感信息扫描" docs/demos/README.md`
