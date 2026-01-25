# Spec: CI/CD 架构检查集成（ci-cd-integration）

> **Change ID**: `augment-parity-final-gaps`
> **Capability**: ci-cd-integration
> **Version**: 1.0.0
> **Status**: Draft
> **Created**: 2026-01-16

---

## 概述

本规格定义 CI/CD 架构检查集成功能。系统应提供：
1. GitHub Action 模板：PR 自动架构检查
2. GitLab CI 模板：Merge Request 架构检查
3. 检查项：循环依赖、孤儿模块、架构规则违规

---

## Requirements（需求）

### REQ-CI-001：GitHub Action 模板

系统应提供 GitHub Action 工作流模板：

**文件位置**：`.github/workflows/arch-check.yml`

**触发条件**：
- Pull Request 到 `master` 或 `main` 分支
- 手动触发（workflow_dispatch）

**执行环境**：
- `ubuntu-latest`
- Node.js 18

### REQ-CI-002：检查项

GitHub Action 应执行以下检查：

| 检查项 | 脚本 | 失败条件 | 严重级别 |
|--------|------|----------|----------|
| 循环依赖 | `dependency-guard.sh --cycles` | 存在任何循环 | error |
| 孤儿模块 | `dependency-guard.sh --orphan-check` | 存在孤儿（警告） | warning |
| 架构规则 | `boundary-detector.sh detect` | 存在违规 | error |

### REQ-CI-003：检查输出

检查结果应以 JSON 格式输出，支持 CI 解析：

```json
{
  "check": "cycles",
  "status": "pass|fail",
  "findings": [
    {
      "type": "cycle",
      "nodes": ["A", "B", "C", "A"],
      "severity": "error"
    }
  ]
}
```

### REQ-CI-004：PR 评论

检查失败时应在 PR 上添加评论：

**评论内容**：
```markdown
## Architecture Check Failed

Please review the architecture violations in the workflow logs.

### Findings:
- ❌ Circular dependency: A → B → C → A
- ⚠️ Orphan module: src/legacy/unused.ts
```

### REQ-CI-005：GitLab CI 模板

系统应提供 GitLab CI 模板：

**文件位置**：`.gitlab-ci.yml.template`

**说明**：用户需复制为 `.gitlab-ci.yml` 以启用。

### REQ-CI-006：模板配置

