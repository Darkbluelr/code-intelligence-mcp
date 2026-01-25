# 设计文档: 代码智能能力升级

Change-ID: 20260118-0057-upgrade-code-intelligence-capabilities

## What (目标)

弥补与 Augment 的差距，通过轻资产（代码/算法）实现：
1. 完整边类型解析
2. Schema 平滑迁移
3. CKB MCP 真正集成
4. Graph+Vector 融合查询
5. 自动预热机制

## Constraints (约束)

- 不引入自研模型或大数据依赖
- 保持向后兼容
- 降级方案不影响核心功能
- macOS 兼容（无 timeout 命令）

## Acceptance Criteria (验收标准)

### MP1: 边类型解析
| AC | 描述 | 测试 |
|----|------|------|
| AC-U01 | SCIP 解析 IMPLEMENTS 边 | T-EDGE-001 |
| AC-U02 | SCIP 解析 EXTENDS 边 | T-EDGE-002 |
| AC-U09 | SCIP 解析 RETURNS_TYPE 边 | T-EDGE-003 |
| AC-U10 | grep 后备支持三种边类型 | T-EDGE-004 |

### MP2: Schema 迁移
| AC | 描述 | 测试 |
|----|------|------|
| AC-U03 | v2→v3 迁移成功 | T-MIG-001 |
| AC-U11 | 迁移失败自动回滚 | T-MIG-002 |
| AC-U12 | 迁移前自动备份 | T-MIG-003 |
| AC-U13 | 并发迁移保护 | T-MIG-004 |

### MP3: CKB 集成
| AC | 描述 | 测试 |
|----|------|------|
| AC-U04 | CKB 可用时返回真实数据 | T-CKB-001 |
| AC-U14 | CKB 不可用时降级 | T-CKB-002 |
| AC-U15 | CKB 超时触发降级 | T-CKB-003 |
| AC-U16 | 60秒冷却期 | T-CKB-004 |
| AC-U17 | 输出 ckb_fallback_reason | T-CKB-005 |

### MP4: Fusion 查询
| AC | 描述 | 测试 |
|----|------|------|
| AC-U05 | Fusion 候选 >= 1.5x 向量 | T-FUSION-001 |
| AC-U07 | Token 预算控制 | T-FUSION-002 |
| AC-U08 | 延迟增加 < 300ms | T-FUSION-003 |
| AC-U18 | 降级使用本地遍历 | T-FUSION-004 |

### MP5: Auto Warmup
| AC | 描述 | 测试 |
|----|------|------|
| AC-U06 | Daemon 启动触发预热 | T-WARMUP-001 |
| AC-U19 | 预热不阻塞启动 | T-WARMUP-002 |
| AC-U20 | 预热超时不影响 daemon | T-WARMUP-003 |

## 测试覆盖

- @smoke: 13 测试
- @critical: 23 测试
- Boundary: 4 测试
- **总计: 47 测试**

## 实现状态

所有 AC 已通过验证，测试通过率 100%。
