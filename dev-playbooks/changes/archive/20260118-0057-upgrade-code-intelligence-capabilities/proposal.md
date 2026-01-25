# 变更提案: 代码智能能力升级

Change-ID: 20260118-0057-upgrade-code-intelligence-capabilities
Status: APPROVED → IMPLEMENTED → ARCHIVED

## Why (动机)

当前项目的代码智能水平约为 Augment 的 70%。通过分析差距，识别出可用"轻资产"（代码/算法）弥补的改进点，无需自研模型或大数据。

## What (变更内容)

### 1. 边类型解析增强 (MP1)
- SCIP 解析器支持 IMPLEMENTS/EXTENDS/RETURNS_TYPE
- grep 后备分支同样支持三种边类型

### 2. Schema 迁移 (MP2)
- v2 → v3 自动迁移
- 备份/回滚机制
- 并发迁移保护

### 3. CKB MCP 集成 (MP3)
- 通过 MCP Client SDK 调用 CKB Server
- 超时降级机制
- 60秒冷却期

### 4. Graph+Vector Fusion (MP4)
- --fusion-depth 参数 (0-5)
- 1-hop 图扩展
- Token 预算控制

### 5. Auto Warmup (MP5)
- Daemon 启动后自动预热
- 异步执行不阻塞启动
- 30秒超时保护

## Impact (影响范围)

### 修改文件
- `scripts/scip-to-graph.sh` - 边类型提取
- `scripts/graph-store.sh` - Schema 迁移
- `scripts/graph-rag.sh` - CKB 集成 + Fusion
- `scripts/daemon.sh` - Auto warmup

### 风险
- Schema 迁移失败：自动回滚
- CKB 不可用：降级到本地图遍历
- 预热超时：不影响 daemon 运行

## Decision Log

| 日期 | 决策者 | 决策 | 理由 |
|------|--------|------|------|
| 2026-01-18 | Judge | APPROVED | 所有阻塞项已修复 |
| 2026-01-18 | Test | GREEN | 47/47 测试通过 |
| 2026-01-18 | Archive | CLOSED | 验证完成，归档 |
