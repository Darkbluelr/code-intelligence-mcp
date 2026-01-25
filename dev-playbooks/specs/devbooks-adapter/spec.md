---
last_referenced_by: augment-parity-final-gaps
last_verified: 2026-01-16
health: active
---


# Spec: DevBooks 适配（devbooks-adapter）

> **Change ID**: `augment-parity-final-gaps`
> **Capability**: devbooks-adapter
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-16

---

## 概述

本规格定义 DevBooks 适配功能。系统应能够：
1. 自动检测 DevBooks 配置
2. 提取高信噪比信息增强代码智能
3. 将 DevBooks 上下文注入到结构化输出中

---

## Requirements（需求）

### REQ-DBA-001：DevBooks 配置检测

系统应按以下优先级检测 DevBooks 配置：

| 优先级 | 检测方式 | 配置文件 |
|--------|----------|----------|
| 1（最高） | `.devbooks/config.yaml` 存在 | 解析 `root` 字段获取真理目录 |
| 2 | `dev-playbooks/project.md` 存在 | 使用 `dev-playbooks/` 作为真理目录 |
| 3 | `openspec/project.md` 存在 | 使用 `openspec/` 作为真理目录 |
| 4（最低） | `.openspec/project.md` 存在 | 使用 `.openspec/` 作为真理目录 |

**约束**：
- 按优先级顺序检测，找到后停止
- 未检测到时返回空，不报错
- 检测结果缓存 60 秒

### REQ-DBA-002：高信噪比信息提取

系统应从 DevBooks 真理目录提取以下高信噪比信息：

| 信息类别 | 文件路径 | 提取内容 |
|----------|----------|----------|
| 项目画像 | `specs/_meta/project-profile.md` | 技术栈、架构模式、命令速查 |
| 术语表 | `specs/_meta/glossary.md` | 领域术语、同义词、禁用词 |
| 架构约束 | `specs/architecture/c4.md` | 分层规则、依赖方向、禁止依赖 |
| 当前变更 | `changes/*/proposal.md` | 变更状态、验收标准、当前焦点 |

### REQ-DBA-003：项目画像提取

系统应从 `project-profile.md` 提取以下字段：

```json
{
  "name": "项目名称",
  "tech_stack": ["Node.js", "TypeScript", "Bash"],
  "architecture": "thin-shell",
  "key_commands": {
    "build": "npm run build",
    "test": "npm test",
    "lint": "npm run lint"
  },
  "constraints": [
    "CON-TECH-002: MCP Server 使用 Node.js 薄壳调用 Shell 脚本"
  ]
}
```

**提取规则**：
- 从 `## 第一层：快速定位` 章节提取命令
- 从 `## 约束` 章节提取约束
- 从 `## 技术栈` 章节提取技术栈

### REQ-DBA-004：术语表集成

系统应集成术语表用于搜索增强：

**用途**：
- 同义词扩展：查询 `auth` 时扩展为 `authentication, 认证`
- 禁用词过滤：过滤 `deprecated terms`
- 缩写解析：`MCP` → `Model Context Protocol`

**格式**：
```markdown
## 术语

| 术语 | 同义词 | 说明 |
|------|--------|------|
| MCP | Model Context Protocol | AI 与工具通信协议 |
| 薄壳 | thin-shell | 架构模式 |
```

### REQ-DBA-005：架构约束提取

系统应从 `c4.md` 提取架构约束：

**提取内容**：
- 分层规则（Layering Constraints）
- 依赖方向（Dependency Direction）
- 禁止依赖（Forbidden Dependencies）

**输出格式**：
```json
{
  "layers": ["shared", "core", "integration"],
  "direction": "shared ← core ← integration",
  "forbidden": [
    "scripts/*.sh → src/*.ts",
    "common.sh → 功能脚本"
  ]
}
```

### REQ-DBA-006：当前变更包检测

系统应检测当前活跃的变更包：

**检测规则**：
1. 扫描 `changes/` 目录下的子目录
2. 读取每个 `proposal.md` 的 Status 字段
3. Status 为 `Pending` 或 `Approved` 的视为活跃

**输出**：
```json
{
  "active_changes": [
    {
      "id": "augment-parity-final-gaps",
      "status": "Approved",
      "title": "补齐 Augment 对等最后差距"
    }
  ]
}
```

### REQ-DBA-007：上下文注入

系统应将 DevBooks 上下文注入到结构化输出的相应字段：

| DevBooks 信息 | 注入目标 |
|---------------|----------|
| 项目画像 | `project_profile` |
| 架构约束 | `constraints.architectural` |
| 当前变更 | `task_context` 或单独字段 |
| 术语表 | 搜索时自动应用 |

### REQ-DBA-008：降级处理

当 DevBooks 不可用或部分文件缺失时，系统应优雅降级：

| 场景 | 降级行为 |
|------|----------|
| 无 DevBooks 配置 | 跳过 DevBooks 增强，使用基础上下文 |
| `project-profile.md` 缺失 | 从 `package.json` 推断项目画像 |
| `c4.md` 缺失 | 跳过架构约束注入 |
| `glossary.md` 缺失 | 跳过术语扩展 |

