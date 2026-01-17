# Spec: Context Layer（上下文层增强）

> **Change ID**: `augment-upgrade-phase2`
> **Capability**: context-layer
> **Version**: 1.0.0
> **Status**: Approved

---

## Requirements

### REQ-CTX-001: Commit 语义分类

系统必须对 Git Commit 进行语义分类：

| 分类 | 匹配规则（优先级高 → 低） | 示例 |
|------|---------------------------|------|
| `fix` | `^fix[:\(]` / `bug` / `issue` / `error` / `crash` | `fix: null pointer` |
| `feat` | `^feat[:\(]` / `add` / `new` / `implement` | `feat: add login` |
| `refactor` | `^refactor[:\(]` / `refact` / `clean` / `improve` | `refactor: extract method` |
| `docs` | `^docs[:\(]` / `document` / `readme` / `comment` | `docs: update README` |
| `chore` | `^chore[:\(]` / `build` / `ci` / `dep` | `chore: bump version` |

**约束**：
- 准确率 >= 90%
- 不支持国际化（仅英文规则）
- 支持自定义规则扩展

---

### REQ-CTX-002: Bug 修复历史提取

系统必须提取每个文件的 Bug 修复历史：

| 输出字段 | 说明 |
|----------|------|
| `file` | 文件路径 |
| `bug_fix_count` | Bug 修复次数（90 天内） |
| `bug_fix_commits` | Bug 修复 Commit SHA 列表 |
| `last_bug_fix` | 最近 Bug 修复时间 |

**约束**：
- 默认时间窗口：90 天
- 仅统计 `fix` 类型 Commit

---

### REQ-CTX-003: 热点算法增强

`hotspot-analyzer.sh` 必须支持集成 Bug 修复历史：

| 参数 | 说明 |
|------|------|
| `--with-bug-history` | 启用 Bug 修复权重 |
| `--bug-weight <float>` | Bug 修复权重系数（默认 1.0） |

**增强后热点分数公式**：
```
score = change_freq × complexity × (1 + bug_weight × bug_fix_ratio)
```

其中 `bug_fix_ratio = bug_fix_count / total_changes`

**约束**：
- 无 `--with-bug-history` 时，输出与变更前一致（REG2）
- 向后兼容

---

### REQ-CTX-004: 上下文索引格式

系统应生成上下文索引 `.devbooks/context-index.json`：

```json
{
  "schema_version": "1.0.0",
  "indexed_at": "2026-01-13T10:00:00Z",
  "time_window_days": 90,
  "files": [
    {
      "path": "src/server.ts",
      "bug_fix_count": 3,
      "bug_fix_commits": ["abc123", "def456", "ghi789"],
      "last_bug_fix": "2026-01-10T15:30:00Z",
      "commit_types": {
        "fix": 3,
        "feat": 5,
        "refactor": 2
      }
    }
  ]
}
```

---

## Scenarios

### SC-CTX-001: 分类 fix 类型 Commit

**Given**: Commit message = "fix: resolve null pointer in login"
**When**: 执行 Commit 分类
**Then**:
- type = "fix"
- confidence >= 0.9

---

### SC-CTX-002: 分类 feat 类型 Commit

**Given**: Commit message = "feat(auth): add OAuth support"
**When**: 执行 Commit 分类
**Then**:
- type = "feat"
- confidence >= 0.9

---

### SC-CTX-003: 分类歧义 Commit

**Given**: Commit message = "update user module"
**When**: 执行 Commit 分类
**Then**:
- type = "chore"（默认）
- confidence < 0.8

---

### SC-CTX-004: 提取 Bug 修复历史

**Given**: 文件 `src/auth.ts` 在 90 天内有 5 次 `fix` 类型 Commit
**When**: 执行 `context-layer.sh --file src/auth.ts`
**Then**:
- bug_fix_count = 5
- bug_fix_commits 长度 = 5

---

### SC-CTX-005: 热点分数增强

**Given**:
- 文件变更次数 = 10
- 复杂度 = 50
- Bug 修复次数 = 3
- bug_weight = 1.0
**When**: 执行 `hotspot-analyzer.sh --with-bug-history`
**Then**:
- bug_fix_ratio = 3/10 = 0.3
- 增强系数 = 1 + 1.0 × 0.3 = 1.3
- 最终分数 = 10 × 50 × 1.3 = 650

---

### SC-CTX-006: 热点分数无 Bug 历史

**Given**: 无 `--with-bug-history` 参数
**When**: 执行 `hotspot-analyzer.sh`
**Then**:
- 输出与变更前完全一致
- 不包含 bug_weight 字段

---

### SC-CTX-007: 上下文索引生成

**Given**: 项目有 100 个文件，90 天内有 50 次 Commit
**When**: 执行 `context-layer.sh --index`
**Then**:
- 生成 `.devbooks/context-index.json`
- files 数组包含所有有 Commit 记录的文件
- 每个文件包含 commit_types 统计

---

### SC-CTX-008: 分类准确率验证

**Given**: 测试集包含 50+ Commit，人工标注类型
**When**: 执行批量分类
**Then**:
- 整体准确率 >= 90%
- fix 类型召回率 >= 95%

---

## Contract Test IDs

| Test ID | 类型 | 覆盖需求/场景 | 说明 |
|---------|------|---------------|------|
| CT-CTX-001 | behavior | REQ-CTX-001, SC-CTX-001 | fix 分类 |
| CT-CTX-002 | behavior | REQ-CTX-001, SC-CTX-002 | feat 分类 |
| CT-CTX-003 | behavior | REQ-CTX-001, SC-CTX-003 | 歧义处理 |
| CT-CTX-004 | behavior | REQ-CTX-002, SC-CTX-004 | Bug 历史提取 |
| CT-CTX-005 | behavior | REQ-CTX-003, SC-CTX-005 | 热点增强 |
| CT-CTX-006 | behavior | REQ-CTX-003, SC-CTX-006 | 向后兼容 |
| CT-CTX-007 | behavior | REQ-CTX-004, SC-CTX-007 | 索引生成 |
| CT-CTX-008 | behavior | REQ-CTX-001, SC-CTX-008 | 准确率 >= 90% |
| CT-CTX-009 | schema | REQ-CTX-004 | 索引格式 |

---

## 脚本接口

### context-layer.sh

```bash
# 分类单个 Commit
context-layer.sh --classify <sha>

# 批量分类
context-layer.sh --classify-batch --since "90 days ago"

# 提取文件 Bug 历史
context-layer.sh --bug-history --file <path>

# 生成上下文索引
context-layer.sh --index [--days 90]
```

| 参数 | 说明 |
|------|------|
| `--classify <sha>` | 分类指定 Commit |
| `--classify-batch` | 批量分类 |
| `--since <date>` | 起始日期 |
| `--bug-history` | 提取 Bug 修复历史 |
| `--file <path>` | 指定文件 |
| `--index` | 生成上下文索引 |
| `--days <n>` | 时间窗口（天） |

### hotspot-analyzer.sh 扩展参数

```bash
# 启用 Bug 修复权重
hotspot-analyzer.sh --with-bug-history [--bug-weight 1.0]
```

| 参数 | 说明 |
|------|------|
| `--with-bug-history` | 启用 Bug 修复历史权重 |
| `--bug-weight <float>` | 权重系数（默认 1.0） |

---

## 环境变量接口

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `GIT_LOG_CMD` | `git log` | Git log 命令（可 Mock） |
| `CONTEXT_INDEX_PATH` | `.devbooks/context-index.json` | 索引路径 |
| `BUG_HISTORY_DAYS` | `90` | 默认时间窗口 |