模板应支持以下配置（通过环境变量）：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ARCH_CHECK_FAIL_ON_WARNING` | false | 警告是否导致失败 |
| `ARCH_CHECK_RULES_FILE` | `config/arch-rules.yaml` | 架构规则文件 |
| `ARCH_CHECK_IGNORE_PATTERNS` | 空 | 忽略的文件模式 |

### REQ-CI-007：语法验证

GitHub Action 模板应通过 `actionlint` 验证：

```bash
actionlint .github/workflows/arch-check.yml
# 退出码 0 表示语法正确
```

---

## Scenarios（场景）

### SC-CI-001：GitHub Action 触发

**Given**:
- 存在 `.github/workflows/arch-check.yml`
**When**: 创建 Pull Request 到 master 分支
**Then**:
- 自动触发 arch-check 工作流
- 执行所有检查项
- 显示检查状态

### SC-CI-002：循环依赖检测失败

**Given**:
- 代码存在循环依赖 A → B → C → A
**When**: 执行 arch-check 工作流
**Then**:
- 循环依赖检测失败
- 工作流状态为 Failed
- 输出循环依赖详情
- PR 评论指出问题

### SC-CI-003：孤儿模块检测（警告）

**Given**:
- 代码存在孤儿模块 `src/legacy/unused.ts`
**When**: 执行 arch-check 工作流
**Then**:
- 孤儿模块检测为警告
- 工作流状态为 Success（默认警告不失败）
- 输出孤儿模块列表
- PR 评论包含警告信息

### SC-CI-004：架构规则违规

**Given**:
- `scripts/helper.sh` 依赖 `src/server.ts`（违反分层规则）
- `config/arch-rules.yaml` 定义禁止此依赖
**When**: 执行 arch-check 工作流
**Then**:
- 架构规则检测失败
- 工作流状态为 Failed
- 输出违规详情
- PR 评论指出违规

### SC-CI-005：检查全部通过

**Given**:
- 代码无循环依赖
- 代码无严重孤儿模块
- 代码符合架构规则
**When**: 执行 arch-check 工作流
**Then**:
- 所有检查通过
- 工作流状态为 Success
- 无 PR 评论（或成功评论）

### SC-CI-006：actionlint 语法验证

**Given**:
- 新创建或修改的 `.github/workflows/arch-check.yml`
**When**: 执行 `actionlint .github/workflows/arch-check.yml`
**Then**:
- 退出码 0
- 无语法错误输出

### SC-CI-007：GitLab CI 模板使用

**Given**:
- 用户复制 `.gitlab-ci.yml.template` 为 `.gitlab-ci.yml`
**When**: 创建 Merge Request
**Then**:
- 触发 arch-check stage
- 执行架构检查
- 显示检查结果

### SC-CI-008：配置覆盖

**Given**:
- 设置 `ARCH_CHECK_FAIL_ON_WARNING=true`
- 代码存在孤儿模块
**When**: 执行 arch-check 工作流
**Then**:
- 孤儿模块导致失败
- 工作流状态为 Failed

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-CI-001 | SC-CI-001 | AC-G09 |
| REQ-CI-002 | SC-CI-002, SC-CI-003, SC-CI-004, SC-CI-005 | AC-G09 |
| REQ-CI-003 | SC-CI-002, SC-CI-003, SC-CI-004 | AC-G09 |
| REQ-CI-004 | SC-CI-002, SC-CI-003, SC-CI-004 | AC-G09 |
| REQ-CI-005 | SC-CI-007 | AC-G09 |
| REQ-CI-006 | SC-CI-008 | AC-G09 |
| REQ-CI-007 | SC-CI-006 | AC-G09 |

---

## Contract Test IDs

| Test ID | 类型 | 覆盖需求/场景 | 说明 |
|---------|------|---------------|------|
| CT-CI-001 | syntax | REQ-CI-007, SC-CI-006 | actionlint 语法验证 |
| CT-CI-002 | behavior | REQ-CI-002, SC-CI-002 | 循环依赖检测 |
| CT-CI-003 | behavior | REQ-CI-002, SC-CI-003 | 孤儿模块检测 |
| CT-CI-004 | behavior | REQ-CI-002, SC-CI-004 | 架构规则检测 |
| CT-CI-005 | behavior | REQ-CI-002, SC-CI-005 | 全部通过场景 |
| CT-CI-006 | behavior | REQ-CI-006, SC-CI-008 | 配置覆盖 |

---

## GitHub Action 模板

```yaml
# .github/workflows/arch-check.yml
name: Architecture Check

on:
  pull_request:
    branches: [master, main]
  workflow_dispatch:

env:
  ARCH_CHECK_FAIL_ON_WARNING: ${{ vars.ARCH_CHECK_FAIL_ON_WARNING || 'false' }}
  ARCH_CHECK_RULES_FILE: ${{ vars.ARCH_CHECK_RULES_FILE || 'config/arch-rules.yaml' }}

