# Coder 修复记录 7

- 恢复动作：重建 `docs/demos/` 并恢复 `docs/demos/README.md` 的公开归档说明内容。
- 防止再次被清理：执行 `git add docs/demos/README.md`，将交付文件加入索引。
- 验证命令：
  - `test -f docs/demos/README.md`
  - `rg -n "敏感信息扫描" docs/demos/README.md`
