# Docs Consistency 报告（Check Only）

- Change：`20260123-1206-add-auto-tool-orchestrator`
- 运行时间（UTC）：`2026-01-24T10:31:22Z`
- 配置发现：发现 `.devbooks/config.yaml`（本次未发现文档规则映射项，使用默认脚本参数）
- 扫描范围：基于 `git status --porcelain` 的变更文档集合
  - `README.md`
  - `README.zh-CN.md`
  - `docs/TECHNICAL.md`
  - `docs/TECHNICAL_zh.md`
- 工具：`devbooks-docs-consistency`（`doc-classifier.sh`、`rules-engine.sh`、`completeness-checker.sh`、`style-checker.sh`）

## 文档分类（doc-classifier）

| 文件 | 分类 |
| --- | --- |
| `README.md` | living |
| `README.zh-CN.md` | unknown（规则未覆盖 `README.zh-CN.md`） |
| `docs/TECHNICAL.md` | living |
| `docs/TECHNICAL_zh.md` | living |

## 规则检查（rules-engine）

规则文件：`devbooks-docs-consistency/references/docs-rules-schema.yaml`

- `README.md`：pass
- `README.zh-CN.md`：fail（`forbid-smart` 命中：`智能`）
- `docs/TECHNICAL.md`：pass
- `docs/TECHNICAL_zh.md`：fail（`forbid-smart` 命中：`智能`）

备注：
- 当前默认规则对 “智能” 的禁用会与本仓库既有中文表述（如“代码智能”）产生冲突，建议为本仓库单独提供规则覆盖（或将该规则调整为更精确的模式/白名单）。

## 完备性检查（completeness-checker）

维度配置：`devbooks-docs-consistency/references/completeness-dimensions.yaml`

### `README.md`

- 环境依赖: ✓ 命中: Node.js
- 安全权限: ✗ 缺少: 权限 安全 密钥
- 故障排查: ✓ 命中: Troubleshooting
- 配置说明: ✓ 命中: config
- API 文档: ✓ 命中: API

### `README.zh-CN.md`

- 环境依赖: ✓ 命中: Node.js
- 安全权限: ✓ 命中: 安全
- 故障排查: ✓ 命中: 故障
- 配置说明: ✓ 命中: 配置
- API 文档: ✓ 命中: API

### `docs/TECHNICAL.md`

- 环境依赖: ✓ 命中: Node.js
- 安全权限: ✗ 缺少: 权限 安全 密钥
- 故障排查: ✗ 缺少: 故障 排查 Troubleshooting
- 配置说明: ✓ 命中: config
- API 文档: ✓ 命中: API

### `docs/TECHNICAL_zh.md`

- 环境依赖: ✓ 命中: Node.js
- 安全权限: ✓ 命中: 安全
- 故障排查: ✗ 缺少: 故障 排查 Troubleshooting
- 配置说明: ✓ 命中: 配置
- API 文档: ✓ 命中: API

备注：
- 该完备性检查为“关键词命中”模型，且当前 “安全权限” 维度仅包含中文关键词，可能对英文文档产生误报；建议补充英文关键词（如 `Security` / `Permissions` / `Credentials` 等）或为不同语种拆分维度配置。

## 风格检查（style-checker）

- `README.md`：pass
- `README.zh-CN.md`：pass
- `docs/TECHNICAL.md`：pass
- `docs/TECHNICAL_zh.md`：pass

