# 项目上下文

## 目的
[描述您项目的目标和目的]

## 技术栈
- [列出您的主要技术]
- [例如：TypeScript, React, Node.js]

## 项目约定

### 代码风格
[描述您的代码风格偏好、格式化规则和命名约定]

### 架构模式
[记录您的架构决策和模式]

### 测试策略
[解释您的测试方法和要求]

### Git工作流
[描述您的分支策略和提交约定]

## 领域上下文
[添加AI助手需要了解的领域特定知识]

## 重要约束
[列出任何技术、业务或监管约束]

## 外部依赖
[记录关键的外部服务、API或系统]

---

## DevBooks 集成规则

### Directory Roots（目录根）

- `dev-playbooks/specs/`（当前真理源）
- `dev-playbooks/changes/`（变更包）

### Project Profile（项目画像入口，强烈建议）

- 项目画像（技术栈/命令/约定/闸门）：`dev-playbooks/specs/_meta/project-profile.md`
- 统一语言表（术语）：`dev-playbooks/specs/_meta/glossary.md`
- 架构地图（C4）：`dev-playbooks/specs/architecture/c4.md`

### Truth Sources（真理源优先级）

1. `dev-playbooks/specs/`：当前系统真理（最高优先级）
2. `dev-playbooks/changes/<change-id>/`：本次变更包（proposal/design/tasks/verification/spec deltas）
3. 代码与测试：以仓库事实为准（测试/构建输出是确定性锚点）
4. 聊天记录：非权威，必要时需回写到上述文件

### Agent Roles（角色隔离）

