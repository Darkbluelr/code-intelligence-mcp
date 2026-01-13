# Spec: hotspot-analysis

> **Version**: 1.0.0
> **Status**: Active
> **Owner**: Spec Owner
> **Created**: 2026-01-11
> **Last Verified**: 2026-01-11
> **Freshness Check**: 90 days
> **Source Change**: enhance-code-intelligence

---

## Purpose

提供代码热点分析能力，通过 Frequency × Complexity 公式识别项目中最需要关注的文件，辅助 Bug 定位和重构决策。

---

## Requirements

### Requirement: Hotspot Calculation

系统 SHALL 基于 Frequency × Complexity 公式计算代码热点分数。

- Frequency：文件在最近 N 天（默认 30 天）的 git commit 中的变更次数
- Complexity：文件的圈复杂度加权平均值
- 热点分数 = Frequency × Complexity

#### Scenario: Calculate hotspot for single file

- **GIVEN** 一个 TypeScript 文件在过去 30 天内有 10 次提交
- **AND** 该文件的圈复杂度加权平均值为 5
- **WHEN** 执行热点计算
- **THEN** 该文件的热点分数为 50

Trace: AC-001

#### Scenario: Calculate hotspot for project

- **GIVEN** 一个包含 1000 个文件的项目
- **WHEN** 执行热点计算并请求 Top-20
- **THEN** 返回热点分数最高的 20 个文件
- **AND** 计算耗时 < 5 秒

Trace: AC-001

#### Scenario: Hotspot with no git history

- **GIVEN** 一个没有 git 历史的文件
- **WHEN** 执行热点计算
- **THEN** 该文件的 Frequency 视为 0
- **AND** 热点分数为 0

Trace: AC-001

---

### Requirement: Hotspot MCP Tool

系统 SHALL 通过 MCP 工具 `ci_hotspot` 暴露热点分析能力。

#### Scenario: Invoke ci_hotspot with default parameters

- **GIVEN** MCP 服务器运行中
- **WHEN** 调用 `ci_hotspot` 工具，无参数
- **THEN** 返回当前目录 Top-20 热点文件
- **AND** 输出格式为 JSON

Trace: AC-001, AC-008

#### Scenario: Invoke ci_hotspot with custom top_n

- **GIVEN** MCP 服务器运行中
- **WHEN** 调用 `ci_hotspot` 工具，参数 `top_n=10`
- **THEN** 返回 Top-10 热点文件

Trace: AC-001, AC-008

---

## Data Examples

| 文件 | Frequency (30d) | Complexity | Hotspot Score |
|------|-----------------|------------|---------------|
| src/server.ts | 15 | 8 | 120 |
| scripts/bug-locator.sh | 10 | 12 | 120 |
| scripts/embedding.sh | 5 | 6 | 30 |
| scripts/common.sh | 20 | 2 | 40 |
