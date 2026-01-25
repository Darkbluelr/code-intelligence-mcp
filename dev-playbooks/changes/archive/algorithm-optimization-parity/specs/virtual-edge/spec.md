# 规格：虚拟边置信度 (Virtual Edge Confidence)

> **Capability ID**: ALG-006
> **模块**: federation-lite.sh
> **类型**: 行为变更（内部算法优化）

## Requirements

### REQ-VE-001: 置信度计算

**描述**: 跨仓库虚拟边的置信度基于多个因子计算。

**输入因子**:
- `name_similarity`: 符号名称相似度 (0-1)
- `path_similarity`: 文件路径相似度 (0-1)
- `version_compatibility`: 版本兼容性评分 (0-1)

**公式**:
```
confidence = name_similarity × 0.5 + path_similarity × 0.3 + version_compatibility × 0.2
```

---

### REQ-VE-002: 置信度阈值

**描述**: 只有置信度 ≥ 阈值的虚拟边才会被创建。

**配置键**: `federation_virtual_edges.confidence_threshold`
**默认值**: 0.5

---

### REQ-VE-003: 高置信度标记

**描述**: 置信度超过高阈值的边标记为"高置信"。

**配置键**: `federation_virtual_edges.high_confidence_threshold`
**默认值**: 0.8

---

### REQ-VE-004: 名称相似度计算

**描述**: 使用 Levenshtein 距离或精确匹配计算名称相似度。

**规则**:
- 精确匹配: 1.0
- 大小写不敏感匹配: 0.9
- 前缀匹配: 0.7
- 其他: Levenshtein 相似度

---

## Scenarios

### SC-VE-001: 高置信度虚拟边

- **Given**: 跨仓库符号引用
  - name_similarity = 1.0（精确匹配）
  - path_similarity = 0.8
  - version_compatibility = 1.0
- **When**: 计算虚拟边置信度
- **Then**: confidence = 1.0×0.5 + 0.8×0.3 + 1.0×0.2 = 0.94
- **And**: 标记为"高置信"

### SC-VE-002: 边界阈值过滤

- **Given**: 置信度阈值 = 0.5
- **And**: 计算得出 confidence = 0.49
- **When**: 判断是否创建虚拟边
- **Then**: 不创建虚拟边

### SC-VE-003: 刚好达到阈值

- **Given**: 置信度阈值 = 0.5
- **And**: 计算得出 confidence = 0.5
- **When**: 判断是否创建虚拟边
- **Then**: 创建虚拟边

### SC-VE-004: 版本不兼容

- **Given**: 符号版本不兼容
- **And**: version_compatibility = 0
- **When**: 计算虚拟边置信度
- **Then**: confidence 降低 0.2

### SC-VE-005: 名称前缀匹配

- **Given**: 源符号名 = "handleAuth"
- **And**: 目标符号名 = "handleAuthV2"
- **When**: 计算名称相似度
- **Then**: name_similarity = 0.7（前缀匹配）

---

## Contract Test IDs

| Test ID | 类型 | 覆盖场景 |
|---------|------|----------|
| CT-VE-001 | behavior | SC-VE-001 |
| CT-VE-002 | boundary | SC-VE-002 |
| CT-VE-003 | boundary | SC-VE-003 |
| CT-VE-004 | behavior | SC-VE-004 |
| CT-VE-005 | unit | SC-VE-005 |