- Design Owner：只写 What/Constraints + AC-xxx（禁止写实现步骤）
- Spec Owner：只写规格 delta（Requirements/Scenarios）
- Planner：只从设计推导 tasks（不得参考 tests/）
- Test Owner：只从设计/规格推导测试（不得参考 tasks/）；**必须独立对话/独立实例**
- Proposal Author：只写 `proposal.md`（含 Debate Packet）
- Proposal Challenger：只出质疑报告（必须给结论）
- Proposal Judge：只出裁决报告（必须明确 Approved/Revise/Rejected）
- Coder：按 tasks 实现并跑闸门（不得反向改写设计意图）；**必须独立对话/独立实例；禁止修改 tests/**，如需调整测试只能交还 Test Owner
- Reviewer：只做可读性/依赖/风格审查；不改 tests/，不改设计
- Impact Analyst：跨模块改动先做影响分析再写代码

### Test Integrity（测试完整性与红绿循环）

- 允许并行，但**测试与实现必须是独立对话**；禁止在同一会话内既写 tests 又写实现。
- Test Owner 先产出 tests/verification，并运行以确认 **Red** 基线；记录失败证据到 `dev-playbooks/changes/<id>/evidence/`（若无证据目录可新建）。
- Coder 仅以 `dev-playbooks/changes/<id>/tasks.md` + 测试报错 + 代码库为输入，目标是让测试 **Green**；严禁修改 tests。

### Structural Quality Guardrails（结构质量守门）

- 若出现"代理指标驱动"的要求（行数/文件数/机械拆分/命名格式），必须评估其对内聚/耦合/可测试性的影响。
- 触发风险信号时必须停线：记录为决策问题并回到 proposal/design 处理，不得直接执行。
- 质量闸门优先级：复杂度、耦合度、依赖方向、变更频率、测试质量 > 代理指标。

### Definition of Done（DoD，MECE）

每次变更至少声明覆盖到哪些闸门；缺失项必须写原因与补救计划（建议写入 `dev-playbooks/changes/<id>/verification.md`）：
- 行为（Behavior）：unit/integration/e2e（按项目类型最小集）
- 契约（Contract）：OpenAPI/Proto/Schema/事件 envelope + contract tests
- 结构（Structure）：架构适配函数（依赖方向/分层/禁止循环）
- 静态与安全（Static/Security）：lint/typecheck/build + SAST/secret scan
- 证据（Evidence，按需）：截图/录像/报告

### DevBooks Skills（开发作战手册 Skills）

本项目使用 DevBooks 的 `devbooks-*` Skills（全局安装后在所有项目可用）：

**角色类：**
- Router（下一步路由）：`devbooks-router` → 给出阶段判断 + 下一步该用哪个 Skill + 产物落点（支持 Prototype 模式）
- Design（设计文档）：`devbooks-design-doc` → `dev-playbooks/changes/<id>/design.md`
- Spec & Contract（规格与契约）：`devbooks-spec-contract` → `dev-playbooks/changes/<id>/specs/<capability>/spec.md` + 契约计划
- Plan（编码计划）：`devbooks-implementation-plan` → `dev-playbooks/changes/<id>/tasks.md`
- Test（测试与追溯）：`devbooks-test-owner` → `dev-playbooks/changes/<id>/verification.md` + `tests/**`
- Proposal Author（提案撰写）：`devbooks-proposal-author` → `dev-playbooks/changes/<id>/proposal.md`
- Proposal Challenger（提案质疑）：`devbooks-proposal-challenger` → 质疑报告（不写入变更包）
- Proposal Judge（提案裁决）：`devbooks-proposal-judge` → 裁决报告（写回 `proposal.md`）
- Coder（实现）：`devbooks-coder` → 实现与验证（不改 tests）
- Reviewer（代码评审）：`devbooks-code-review` → Review Notes（不写入变更包）
- Garden（规格园丁）：`devbooks-spec-gardener` → 归档前修剪 `dev-playbooks/specs/`
- Impact（影响分析）：`devbooks-impact-analysis` → 写入 `dev-playbooks/changes/<id>/proposal.md` 的 Impact 部分
- C4 map（架构地图）：`devbooks-c4-map` → `dev-playbooks/specs/architecture/c4.md`
- Backport（回写设计）：`devbooks-design-backport` → 回写 `dev-playbooks/changes/<id>/design.md`

**工作流类：**
- Workflow（交付验收骨架）：`devbooks-delivery-workflow` → 变更闭环 + 确定性脚本
- Proposal Debate（提案对辩工作流）：`devbooks-proposal-debate-workflow` → Author/Challenger/Judge 三角对辩
- Brownfield Bootstrap（存量初始化）：`devbooks-brownfield-bootstrap` → 当 `dev-playbooks/specs/` 为空时生成项目画像与基线

**度量类：**
- Entropy Monitor（熵度量）：`devbooks-entropy-monitor` → 系统熵度量 → `dev-playbooks/specs/_meta/entropy/`

### OpenSpec 三阶段与 DevBooks 角色映射

> OpenSpec 有 proposal/apply/archive 三阶段命令。DevBooks 为每个阶段提供角色隔离与质量闸门。

#### 阶段一：Proposal（禁止写实现代码）

**命令**：`/openspec:proposal <描述>` 或 `/devbooks-openspec-proposal`

**可用角色与 Skills**：
| 角色 | Skill | 产物 |
|------|-------|------|
| Router | `devbooks-router` | 阶段判断 + 下一步建议 |
| Proposal Author | `devbooks-proposal-author` | `proposal.md`（Why/What/Impact + Debate Packet）|
| Proposal Challenger | `devbooks-proposal-challenger` | 质疑报告（风险/遗漏/不一致）|
| Proposal Judge | `devbooks-proposal-judge` | 裁决报告（Approved/Revise/Rejected → 写回 proposal.md）|
| Design Owner | `devbooks-design-doc` | `design.md`（What/Constraints + AC-xxx）|
| Spec & Contract Owner | `devbooks-spec-contract` | `specs/<capability>/spec.md` + 契约计划 |
| Planner | `devbooks-implementation-plan` | `tasks.md`（编码计划，不得参考 tests/）|
| Impact Analyst | `devbooks-impact-analysis` | 影响分析（写入 proposal.md 的 Impact 部分）|

---

#### 阶段二：Apply（角色隔离，必须指定角色）

**命令**：`/openspec:apply <role> <change-id>` 或 `/devbooks-openspec-apply <role> <change-id>`

**关键约束**：
- **必须指定角色**：test-owner / coder / reviewer
- **未指定角色时**：显示菜单等待用户选择，**禁止自动执行**
- **角色隔离**：Test Owner 与 Coder 必须独立对话/独立实例

**可用角色与 Skills**：
| 角色 | Skill | 产物 | 约束 |
|------|-------|------|------|
| Test Owner | `devbooks-test-owner` | `verification.md` + `tests/**` | 先跑 Red 基线，记录证据到 `evidence/` |
| Coder | `devbooks-coder` | 实现代码 | **禁止修改 tests/**，以测试为唯一完成判据 |
| Reviewer | `devbooks-code-review` | 评审意见 | 只做可读性/依赖/风格审查，不改代码 |

---

#### 阶段三：Archive（规格合并与归档）

**命令**：`/openspec:archive <change-id>` 或 `/devbooks-openspec-archive`

**可用角色与 Skills**：
| 角色 | Skill | 产物 |
|------|-------|------|
| Spec Gardener | `devbooks-spec-gardener` | 修剪后的 `dev-playbooks/specs/`（去重/合并/删除过时）|
| Design Backport | `devbooks-design-backport` | 回写 `design.md`（实现中发现的新约束/冲突）|

---

### C4（架构地图）

- 权威 C4 地图：`dev-playbooks/specs/architecture/c4.md`
- 每次变更的设计文档只写 C4 Delta（本次新增/修改/移除哪些元素）
