<!-- DEVBOOKS:START -->
# DevBooks 使用说明

这些说明适用于 兼容 AGENTS.md 的 AI 工具。

## DevBooks 协议发现与约束

- **配置发现**：在回答任何问题或写任何代码前，按以下顺序查找配置：
  1. `.devbooks/config.yaml`（如存在）→ 解析并使用其中的映射
  2. `dev-playbooks/project.md`（如存在）→ DevBooks 协议
- 找到配置后，先阅读 `agents_doc`（规则文档），再执行任何操作。
- Test Owner 与 Coder 必须独立对话/独立实例；Coder 禁止修改 tests/。
- 任何新功能/破坏性变更/架构改动：必须先创建 `dev-playbooks/changes/<id>/`。

## 工作流命令

| 命令 | 说明 |
|------|------|
| `/devbooks:proposal` | 创建变更提案 |
| `/devbooks:design` | 创建设计文档 |
| `/devbooks:apply <role>` | 执行实现（test-owner/coder/reviewer） |
| `/devbooks:archive` | 归档变更包 |

<!-- DEVBOOKS:END -->
