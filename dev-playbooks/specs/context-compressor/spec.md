# 规格：上下文智能压缩

> **Capability**: context-compressor
> **Version**: 1.0.0
> **Status**: Active
> **Created**: 2026-01-17
> **Last Referenced By**: 20260118-2112-enhance-code-intelligence-capabilities
> **Last Verified**: 2026-01-22
> **Health**: active

---

## Requirements（需求）

### REQ-CC-001：压缩率目标

系统应实现 ≥50% 的上下文压缩率：

| 指标 | 目标 |
|------|------|
| 最小压缩率 | 50% |
| 平均压缩率 | 60-70% |
| 最大压缩率 | 80%（仅保留签名） |

### REQ-CC-002：AST 骨架提取

系统应支持 AST 骨架提取模式：

```bash
# 提取模式
context_compress --mode skeleton <files>

# 保留内容
- 函数签名（完整参数和返回类型）
- 类定义（含成员签名）
- 接口定义
- 类型定义
- 导入语句

# 移除内容
- 函数体实现
- 注释（可选保留文档注释）
- 空白行
- 内部变量
```

### REQ-CC-003：符号签名摘要

系统应支持符号签名摘要模式：

```bash
# 摘要格式
function_name(ParamType1, ParamType2) -> ReturnType

# 示例
processOrder(Order, PaymentInfo) -> Result<Receipt, Error>
```

### REQ-CC-004：热点优先选择

系统应集成热点分析，优先保留高热点代码：

```bash
# 热点权重因子
hotspot_weight = churn_count * 0.4 + recent_edits * 0.3 + coupling_score * 0.3

# 选择策略
1. 按热点分数降序排列文件
2. 在 Token 预算内选择高热点文件
3. 低热点文件仅保留签名摘要
```

### REQ-CC-005：Token 预算控制

系统应严格控制输出 Token 数量：

```bash
# 预算分配
context_compress --budget 5000 <files>

# 分配策略
| 类别 | 预算比例 |
|------|----------|
| 高热点文件（完整骨架） | 60% |
| 中热点文件（签名摘要） | 30% |
| 低热点文件（仅列表） | 10% |
```

### REQ-CC-006：完整签名保留

**核心约束**：无论压缩程度如何，系统必须保留完整的函数签名：

```typescript
// 原始代码
export function processPayment(
  order: Order,
  payment: PaymentInfo,
  options?: ProcessOptions
): Promise<Result<Receipt, PaymentError>> {
  // 200 行实现...
}

// 压缩后（必须保留的内容）
export function processPayment(
  order: Order,
  payment: PaymentInfo,
  options?: ProcessOptions
): Promise<Result<Receipt, PaymentError>>;
```

### REQ-CC-007：增量压缩

系统应支持增量压缩以提高效率：

```bash
# 缓存压缩结果
.devbooks/cache/compressed/<file-hash>.json

# 增量更新
- 仅重新压缩修改的文件
- 合并缓存的压缩结果
```

### REQ-CC-008：多语言支持

系统应支持主要编程语言的 AST 解析：

| 语言 | 解析器 | 支持程度 |
|------|--------|----------|
| TypeScript | tree-sitter-typescript | 完整 |
| JavaScript | tree-sitter-javascript | 完整 |
| Python | tree-sitter-python | 完整 |
| Go | tree-sitter-go | 基础 |
| Rust | tree-sitter-rust | 基础 |

---

## Scenarios（场景）

### SC-CC-001：基础骨架提取

**Given**: 一个 500 行的 TypeScript 文件
**When**: 运行 `context-compress --mode skeleton src/service.ts`
**Then**:
- 输出 ≤200 行
- 保留所有函数签名
- 保留类和接口定义
- 移除函数体

### SC-CC-002：Token 预算压缩

**Given**:
- 10 个源文件，共 10000 Token
- Token 预算 5000
**When**: 运行 `context-compress --budget 5000 src/`
**Then**:
- 输出 ≤5000 Token
- 高热点文件保留更多内容
- 低热点文件仅保留签名

### SC-CC-003：热点优先选择

**Given**:
- 文件 A：高热点（最近修改 10 次）
- 文件 B：低热点（最近修改 0 次）
**When**: 运行压缩，预算仅够保留 1 个文件完整骨架
**Then**:
- 文件 A 保留完整骨架
- 文件 B 仅保留签名摘要

### SC-CC-004：完整签名验证

