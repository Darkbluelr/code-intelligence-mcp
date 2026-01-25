# 实现计划: 代码智能能力升级

Change-ID: 20260118-0057-upgrade-code-intelligence-capabilities

## 里程碑

### MP1: 边类型解析增强 ✅
- [x] MP1.1: SCIP 解析 IMPLEMENTS
- [x] MP1.2: SCIP 解析 EXTENDS
- [x] MP1.3: SCIP 解析 RETURNS_TYPE
- [x] MP1.4: grep 后备支持三种边类型

### MP2: Schema 迁移 ✅
- [x] MP2.1: 定义 v3 schema
- [x] MP2.2: 实现迁移 SQL
- [x] MP2.3: 自动备份机制
- [x] MP2.4: 并发保护 (mkdir 原子锁)
- [x] MP2.5: 回滚机制

### MP3: CKB MCP 集成 ✅
- [x] MP3.1: CKB 可用性检测
- [x] MP3.2: 跨平台超时 (call_with_timeout)
- [x] MP3.3: 动态降级机制
- [x] MP3.4: 冷却期实现 (60s)
- [x] MP3.5: fallback_reason 输出

### MP4: Graph+Vector Fusion ✅
- [x] MP4.1: --fusion-depth 参数
- [x] MP4.2: 参数验证 (0-5)
- [x] MP4.3: 1-hop 图扩展
- [x] MP4.4: Token 预算控制
- [x] MP4.5: 降级本地遍历

### MP5: Auto Warmup ✅
- [x] MP5.1: daemon start 触发预热
- [x] MP5.2: 异步执行
- [x] MP5.3: 30s 超时保护
- [x] MP5.4: WARMUP_ENABLED 开关
- [x] MP5.5: status 输出 warmup_status

## 修改文件清单

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| scripts/scip-to-graph.sh | 修改 | 边类型提取 |
| scripts/graph-store.sh | 修改 | Schema 迁移 + stats SQL 修复 |
| scripts/graph-rag.sh | 修改 | CKB 集成 + Fusion 查询 |
| scripts/daemon.sh | 修改 | Auto warmup |
| tests/upgrade-capabilities.bats | 新增 | 47 个测试用例 |

## 完成状态

所有任务已完成，测试通过率 100%。
