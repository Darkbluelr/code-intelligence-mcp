truth-root: dev-playbooks/specs（未按配置文件验证）；change-root: dev-playbooks/changes（基于变更包路径）

# Code Review（第 3 次）：演示与文档层

- change-id: 20260123-0702-improve-demo-suite-ab-metrics
- reviewer: devbooks-reviewer（System Architect / Security Expert）
- 评审范围（仅演示与文档层）: demo/demo-suite.sh, demo/DEMO-GUIDE.md, dev-playbooks/docs/长期可复用演示方案.md, docs/demos/README.md, README.zh-CN.md, dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/code-review-2.md
- 限制: 未读取 dev-playbooks/specs/** 与其它实现层文件；未运行脚本/测试；未读取 tasks.md 与 evidence/green-final/（受评审范围限制）

## 已解决项（对照 code-review-2）

- 文档与脚本对“当前能力边界”的表述已一致，明确已有 metrics/report/compare 与诊断锚点范围，避免“仅 out-dir 初始化”的误导：demo/DEMO-GUIDE.md:3-5, demo/demo-suite.sh:2-7
- 降级兜底产物的文档契约与实现已对齐，明确 degraded/metrics.json 与 degraded/report.md 并落盘：demo/DEMO-GUIDE.md:78-85, demo/demo-suite.sh:942-973
- 临时文件策略已绑定 out-dir，避免系统 /tmp 污染，与文档描述一致：demo/DEMO-GUIDE.md:41-43, demo/demo-suite.sh:1700-1704
- README 已补充按特性划分的依赖矩阵，明确 A/B compare 对 jq 的强依赖：README.zh-CN.md:46-51
- 诊断锚点已显式可配置并写入产物，降低默认锚点的演进风险：demo/DEMO-GUIDE.md:23-37, demo/demo-suite.sh:26-27
- CLI 与 MCP 工具名映射已补充说明，降低命名混用风险：README.zh-CN.md:70-77
- eval 注入风险已通过前缀白名单与安全注释进行显式约束：demo/demo-suite.sh:529-546, demo/demo-suite.sh:1892-1893

## 仍遗留项（对照 code-review-2）

- 可维护性风险：write_ab_version_compare 与 write_ab_config_compare 仍存在大段重复逻辑，后续修改易出现漏改；建议提取共享 compare 生成函数并复用，验证方式：对比 demo/demo-suite.sh:1068-1289 与 demo/demo-suite.sh:1314-1554，重复逻辑被收敛到单一公共函数。
- 文档一致性建议：公开归档自检仍缺少“可选的敏感信息扫描”步骤提示，建议补充最小扫描建议与示例模式，验证方式：在 docs/demos/README.md 增加可选扫描步骤并复核约束段落一致性（docs/demos/README.md:7-12）。
- 交付完整性阻断项：tasks/test/green 证据未验证，无法满足 Reviewer 完整性闸门；建议提供可验证证据或放开读取范围，验证方式：rg "^- \[ \]" dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/tasks.md；npm test；ls -la dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/green-final/；rg -i "FAIL|FAILED|ERROR" dev-playbooks/changes/20260123-0702-improve-demo-suite-ab-metrics/evidence/green-final/。

## 产出物完整性检查

| 检查项 | 状态 | 说明 |
|--------|------|------|
| tasks.md 完成度 | ❌ | 未读取 tasks.md（受评审范围限制） |
| 测试全绿（非 Skip） | ❌ | 未运行测试（受评审范围限制） |
| Green 证据存在 | ❌ | 未读取 evidence/green-final/（受评审范围限制） |
| 无失败模式在证据中 | ❌ | 未读取日志（受评审范围限制） |

**评审结论：REVISE REQUIRED**
