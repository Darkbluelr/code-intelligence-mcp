# Spec: intent-analysis

> **Version**: 1.0.0
> **Status**: Active
> **Owner**: Spec Owner
> **Created**: 2026-01-11
> **Last Verified**: 2026-01-11
> **Freshness Check**: 90 days
> **Source Change**: enhance-code-intelligence

---

## Purpose

提供 4 维意图信号分析能力，从显式、隐式、历史、代码四个维度提取用户意图，增强上下文注入的精准度。

---

## Requirements

### Requirement: Four-Dimensional Intent Analysis

系统 SHALL 聚合 4 个维度的意图信号来理解用户意图：

1. **显式信号（Explicit）**：用户 Prompt 中的关键词和语义
2. **隐式信号（Implicit）**：当前文件、光标位置、选中内容
3. **历史信号（Historical）**：最近 5 次编辑记录、访问文件
4. **代码信号（Code）**：AST 上下文（所在函数/类/模块）

#### Scenario: Analyze intent with explicit keywords

- **GIVEN** 用户 Prompt 包含 "fix authentication bug"
- **WHEN** 执行意图分析
- **THEN** 显式信号输出包含 `["fix", "authentication", "bug"]`
- **AND** 信号类型标记为 `explicit`

Trace: AC-002

#### Scenario: Analyze intent with implicit context

- **GIVEN** 用户当前打开文件为 `src/auth/login.ts`
- **AND** 光标位于第 42 行
- **WHEN** 执行意图分析
- **THEN** 隐式信号输出包含 `file: src/auth/login.ts`
- **AND** 隐式信号输出包含 `line: 42`
- **AND** 信号类型标记为 `implicit`

Trace: AC-002

#### Scenario: Analyze intent with historical context

- **GIVEN** 用户最近 5 次编辑了 `auth/*.ts` 相关文件
- **WHEN** 执行意图分析
- **THEN** 历史信号输出包含最近 5 个编辑文件路径
- **AND** 信号类型标记为 `historical`

Trace: AC-002

#### Scenario: Analyze intent with code context

- **GIVEN** 光标位于函数 `validateToken()` 内部
- **AND** 该函数属于类 `AuthService`
- **WHEN** 执行意图分析
- **THEN** 代码信号输出包含 `function: validateToken`
- **AND** 代码信号输出包含 `class: AuthService`
- **AND** 信号类型标记为 `code`

Trace: AC-002

---

### Requirement: Intent Signal Aggregation

系统 SHALL 将 4 维信号聚合为统一的意图向量，用于检索排序。

#### Scenario: Aggregate signals with weights

- **GIVEN** 4 维信号均已提取
- **WHEN** 执行信号聚合
- **THEN** 输出聚合意图向量
- **AND** 每个信号维度有对应权重（权重 ∈ [0, 1]）

Trace: AC-002

#### Scenario: Aggregate with missing signals

- **GIVEN** 仅有显式信号（无历史、无代码上下文）
- **WHEN** 执行信号聚合
- **THEN** 缺失维度权重设为 0
- **AND** 仅使用可用信号进行聚合

Trace: AC-002

---

## Data Examples

| 维度 | 信号示例 | 默认权重 |
|------|----------|----------|
| explicit | `["fix", "bug", "login"]` | 0.4 |
| implicit | `{file: "auth.ts", line: 42}` | 0.3 |
| historical | `["auth.ts", "user.ts", "session.ts"]` | 0.2 |
| code | `{function: "login", class: "AuthService"}` | 0.1 |