**Given**: 包含复杂泛型的函数签名
```typescript
function transform<T extends Base, R>(
  input: T,
  mapper: (item: T) => R,
  options?: TransformOptions<T, R>
): Promise<TransformResult<R>>;
```
**When**: 运行任意压缩模式
**Then**: 签名完全保留，无任何省略

### SC-CC-005：增量压缩

**Given**:
- 上次压缩结果已缓存
- 仅修改了 1 个文件
**When**: 运行压缩
**Then**:
- 仅重新压缩修改的文件
- 复用其他文件的缓存
- 总耗时降低 ≥50%

### SC-CC-006：多文件聚合

**Given**: 5 个相关文件需要压缩
**When**: 运行 `context-compress --budget 3000 file1.ts file2.ts ...`
**Then**:
- 输出包含所有文件的压缩内容
- 明确标注每个文件的边界
- 总 Token 不超过预算

---

## API 契约

### context_compress

```bash
# 基础调用
context_compress [OPTIONS] <files...>

# 选项
--mode <skeleton|summary|hybrid>  # 压缩模式，默认 hybrid
--budget <tokens>                 # Token 预算，默认无限制
--hotspot                         # 启用热点优先（默认启用）
--no-hotspot                      # 禁用热点优先
--cache                           # 启用缓存（默认启用）
--no-cache                        # 禁用缓存
--format <json|text>              # 输出格式，默认 json
```

### 输出格式（JSON）

```json
{
  "compressed_context": "// file: src/service.ts\nexport function process...",
  "metadata": {
    "original_tokens": 10000,
    "compressed_tokens": 3500,
    "compression_ratio": 0.65,
    "files_processed": 5,
    "cache_hits": 3
  },
  "files": [
    {
      "path": "src/service.ts",
      "original_tokens": 2000,
      "compressed_tokens": 700,
      "mode_used": "skeleton",
      "hotspot_score": 0.85,
      "preserved_symbols": ["processOrder", "OrderService", "PaymentHandler"]
    }
  ],
  "preserved_signatures": [
    {
      "name": "processOrder",
      "file": "src/service.ts",
      "signature": "processOrder(Order, PaymentInfo) -> Promise<Receipt>"
    }
  ]
}
```

### 输出格式（Text）

```
// ========== src/service.ts ==========
// Mode: skeleton | Tokens: 700/2000 | Hotspot: 0.85

export interface OrderService {
  processOrder(order: Order, payment: PaymentInfo): Promise<Receipt>;
  cancelOrder(orderId: string): Promise<void>;
}

export class PaymentHandler {
  constructor(config: PaymentConfig);
  validate(payment: PaymentInfo): ValidationResult;
  charge(payment: PaymentInfo, amount: number): Promise<ChargeResult>;
}

// ========== src/utils.ts ==========
// Mode: summary | Tokens: 200/1000 | Hotspot: 0.30

formatCurrency(number) -> string
validateEmail(string) -> boolean
generateId() -> string
```

---

## 追溯矩阵

| Requirement | Scenarios | AC |
|-------------|-----------|-----|
| REQ-CC-001 | SC-CC-001, SC-CC-002 | AC-006 |
| REQ-CC-002 | SC-CC-001 | AC-006 |
| REQ-CC-003 | SC-CC-002 | AC-006 |
| REQ-CC-004 | SC-CC-003 | AC-006 |
| REQ-CC-005 | SC-CC-002, SC-CC-006 | AC-006 |
| REQ-CC-006 | SC-CC-004 | AC-006 |
| REQ-CC-007 | SC-CC-005 | AC-006 |
| REQ-CC-008 | All | AC-006 |

---

## 非功能需求

### 性能基准

| 场景 | 指标 | 阈值 |
|------|------|------|
| 单文件压缩（1000行） | 延迟 | <100ms |
| 多文件压缩（10文件） | 延迟 | <500ms |
| 增量压缩（1文件变更） | 延迟 | <50ms |

### 准确性要求

| 检查项 | 要求 |
|--------|------|
| 签名完整性 | 100% 保留 |
| 类型信息完整性 | 100% 保留 |
| 导入语句完整性 | ≥95% 保留 |

---

## 测试契约

### 单元测试

```bash
# @smoke 快速验证
test_compression_ratio_above_50_percent
test_signature_preserved_completely

# @critical 关键功能
test_token_budget_respected
test_hotspot_priority_selection
test_multifile_aggregation

# @full 完整覆盖
test_incremental_compression
test_multilanguage_support
test_complex_generic_signatures
```

### 集成测试

```bash
# 端到端压缩流程
test_e2e_compression_pipeline
test_cache_invalidation
test_hotspot_integration
```
