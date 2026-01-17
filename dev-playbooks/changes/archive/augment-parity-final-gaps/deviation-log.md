# 偏离日志

## 待回写记录

| 时间 | 类型 | 描述 | 涉及文件 | 已回写 |
|------|------|------|----------|:------:|
| 2026-01-16 16:53 | DESIGN_GAP | 规格定义 bug-locator.sh 使用 locate 子命令，但现有 CLI 仅支持 --error；新增测试按 --error + --with-impact 编写，需澄清最终 CLI 契约（已回写设计） | tests/bug-locator.bats | ✅ |
| 2026-01-16 | CONSTRAINT_CHANGE | 规格 REQ-BLF-002 定义 --with-impact 输出为纯数组格式，但为保持向后兼容（REQ-BLF-006），实现保持 `{schema_version, candidates:[...]}` 对象格式；测试需按对象格式更新 jq 表达式 | specs/bug-locator-fusion/spec.md, tests/bug-locator.bats | ✅ |

---

## 归档批次记录

| 归档时间 | 批次 | 回写内容 |
|----------|------|----------|
| 2026-01-16 | archiver-001 | REQ-BLF-002, REQ-BLF-006, JSON Schema 更新为对象包装格式 |
