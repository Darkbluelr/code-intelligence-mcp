# 技术债热点分析：Code Intelligence MCP Server

> 生成时间：2026-01-13
> 生成方式：静态复杂度分析（Git 历史不可用）
> 分析范围：src/, scripts/

---

## 分析方法说明

由于当前仓库无 Git 提交历史，无法计算变更频率。本报告基于以下静态指标：

- **代码行数**：文件规模
- **函数数量**：模块复杂度
- **依赖关系**：耦合程度

**热点公式（简化）**：
```
热点分数 = 代码行数 × 功能密度系数
```

---

## 热点清单

### 高复杂度文件（需关注）

| 排名 | 文件 | 行数 | 风险等级 | 建议 |
|------|------|------|----------|------|
| 1 | `scripts/embedding.sh` | 1332 | 🔴 高 | 考虑拆分为子模块 |
| 2 | `scripts/graph-rag.sh` | 912 | 🟡 中高 | 核心功能，需充分测试 |
| 3 | `scripts/bug-locator.sh` | 793 | 🟡 中高 | 依赖多个外部服务 |
| 4 | `scripts/call-chain.sh` | 742 | 🟡 中高 | CKB 依赖集中 |
| 5 | `scripts/pattern-learner.sh` | 706 | 🟡 中 | 新功能，需稳定性验证 |

### 中等复杂度文件

| 文件 | 行数 | 风险等级 | 说明 |
|------|------|----------|------|
| `scripts/ast-diff.sh` | 595 | 🟢 中 | AST 处理逻辑 |
| `scripts/common.sh` | 449 | 🟢 中 | 共享库，变更影响大 |
| `scripts/entropy-viz.sh` | 392 | 🟢 低 | 独立功能 |
| `src/server.ts` | 356 | 🟢 低 | 薄壳设计，职责清晰 |
| `scripts/reranker.sh` | 335 | 🟢 低 | LLM 重排序 |

### 低复杂度文件（健康）

| 文件 | 行数 | 说明 |
|------|------|------|
| `scripts/indexer.sh` | 322 | 索引管理 |
| `scripts/boundary-detector.sh` | 291 | 边界检测 |
| `scripts/hotspot-analyzer.sh` | 227 | 热点分析 |
| `scripts/complexity.sh` | 279 | 复杂度计算 |

---

## 依赖风险分析

### 高耦合模块

```
embedding.sh (1332 行)
├── 被依赖：graph-rag.sh, bug-locator.sh, hooks/*
├── 外部依赖：Ollama, OpenAI API
└── 风险：修改影响范围大

common.sh (449 行)
├── 被依赖：所有 scripts/*.sh
└── 风险：任何变更都需全量测试
```

### 外部服务依赖

| 服务 | 依赖脚本 | 降级策略 |
|------|----------|----------|
| Ollama | embedding.sh | OpenAI → 关键词搜索 |
| CKB MCP | call-chain.sh, graph-rag.sh | 功能降级 |
| OpenAI API | embedding.sh, reranker.sh | Ollama → 关键词搜索 |

---

## 建议行动

### 短期（立即）

1. **为 embedding.sh 添加测试覆盖**
   - 原因：最大文件，核心功能
   - 目标：关键路径测试覆盖

2. **common.sh 变更审查流程**
   - 原因：全局影响
   - 措施：PR 需 2 人 review

### 中期（下个迭代）

1. **拆分 embedding.sh**
   - 建议拆分点：
     - `embedding-index.sh`：索引构建
     - `embedding-search.sh`：搜索查询
     - `embedding-provider.sh`：Provider 抽象

2. **增加集成测试**
   - 目标：核心功能端到端测试
   - 覆盖：embedding, graph-rag, call-chain

### 长期（技术债务）

1. 建立变更频率跟踪（Git 历史积累后）
2. 引入圈复杂度工具（shellcheck + custom rules）
3. 定期热点报告生成（/devbooks:entropy）

---

## 热点分布图

```
复杂度
  ^
  │                        ● embedding.sh (1332)
  │
  │               ● graph-rag.sh (912)
  │          ● bug-locator.sh (793)
  │        ● call-chain.sh (742)
  │       ● pattern-learner.sh (706)
  │
  │     ● ast-diff.sh (595)
  │   ● common.sh (449)
  │  ● entropy-viz.sh (392)
  │ ● server.ts (356)
  │● reranker.sh (335)
  └──────────────────────────────→ 依赖数
    低                          高
```

---

## 下次更新

当仓库有 Git 历史后，运行以下命令获取更精确的热点分析：

```bash
/devbooks:entropy
```

或手动生成 SCIP 索引后使用 CKB 增强分析：

```bash
scip-typescript index --output index.scip
/devbooks:bootstrap
```
