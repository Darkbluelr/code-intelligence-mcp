# Augment 轻资产能力差距评估报告（仅轻资产）

日期：2026-01-22

## 1. 范围与假设

- 对标来源：`docs/Augment.md`
- 排除项（重资产）：自研/深度定制大模型、大规模数据闭环、组织级超大规模分布式索引与推理基础设施
- 仅评估“轻资产能力”：可通过代码/算法/工程化工具在中小规模上实现的能力
- 证据基于仓库现有实现/文档/脚本路径，未标注证据的能力视为“未见证据”

## 2. Augment 轻资产能力清单（精简）

1. 仓库原生上下文（动态选择相关子图/切片）
2. 语法/语义/上下文三层理解
3. 通用代码图谱（节点+边，确定性图遍历）
4. Graph-RAG（向量锚点 + 图多跳扩展）
5. 跨仓库联邦与虚拟边（契约联结）
6. 深度索引流水线（AST/符号解析/关系抽取）
7. 增量索引（Delta 更新）
8. COD 画像与可视化（依赖拓扑）
9. 架构漂移检测（图谱快照 diff）
10. 热点识别（变更频率 × 复杂度）
11. 边界识别（用户/第三方/生成代码）
12. 意图解析 + 多信号聚合（prompt/文件/历史）
13. 子图检索 + 重排序（降噪）
14. 依赖卫士 + Policy as Code + CI 门禁
15. Bug 定位与调用链/数据流追踪
16. 语义异常检测（项目隐式规范）
17. 安全影响定位（依赖传播追踪）
18. 缓存/预热/请求取消（交互延迟优化）

## 3. 现有能力映射与差距

表中“状态”含义：已具备 / 部分 / 未见证据

| 能力 | 状态 | 证据路径 | 说明与差距 |
|---|---|---|---|
| 仓库原生上下文 | 已具备 | `hooks/augment-context-global.sh` | 支持基于 prompt 与项目画像构建结构化上下文，接近“仓库原生”模式。 |
| 三层理解（语法/语义/上下文） | 部分 | `scripts/ast-delta.sh`, `scripts/graph-store.sh`, `scripts/adr-parser.sh`, `scripts/intent-learner.sh` | 语法/语义层已有；上下文层主要是 ADR/历史信号，运行时追踪/CI 产物融合未见明确落地。 |
| 通用代码图谱（UCG） | 已具备 | `scripts/graph-store.sh`, `scripts/scip-to-graph.sh`, `index.scip` | SQLite 图存储 + SCIP 解析。跨语言统一程度取决于 SCIP 覆盖。 |
| Graph-RAG（向量锚点+图遍历） | 已具备 | `scripts/graph-rag.sh`, `scripts/graph-rag-query.sh`, `scripts/graph-rag-fusion.sh` | 支持图检索+向量检索融合，含 RRF 融合。 |
| 跨仓库联邦与虚拟边 | 部分 | `scripts/federation-lite.sh`, `config/federation.yaml` | 轻量联邦索引已实现；规模化、跨组织的稳定联邦与一致性保障未见。 |
| 深度索引流水线 | 部分 | `scripts/scip-to-graph.sh`, `scripts/ast-delta.sh` | AST/符号抽取与图构建可用；“全语言/全精度”的深度索引仍是差距。 |
| 增量索引（Delta） | 已具备 | `scripts/ast-delta.sh` | 支持增量 AST 与图更新。 |
| COD 画像与可视化 | 已具备 | `scripts/cod-visualizer.sh` | 支持 Mermaid/D3 输出，含热点与复杂度。 |
| 架构漂移检测 | 已具备 | `scripts/drift-detector.sh` | 支持快照/比较/C4 对齐。 |
| 热点识别 | 已具备 | `scripts/hotspot-analyzer.sh` | 含 `frequency × complexity` 公式与增强版权重。 |
| 边界识别 | 已具备 | `scripts/boundary-detector.sh`, `config/boundaries.yaml` | 支持用户/第三方/生成代码区分。 |
| 意图解析+多信号聚合 | 部分 | `hooks/augment-context-global.sh`, `scripts/intent-learner.sh`, `scripts/embedding.sh` | 有对话/信号加权；IDE 光标/编辑流实时信号接入的证据不足。 |
| 子图检索 | 已具备 | `scripts/graph-rag-query.sh` | 子图构建与多跳遍历已实现。 |
| 重排序（Rerank/Judge） | 部分 | `scripts/graph-rag-fusion.sh`, `config/features.yaml` | 支持 rerank 但默认可能关闭；LLM rerank 稳定性与门禁策略仍偏弱。 |
| 依赖卫士 | 已具备 | `scripts/dependency-guard.sh` | 循环依赖/孤儿模块/规则校验均支持。 |
| Policy as Code | 已具备 | `config/arch-rules.yaml`, `scripts/dependency-guard.sh` | 架构规则可配置化并执行。 |
| CI 门禁集成 | 已具备 | `.github/workflows/arch-check.yml`, `.gitlab-ci.yml.template` | 已接入 CI 验证。 |
| Bug 定位 | 已具备 | `scripts/bug-locator.sh` | 支持错误描述定位与缓存。 |
| 调用链/数据流追踪 | 已具备 | `scripts/call-chain.sh`, `scripts/call-chain-dataflow.sh` | 支持调用链与参数/返回值流追踪。 |
| 语义异常检测 | 部分 | `scripts/semantic-anomaly.sh` | 脚本与测试存在；对“项目隐式规范”的学习强度与误报控制仍需验证。 |
| 安全影响定位（依赖传播追踪） | 已具备 | `scripts/vuln-tracker.sh` | 依赖传播链追踪已实现。 |
| 缓存与预热 | 已具备 | `scripts/cache-manager.sh`, `scripts/daemon.sh` | 子图缓存与 warmup 已实现。 |
| 请求取消 | 已具备 | `scripts/daemon.sh` | 支持取消过期请求。 |
| 上下文压缩 | 已具备 | `scripts/context-compressor.sh` | 有压缩策略与预算控制。 |

## 4. 轻资产差距总结（按优先级）

P0（关键短板）
- 上下文层“运行时信号”与“CI 产物”融合未见明确落地：当前上下文更多依赖 ADR/历史信号，缺少运行时追踪数据进入长期记忆的证据。
- IDE/编辑器实时信号的系统化接入不足：具备 `--file/--line` 参数与信号加权能力，但未见端到端的“光标/编辑流/打开文件”自动采集链路。

P1（能力可用但未达 Augment 稳定度）
- 重排序默认管线与稳定性：Rerank 能力存在但可能默认关闭，缺乏“强制进入主流程”的证据与质量保障指标。
- 深度索引覆盖度：已有 SCIP/AST 管线，但跨语言统一与语义精度可能仍有差距。
- 多仓库联邦成熟度：已有 federation-lite，但规模化一致性与可靠性仍待验证。

P2（效果型差距）
- 语义异常检测的“学习-反馈闭环”能力：现有脚本可运行，但是否形成稳定低误报的项目规则学习仍需证据支撑。

## 5. 结论

在“轻资产能力”范围内，本项目已经覆盖 Augment 绝大多数关键能力域（图谱、Graph-RAG、增量索引、热点、漂移、依赖卫士、CI 门禁、数据流追踪等）。
主要差距集中在“上下文层的实时信号与运行时/CI 产物融合”、“重排序默认管线稳定性”、以及“跨仓库联邦与深度索引的规模化成熟度”。

