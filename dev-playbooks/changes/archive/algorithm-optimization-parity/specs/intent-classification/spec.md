# 规格：意图四分类 (Intent Classification)

> **Capability ID**: ALG-011
> **模块**: common.sh
> **类型**: 行为变更（内部算法优化）

## Requirements

### REQ-IC-001: 四分类定义

**描述**: 用户意图分为四个类别，按优先级排序。

| 优先级 | 类别 | 说明 | 关键词模式 |
|--------|------|------|------------|
| 1 | debug | 调试/修复 | fix, debug, bug, crash, fail, error, issue, resolve, problem, broken |
| 2 | refactor | 重构/优化 | refactor, optimize, improve, clean, simplify, quality, performance, restructure |
| 3 | docs | 文档/注释 | doc, comment, readme, explain, guide, 注释, 文档 |
| 4 | feature | 功能（默认） | 其他所有输入 |

---

### REQ-IC-002: 优先级规则

**描述**: 当输入包含多个类别的关键词时，返回优先级最高的类别。

**规则**: debug > refactor > docs > feature

---

### REQ-IC-003: 大小写不敏感

**描述**: 关键词匹配不区分大小写。

**示例**: "Fix bug" 和 "fix BUG" 都匹配 debug 类别

---

### REQ-IC-004: 边界处理

**描述**: 对特殊输入的处理规则。

| 输入 | 返回 |
|------|------|
| 空字符串 | feature |
| 纯空白 | feature |
| 纯特殊字符 | feature |
| 无字母字符 | feature |

---

### REQ-IC-005: 分类准确率

**描述**: 在标准测试集上分类准确率 ≥ 85%。

---

## Scenarios

### SC-IC-001: 纯 debug 意图

- **Given**: 输入 = "fix the authentication bug"
- **When**: 调用 `get_intent_type()` 函数
- **Then**: 返回 "debug"

### SC-IC-002: 纯 refactor 意图

- **Given**: 输入 = "optimize database queries"
- **When**: 调用 `get_intent_type()` 函数
- **Then**: 返回 "refactor"

### SC-IC-003: 纯 docs 意图

- **Given**: 输入 = "write documentation for API"
- **When**: 调用 `get_intent_type()` 函数
- **Then**: 返回 "docs"

### SC-IC-004: 默认 feature 意图

- **Given**: 输入 = "add user registration"
- **When**: 调用 `get_intent_type()` 函数
- **Then**: 返回 "feature"

### SC-IC-005: 优先级冲突 - debug > refactor

- **Given**: 输入 = "fix and optimize the login flow"
- **When**: 调用 `get_intent_type()` 函数
- **Then**: 返回 "debug"（debug 优先级高于 refactor）

### SC-IC-006: 优先级冲突 - refactor > docs

- **Given**: 输入 = "improve and document the API"
- **When**: 调用 `get_intent_type()` 函数
- **Then**: 返回 "refactor"（refactor 优先级高于 docs）

### SC-IC-007: 空字符串

- **Given**: 输入 = ""
- **When**: 调用 `get_intent_type()` 函数
- **Then**: 返回 "feature"

### SC-IC-008: 大小写不敏感

- **Given**: 输入 = "FIX THE BUG"
- **When**: 调用 `get_intent_type()` 函数
- **Then**: 返回 "debug"

### SC-IC-009: 中文关键词

- **Given**: 输入 = "修复登录问题"
- **When**: 调用 `get_intent_type()` 函数
- **Then**: 返回 "debug"（如果支持中文关键词）

### SC-IC-010: 纯特殊字符

- **Given**: 输入 = "!@#$%^&*()"
- **When**: 调用 `get_intent_type()` 函数
- **Then**: 返回 "feature"

---

## Contract Test IDs

| Test ID | 类型 | 覆盖场景 |
|---------|------|----------|
| CT-IC-001 | behavior | SC-IC-001 |
| CT-IC-002 | behavior | SC-IC-002 |
| CT-IC-003 | behavior | SC-IC-003 |
| CT-IC-004 | behavior | SC-IC-004 |
| CT-IC-005 | priority | SC-IC-005 |
| CT-IC-006 | priority | SC-IC-006 |
| CT-IC-007 | boundary | SC-IC-007 |
| CT-IC-008 | behavior | SC-IC-008 |
| CT-IC-009 | i18n | SC-IC-009 |
| CT-IC-010 | boundary | SC-IC-010 |