**约束**：
- 降级时记录 INFO 日志
- 不报错，不中断处理

---

## Scenarios（场景）

### SC-DBA-001：检测 .devbooks/config.yaml

**Given**:
- 存在 `.devbooks/config.yaml`
- 内容包含 `root: dev-playbooks`
**When**: 执行 DevBooks 检测
**Then**:
- 检测到 DevBooks 配置
- 真理目录设为 `dev-playbooks/`
- 返回检测结果

### SC-DBA-002：检测 dev-playbooks/project.md

**Given**:
- 无 `.devbooks/config.yaml`
- 存在 `dev-playbooks/project.md`
**When**: 执行 DevBooks 检测
**Then**:
- 检测到 DevBooks 配置
- 真理目录设为 `dev-playbooks/`

### SC-DBA-003：无 DevBooks 配置

**Given**:
- 无任何 DevBooks 配置文件
**When**: 执行 DevBooks 检测
**Then**:
- 返回检测结果：未检测到
- 不报错
- 降级使用基础上下文

### SC-DBA-004：提取项目画像

**Given**:
- 存在 `dev-playbooks/specs/_meta/project-profile.md`
**When**: 提取项目画像
**Then**:
- 提取技术栈
- 提取架构模式
- 提取关键约束
- 返回 JSON 格式画像

### SC-DBA-005：提取架构约束

**Given**:
- 存在 `dev-playbooks/specs/architecture/c4.md`
- C4 文档包含分层约束章节
**When**: 提取架构约束
**Then**:
- 提取分层规则
- 提取依赖方向
- 提取禁止依赖

### SC-DBA-006：检测活跃变更包

**Given**:
- `changes/` 目录包含 2 个变更包
- 1 个 Status=Approved，1 个 Status=Archived
**When**: 检测活跃变更包
**Then**:
- 返回 1 个活跃变更包
- 不返回 Archived 状态的变更包

### SC-DBA-007：术语表同义词扩展

**Given**:
- 术语表包含 `MCP | Model Context Protocol`
- 用户查询 `MCP`
**When**: 执行搜索
**Then**:
- 自动扩展查询为 `MCP OR "Model Context Protocol"`
- 返回更多相关结果

### SC-DBA-008：project-profile.md 缺失降级

**Given**:
- DevBooks 配置存在
- `specs/_meta/project-profile.md` 不存在
- `package.json` 存在
**When**: 提取项目画像
**Then**:
- 从 `package.json` 推断项目名称
- 从依赖推断技术栈
- 记录 INFO 日志：`project-profile.md 缺失，从 package.json 降级推断`

### SC-DBA-009：上下文注入

**Given**:
- DevBooks 检测成功
- 项目画像和架构约束已提取
**When**: 构建结构化输出
**Then**:
- `project_profile` 字段填充 DevBooks 画像
- `constraints.architectural` 字段填充架构约束
- 输出 JSON 有效

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-DBA-001 | SC-DBA-001, SC-DBA-002, SC-DBA-003 | AC-G12 |
| REQ-DBA-002 | SC-DBA-004, SC-DBA-005, SC-DBA-006 | AC-G12 |
| REQ-DBA-003 | SC-DBA-004 | AC-G12 |
| REQ-DBA-004 | SC-DBA-007 | AC-G12 |
| REQ-DBA-005 | SC-DBA-005 | AC-G12 |
| REQ-DBA-006 | SC-DBA-006 | AC-G12 |
| REQ-DBA-007 | SC-DBA-009 | AC-G12 |
| REQ-DBA-008 | SC-DBA-003, SC-DBA-008 | AC-G12 |

---

## Contract Test IDs

| Test ID | 类型 | 覆盖需求/场景 | 说明 |
|---------|------|---------------|------|
| CT-DBA-001 | behavior | REQ-DBA-001, SC-DBA-001 | config.yaml 检测 |
| CT-DBA-002 | behavior | REQ-DBA-001, SC-DBA-002 | project.md 检测 |
| CT-DBA-003 | behavior | REQ-DBA-001, SC-DBA-003 | 无配置降级 |
| CT-DBA-004 | behavior | REQ-DBA-003, SC-DBA-004 | 项目画像提取 |
| CT-DBA-005 | behavior | REQ-DBA-005, SC-DBA-005 | 架构约束提取 |
| CT-DBA-006 | behavior | REQ-DBA-006, SC-DBA-006 | 活跃变更检测 |
| CT-DBA-007 | behavior | REQ-DBA-008, SC-DBA-008 | 降级处理 |
| CT-DBA-008 | behavior | REQ-DBA-007, SC-DBA-009 | 上下文注入 |

---

## 命令行接口（CLI）

新增到 `common.sh`：

```bash
# 检测 DevBooks 配置
detect_devbooks() {
  # 返回真理目录路径，未检测到返回空
}

# 加载 DevBooks 上下文
load_devbooks_context() {
  local devbooks_root="$1"
  # 返回 JSON 格式上下文
}
```

新增到 `augment-context-global.sh`：

```bash
# 带 DevBooks 增强的上下文构建
build_enhanced_context() {
  # 检测 DevBooks
  # 提取高信噪比信息
  # 注入到结构化输出
}
```