jobs:
  arch-check:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'

      - name: Install dependencies
        run: npm ci

      - name: Check for circular dependencies
        id: cycles
        run: |
          ./scripts/dependency-guard.sh --cycles --format json > /tmp/cycles.json
          if jq -e '.cycles | length > 0' /tmp/cycles.json > /dev/null; then
            echo "status=fail" >> $GITHUB_OUTPUT
            echo "::error::Circular dependencies detected"
            cat /tmp/cycles.json
          else
            echo "status=pass" >> $GITHUB_OUTPUT
            echo "No circular dependencies found"
          fi

      - name: Check for orphan modules
        id: orphans
        run: |
          ./scripts/dependency-guard.sh --orphan-check --format json > /tmp/orphans.json
          if jq -e '.orphans | length > 0' /tmp/orphans.json > /dev/null; then
            echo "status=warning" >> $GITHUB_OUTPUT
            echo "::warning::Orphan modules detected"
            cat /tmp/orphans.json
          else
            echo "status=pass" >> $GITHUB_OUTPUT
            echo "No orphan modules found"
          fi

      - name: Check architecture rules
        id: arch-rules
        run: |
          if [ -f "$ARCH_CHECK_RULES_FILE" ]; then
            ./scripts/boundary-detector.sh detect --rules "$ARCH_CHECK_RULES_FILE" --format json > /tmp/violations.json
            if jq -e '.violations | length > 0' /tmp/violations.json > /dev/null; then
              echo "status=fail" >> $GITHUB_OUTPUT
              echo "::error::Architecture rule violations detected"
              cat /tmp/violations.json
            else
              echo "status=pass" >> $GITHUB_OUTPUT
              echo "Architecture rules check passed"
            fi
          else
            echo "status=skip" >> $GITHUB_OUTPUT
            echo "No architecture rules file found, skipping"
          fi

      - name: Fail if checks failed
        if: steps.cycles.outputs.status == 'fail' || steps.arch-rules.outputs.status == 'fail'
        run: exit 1

      - name: Fail on warning if configured
        if: env.ARCH_CHECK_FAIL_ON_WARNING == 'true' && steps.orphans.outputs.status == 'warning'
        run: exit 1

      - name: Comment on PR
        if: failure() && github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '## Architecture Check Failed\n\nPlease review the architecture violations in the workflow logs.\n\n[View Details](' + context.serverUrl + '/' + context.repo.owner + '/' + context.repo.repo + '/actions/runs/' + context.runId + ')'
            })
```

---

## GitLab CI 模板

```yaml
# .gitlab-ci.yml.template
# 复制此文件为 .gitlab-ci.yml 以启用

stages:
  - lint
  - test
  - arch-check

variables:
  ARCH_CHECK_FAIL_ON_WARNING: "false"
  ARCH_CHECK_RULES_FILE: "config/arch-rules.yaml"

arch-check:
  stage: arch-check
  image: node:18
  before_script:
    - npm ci
  script:
    - echo "Checking for circular dependencies..."
    - ./scripts/dependency-guard.sh --cycles --format json | tee cycles.json
    - |
      if jq -e '.cycles | length > 0' cycles.json > /dev/null; then
        echo "ERROR: Circular dependencies detected"
        exit 1
      fi
    - echo "Checking for orphan modules..."
    - ./scripts/dependency-guard.sh --orphan-check --format json | tee orphans.json
    - |
      if jq -e '.orphans | length > 0' orphans.json > /dev/null; then
        echo "WARNING: Orphan modules detected"
        if [ "$ARCH_CHECK_FAIL_ON_WARNING" = "true" ]; then
          exit 1
        fi
      fi
    - echo "Checking architecture rules..."
    - |
      if [ -f "$ARCH_CHECK_RULES_FILE" ]; then
        ./scripts/boundary-detector.sh detect --rules "$ARCH_CHECK_RULES_FILE" --format json | tee violations.json
        if jq -e '.violations | length > 0' violations.json > /dev/null; then
          echo "ERROR: Architecture rule violations detected"
          exit 1
        fi
      else
        echo "No architecture rules file found, skipping"
      fi
    - echo "All architecture checks passed!"
  artifacts:
    when: always
    paths:
      - cycles.json
      - orphans.json
      - violations.json
    expire_in: 1 week
  only:
    - merge_requests
  allow_failure: false
```

---

## 文件清单

| 文件 | 类型 | 说明 |
|------|------|------|
| `.github/workflows/arch-check.yml` | 新增 | GitHub Action 模板 |
| `.gitlab-ci.yml.template` | 新增 | GitLab CI 模板 |
| `tests/ci.bats` | 新增 | CI 相关测试 |
