# 文档一致性检查报告（Docs Consistency）

- Change ID：`20260123-0702-improve-demo-suite-ab-metrics`
- 扫描时间：`2026-01-23T20:53:59Z`（UTC）
- 扫描文件数：4

## 扫描清单

- `README.zh-CN.md`
- `docs/demos/README.md`
- `demo/DEMO-GUIDE.md`
- `dev-playbooks/docs/长期可复用演示方案.md`

---

## 文件：`README.zh-CN.md`

- 分类：`unknown`

### 完备性检查（heuristic）

- 环境依赖: ✓ 命中: Node.js
- 安全权限: ✓ 命中: 安全
- 故障排查: ✓ 命中: 故障
- 配置说明: ✓ 命中: 配置
- API 文档: ✓ 命中: API

### 规则检查（docs-rules-schema.yaml）

- 结果：⚠️ 发现违规（非阻断）
```
rule_id=forbid-smart file=README.zh-CN.md forbidden=智能
```

### 风格检查（style-checker.sh）

- 结果：✓ 通过

### 关键一致性断言（抽样）

- ✓ 提及 `demo/demo-suite.sh`
- ✓ 提及 `docs/demos/README.md`

---

## 文件：`docs/demos/README.md`

- 分类：`living`

### 完备性检查（heuristic）

- 环境依赖: ✗ 缺少: Node.js Python 依赖
- 安全权限: ✓ 命中: 密钥
- 故障排查: ✗ 缺少: 故障 排查 Troubleshooting
- 配置说明: ✓ 命中: config
- API 文档: ✗ 缺少: API 接口 Endpoint

### 规则检查（docs-rules-schema.yaml）

- 结果：✓ 通过

### 风格检查（style-checker.sh）

- 结果：✓ 通过

### 关键一致性断言（抽样）

- ✓ 提及 `demo/demo-suite.sh`

---

## 文件：`demo/DEMO-GUIDE.md`

- 分类：`unknown`

### 完备性检查（heuristic）

- 环境依赖: ✓ 命中: 依赖
- 安全权限: ✓ 命中: 安全
- 故障排查: ✗ 缺少: 故障 排查 Troubleshooting
- 配置说明: ✓ 命中: 配置
- API 文档: ✗ 缺少: API 接口 Endpoint

### 规则检查（docs-rules-schema.yaml）

- 结果：✓ 通过

### 风格检查（style-checker.sh）

- 结果：✓ 通过

### 关键一致性断言（抽样）

- ✓ 提及 `demo/demo-suite.sh`
- ✓ 提及 `docs/demos/README.md`
- ✓ 提及 `metrics.json.ai_ab.*`

---

## 文件：`dev-playbooks/docs/长期可复用演示方案.md`

- 分类：`living`

### 完备性检查（heuristic）

- 环境依赖: ✓ 命中: 依赖
- 安全权限: ✓ 命中: 安全
- 故障排查: ✗ 缺少: 故障 排查 Troubleshooting
- 配置说明: ✓ 命中: 配置
- API 文档: ✗ 缺少: API 接口 Endpoint

### 规则检查（docs-rules-schema.yaml）

- 结果：✓ 通过

### 风格检查（style-checker.sh）

- 结果：✓ 通过

### 关键一致性断言（抽样）

- ✓ 提及 `demo/demo-suite.sh`
- ✓ 提及 `docs/demos/README.md`

---

