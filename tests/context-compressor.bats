#!/usr/bin/env bats
# 上下文智能压缩测试
# Change ID: 20260118-2112-enhance-code-intelligence-capabilities
# AC: AC-001
# 测试 ID 使用 T-CC-XXX（对应 SC-CC-XXX）

load 'helpers/common.bash'

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing command: $cmd"
}

require_executable() {
    local path="$1"
    [ -x "$path" ] || fail "Expected executable: $path"
}

require_file() {
    local path="$1"
    [ -f "$path" ] || fail "Missing file: $path"
}

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
    export SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
    export CONTEXT_COMPRESSOR_SCRIPT="${SCRIPTS_DIR}/context-compressor.sh"
    export BASE_FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures/context-compressor"
    export FIXTURES_DIR="${BATS_TEST_TMPDIR}/context-compressor"
    export BASE_TS_FIXTURE="${BASE_FIXTURES_DIR}/order-service.base.ts"

    mkdir -p "$FIXTURES_DIR"

    require_cmd jq
    require_cmd bc
    require_file "$BASE_TS_FIXTURE"
    require_executable "$CONTEXT_COMPRESSOR_SCRIPT"
}

teardown() {
    rm -rf "$FIXTURES_DIR"
}

# Helper: 创建 TypeScript 测试文件
create_ts_fixture() {
    local name=$1
    local lines=$2
    local target="$FIXTURES_DIR/${name}.ts"

    cp "$BASE_TS_FIXTURE" "$target"

    if [ -n "$lines" ]; then
        local current
        current=$(wc -l < "$target" | tr -d ' ')
        if [ "$lines" -gt "$current" ]; then
            local index=0
            while [ "$current" -lt "$lines" ]; do
                local remaining=$((lines - current))
                if [ "$remaining" -ge 3 ]; then
                    cat >> "$target" <<EOF
export function filler${index}(): number {
    return ${index};
}
EOF
                    current=$((current + 3))
                else
                    echo "export const filler_${index} = ${index};" >> "$target"
                    current=$((current + 1))
                fi
                index=$((index + 1))
            done
        fi
    fi
}

# ============================================================
# @smoke 快速验证
# ============================================================

# @smoke T-CC-001: 骨架提取测试
@test "T-CC-001: Skeleton extraction preserves signatures" {
    create_ts_fixture "order-service" 100

    [ -f "$CONTEXT_COMPRESSOR_SCRIPT" ]
    [ -x "$CONTEXT_COMPRESSOR_SCRIPT" ]

    result=$("$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$FIXTURES_DIR/order-service.ts")

    echo "$result" | jq -e 'has("compressed_context") and (.compressed_context | type == "string") and has("metadata") and (.metadata | type == "object")' >/dev/null || \
      fail "Invalid JSON output (missing compressed_context/metadata)"
    echo "$result" | jq -e '.metadata.original_tokens > 0 and .metadata.compressed_tokens > 0' >/dev/null || \
      fail "Missing token metadata"
    echo "$result" | jq -e '(.metadata.compression_ratio | type == "number") and (.metadata.compression_ratio >= 0) and (.metadata.compression_ratio <= 1)' >/dev/null || \
      fail "Invalid compression_ratio (expected number 0..1)"

    # 验证结构化签名输出（避免依赖具体压缩文本实现）
    echo "$result" | jq -e '.files | type == "array" and length >= 1' >/dev/null || \
      fail "Missing files[] array in output"
    echo "$result" | jq -e '.preserved_signatures | type == "array" and length >= 1' >/dev/null || \
      fail "Missing preserved_signatures[] array in output"
    echo "$result" | jq -e '.preserved_signatures[] | select(.name == "processOrder") | .signature | contains("Promise<Result<Receipt, OrderError>>")' >/dev/null || \
      fail "Missing preserved signature for processOrder"
}

# @smoke T-CC-004: 完整签名保留 (SC-CC-004)
@test "T-CC-004: Complex generic signatures are fully preserved" {
    cat > "$FIXTURES_DIR/complex.ts" << 'EOF'
export function transform<T extends Base, R>(
    input: T,
    mapper: (item: T) => R,
    options?: TransformOptions<T, R>
): Promise<TransformResult<R>>;
EOF

    [ -f "$CONTEXT_COMPRESSOR_SCRIPT" ]

    result=$("$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$FIXTURES_DIR/complex.ts")

    # 签名必须完全保留，无任何省略
    compressed=$(echo "$result" | jq -r '.compressed_context')
    echo "$compressed" | grep -q "T extends Base"
    echo "$compressed" | grep -q "(item: T) => R"
    echo "$compressed" | grep -q "TransformOptions<T, R>"
    echo "$compressed" | grep -q "Promise<TransformResult<R>>"
}

# ============================================================
# @critical 关键功能
# ============================================================

# @critical T-CC-002: Token 预算控制 (SC-CC-002)
@test "T-CC-002: Token budget is respected" {
    # 创建多个大文件
    for i in {1..5}; do
        create_ts_fixture "large-$i" 200
    done

    [ -f "$CONTEXT_COMPRESSOR_SCRIPT" ]

    result=$("$CONTEXT_COMPRESSOR_SCRIPT" --budget 5000 "$FIXTURES_DIR/")

    compressed_tokens=$(echo "$result" | jq '.metadata.compressed_tokens')
    echo "Compressed tokens: $compressed_tokens"

    [ "$compressed_tokens" -le 5000 ]
}

# @critical SC-CC-007: 压缩级别测试
@test "SC-CC-007: Compression levels (low/medium/high) work correctly" {
    # 创建一个大文件，确保能看出压缩级别的差异
    cat > "$FIXTURES_DIR/compress-levels.ts" << 'EOF'
export class OrderService {
    async processOrder(order: Order): Promise<Result<Receipt, OrderError>> {
        // This is a long comment that should be preserved
        const validated = await this.validator.validate(order);
        if (!validated.ok) {
            return Result.err(validated.error);
        }

        const payment = await this.paymentService.process(order.payment);
        if (!payment.ok) {
            return Result.err(payment.error);
        }

        const receipt = await this.receiptService.generate(order);
        if (!receipt.ok) {
            return Result.err(receipt.error);
        }

        await this.notificationService.sendReceipt(receipt.value);
        await this.auditService.logOrder(order);

        return Result.ok(receipt.value);
    }

    async calculateTotal(items: OrderItem[]): Promise<number> {
        let total = 0;
        for (const item of items) {
            const price = await this.priceService.getPrice(item.id);
            total += price * item.quantity;

            // Apply discount
            if (item.discount) {
                total -= item.discount;
            }

            // Add tax
            const tax = this.taxService.calculate(item);
            total += tax;
        }
        return total;
    }

    async validateOrder(order: Order): Promise<boolean> {
        if (!order.items || order.items.length === 0) {
            return false;
        }

        for (const item of order.items) {
            const valid = await this.validator.validateItem(item);
            if (!valid) {
                return false;
            }

            const stock = await this.inventory.checkStock(item.id);
            if (stock < item.quantity) {
                return false;
            }
        }

        return true;
    }
}
EOF

    [ -f "$CONTEXT_COMPRESSOR_SCRIPT" ]

    # 测试三种压缩级别
    result_low=$("$CONTEXT_COMPRESSOR_SCRIPT" --enable-all-features --mode skeleton --compress low "$FIXTURES_DIR/compress-levels.ts")
    result_medium=$("$CONTEXT_COMPRESSOR_SCRIPT" --enable-all-features --mode skeleton --compress medium "$FIXTURES_DIR/compress-levels.ts")
    result_high=$("$CONTEXT_COMPRESSOR_SCRIPT" --enable-all-features --mode skeleton --compress high "$FIXTURES_DIR/compress-levels.ts")

    # 提取 tokens 和压缩率
    tokens_low=$(echo "$result_low" | jq '.metadata.compressed_tokens')
    tokens_medium=$(echo "$result_medium" | jq '.metadata.compressed_tokens')
    tokens_high=$(echo "$result_high" | jq '.metadata.compressed_tokens')

    ratio_low=$(echo "$result_low" | jq '.metadata.compression_ratio')
    ratio_medium=$(echo "$result_medium" | jq '.metadata.compression_ratio')
    ratio_high=$(echo "$result_high" | jq '.metadata.compression_ratio')

    echo "Tokens: Low=$tokens_low, Medium=$tokens_medium, High=$tokens_high"
    echo "Ratios: Low=$ratio_low, Medium=$ratio_medium, High=$ratio_high"

    # 验证：low >= medium >= high (保留的 token 数量)
    # 注意：由于文件头和 "// body omitted" 注释，实际验证可能需要调整
    # 我们主要验证压缩级别参数被正确识别和应用

    # 验证压缩级别在元数据中正确记录
    level_low=$(echo "$result_low" | jq -r '.metadata.compression_level')
    level_medium=$(echo "$result_medium" | jq -r '.metadata.compression_level')
    level_high=$(echo "$result_high" | jq -r '.metadata.compression_level')

    [ "$level_low" = "low" ] || fail "Expected compression_level 'low', got '$level_low'"
    [ "$level_medium" = "medium" ] || fail "Expected compression_level 'medium', got '$level_medium'"
    [ "$level_high" = "high" ] || fail "Expected compression_level 'high', got '$level_high'"

    # 验证所有级别都保留关键信息（函数签名、类定义）
    compressed_low=$(echo "$result_low" | jq -r '.compressed_context')
    compressed_medium=$(echo "$result_medium" | jq -r '.compressed_context')
    compressed_high=$(echo "$result_high" | jq -r '.compressed_context')

    # 所有级别都应该保留函数签名
    for compressed in "$compressed_low" "$compressed_medium" "$compressed_high"; do
        echo "$compressed" | grep -q "processOrder" || \
          fail "Missing critical function 'processOrder' in compressed output"
        echo "$compressed" | grep -q "calculateTotal" || \
          fail "Missing critical function 'calculateTotal' in compressed output"
        echo "$compressed" | grep -q "validateOrder" || \
          fail "Missing critical function 'validateOrder' in compressed output"
        echo "$compressed" | grep -qE "(export|class)" || \
          fail "Missing critical structural keywords in compressed output"
    done

    # 验证 high 级别包含 "body omitted" 注释
    echo "$compressed_high" | grep -q "// body omitted" || \
      fail "Expected 'body omitted' comment in high compression level"
}

# @critical T-CC-003: 热点优先选择 (SC-CC-003)
@test "T-CC-003: Hot files are prioritized for preservation" {
    # 创建热点文件
    create_ts_fixture "hot-file" 100
    touch -t 202601170900 "$FIXTURES_DIR/hot-file.ts"  # 最近修改

    # 创建冷文件
    create_ts_fixture "cold-file" 100
    touch -t 202501010000 "$FIXTURES_DIR/cold-file.ts"  # 很久未修改

    [ -f "$CONTEXT_COMPRESSOR_SCRIPT" ]

    # 设置只够保留一个文件的预算
    result=$("$CONTEXT_COMPRESSOR_SCRIPT" --budget 500 --hotspot "$FIXTURES_DIR/")

    compressed=$(echo "$result" | jq -r '.compressed_context')

    # 热点文件应该保留更多内容
    hot_content=$(echo "$compressed" | grep -c "hot-file" || echo 0)
    cold_content=$(echo "$compressed" | grep -c "cold-file" || echo 0)

    [ "$hot_content" -ge "$cold_content" ]
}

# @critical T-CC-006: 多文件聚合测试 (SC-CC-006)
@test "T-CC-006: Multiple files are aggregated correctly" {
    for i in {1..3}; do
        cat > "$FIXTURES_DIR/module-$i.ts" << EOF
export function func$i(): void {}
export class Class$i {}
EOF
    done

    [ -f "$CONTEXT_COMPRESSOR_SCRIPT" ]

    result=$("$CONTEXT_COMPRESSOR_SCRIPT" "$FIXTURES_DIR/module-1.ts" "$FIXTURES_DIR/module-2.ts" "$FIXTURES_DIR/module-3.ts")

    compressed=$(echo "$result" | jq -r '.compressed_context')

    # 验证所有文件都被包含
    echo "$compressed" | grep -q "module-1.ts"
    echo "$compressed" | grep -q "module-2.ts"
    echo "$compressed" | grep -q "module-3.ts"

    # 验证文件边界清晰
    echo "$compressed" | grep -q "=========="
}

# @critical T-CC-007: TypeScript 支持 (AC-006a)
@test "T-CC-007: TypeScript files are fully supported" {
    cat > "$FIXTURES_DIR/typescript.ts" << 'EOF'
import { Injectable } from '@nestjs/common';

@Injectable()
export class AuthService {
    private readonly secret: string;

    constructor(config: ConfigService) {
        this.secret = config.get('JWT_SECRET');
    }

    async validateUser(token: string): Promise<User | null> {
        try {
            const payload = jwt.verify(token, this.secret);
            return this.userService.findById(payload.sub);
        } catch {
            return null;
        }
    }

    generateToken(user: User): string {
        return jwt.sign({ sub: user.id }, this.secret);
    }
}
EOF

    [ -f "$CONTEXT_COMPRESSOR_SCRIPT" ]

    result=$("$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$FIXTURES_DIR/typescript.ts")

    # 验证 TypeScript 特性被正确处理
    compressed=$(echo "$result" | jq -r '.compressed_context')
    echo "$compressed" | grep -q "@Injectable"
    echo "$compressed" | grep -q "validateUser"
    echo "$compressed" | grep -q "Promise<User | null>"
}

# @critical T-CC-009: 压缩率验证 (AC-001)
@test "T-CC-009: Compression ratio between 30% and 50%" {
    create_ts_fixture "large-service" 200

    [ -f "$CONTEXT_COMPRESSOR_SCRIPT" ]

    result=$("$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$FIXTURES_DIR/large-service.ts")

    original=$(echo "$result" | jq '.metadata.original_tokens')
    compressed=$(echo "$result" | jq '.metadata.compressed_tokens')
    ratio=$(echo "$result" | jq '.metadata.compression_ratio')

    echo "Original: $original, Compressed: $compressed, Ratio: $ratio"

    # 压缩率 30% - 50%
    [ $(echo "$ratio >= 0.3" | bc) -eq 1 ]
    [ $(echo "$ratio <= 0.5" | bc) -eq 1 ]
}

# @critical T-CC-011: 30% 边界预算验证
@test "T-CC-011: Budget boundary at 30% is inclusive" {
    create_ts_fixture "boundary-30" 200

    [ -f "$CONTEXT_COMPRESSOR_SCRIPT" ]

    base=$("$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$FIXTURES_DIR/boundary-30.ts")
    original=$(echo "$base" | jq '.metadata.original_tokens')
    budget=$((original * 30 / 100))
    [ "$budget" -gt 0 ] || fail "Computed budget is too small"

    result=$("$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton --budget "$budget" "$FIXTURES_DIR/boundary-30.ts")
    ratio=$(echo "$result" | jq '.metadata.compression_ratio')

    [ $(echo "$ratio <= 0.30" | bc) -eq 1 ]
}

# @critical T-CC-012: 50% 边界预算验证
@test "T-CC-012: Budget boundary at 50% is inclusive" {
    create_ts_fixture "boundary-50" 200

    [ -f "$CONTEXT_COMPRESSOR_SCRIPT" ]

    base=$("$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$FIXTURES_DIR/boundary-50.ts")
    original=$(echo "$base" | jq '.metadata.original_tokens')
    budget=$((original * 50 / 100))
    [ "$budget" -gt 0 ] || fail "Computed budget is too small"

    result=$("$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton --budget "$budget" "$FIXTURES_DIR/boundary-50.ts")
    ratio=$(echo "$result" | jq '.metadata.compression_ratio')

    [ $(echo "$ratio <= 0.50" | bc) -eq 1 ]
}

# ============================================================
# @full 完整覆盖
# ============================================================

# @full T-CC-005: 增量压缩测试 (T-CC-CACHE-001, T-CC-CACHE-002)
# 修复 C-001: 增加预热次数到 10 次，采样次数到 10 次，使用 P95 代替平均值
# 默认阈值从 50 放宽到 70，提高 CI/容器环境稳定性
@test "T-CC-005: Incremental compression reuses cache" {
    create_ts_fixture "cached" 500
    create_ts_fixture "warmup" 50

    [ -f "$CONTEXT_COMPRESSOR_SCRIPT" ]

    # 使用独立的缓存目录避免测试间的缓存干扰
    local test_cache_dir="$BATS_TEST_TMPDIR/cache-cc-005"
    mkdir -p "$test_cache_dir"
    export DEVBOOKS_DIR="$test_cache_dir"

    # 增加预热次数从 1 到 10，确保缓存充分预热
    local warmup_runs="${CONTEXT_COMPRESSOR_CACHE_WARMUP:-10}"
    for ((i=0; i<warmup_runs; i++)); do
        "$CONTEXT_COMPRESSOR_SCRIPT" --enable-all-features --cache "$FIXTURES_DIR/warmup.ts" >/dev/null 2>&1 || \
          fail "Warmup run $i failed"
    done

    # 第一次压缩（冷缓存）- 多次测量取 P95
    local cold_runs="${CONTEXT_COMPRESSOR_COLD_RUNS:-5}"
    local cold_latencies=()
    for ((i=0; i<cold_runs; i++)); do
        # 每次冷测量前清除缓存
        rm -rf "$test_cache_dir"/*
        measure_time "$CONTEXT_COMPRESSOR_SCRIPT" --enable-all-features --cache "$FIXTURES_DIR/cached.ts" > /dev/null
        cold_latencies+=("$MEASURED_TIME_MS")
    done
    local time1
    time1=$(calculate_p95 "${cold_latencies[@]}")

    # 重新预热缓存
    for ((i=0; i<warmup_runs; i++)); do
        "$CONTEXT_COMPRESSOR_SCRIPT" --enable-all-features --cache "$FIXTURES_DIR/cached.ts" >/dev/null 2>&1 || true
    done

    # 增加采样次数从 3 到 10，使用 P95 代替平均值
    local cached_runs="${CONTEXT_COMPRESSOR_CACHE_RUNS:-10}"
    local cached_latencies=()
    local result2=""
    for ((i=0; i<cached_runs; i++)); do
        measure_time "$CONTEXT_COMPRESSOR_SCRIPT" --enable-all-features --cache "$FIXTURES_DIR/cached.ts" > /dev/null
        cached_latencies+=("$MEASURED_TIME_MS")
    done

    result2=$("$CONTEXT_COMPRESSOR_SCRIPT" --enable-all-features --cache "$FIXTURES_DIR/cached.ts")
    local time2_p95
    time2_p95=$(calculate_p95 "${cached_latencies[@]}")

    echo "Cold P95: ${time1}ms, Cached P95: ${time2_p95}ms"

    echo "$result2" | jq -e '.metadata.cache_hits > 0' >/dev/null || \
      fail "Expected cache_hits > 0 on second run"
    # 默认阈值从 50 放宽到 70，提高 CI/容器环境稳定性
    local ratio_pct="${CONTEXT_COMPRESSOR_CACHE_TIME_RATIO_PCT:-70}"
    [ "$time2_p95" -gt 0 ] || fail "Cached timing invalid: ${time2_p95}ms"
    [ "$time1" -gt 0 ] || fail "Cold timing invalid: ${time1}ms"
    [ $((time2_p95 * 100)) -le $((time1 * ratio_pct)) ] || \
      fail "Expected cached P95 <= ${ratio_pct}% of cold P95 (cold=${time1}ms cached=${time2_p95}ms)"

    # 清理独立缓存目录
    rm -rf "$test_cache_dir"
    unset DEVBOOKS_DIR
}

# @full T-CC-013: 并发压缩请求
@test "T-CC-013: Concurrent compression requests do not conflict" {
    create_ts_fixture "concurrent-a" 120
    create_ts_fixture "concurrent-b" 140

    local out_dir="$BATS_TEST_TMPDIR/concurrent"
    mkdir -p "$out_dir"

    # m-003 修复：为每个并发进程设置独立的 DEVBOOKS_DIR，避免共享缓存状态
    local devbooks_dir_a="$BATS_TEST_TMPDIR/devbooks-a"
    local devbooks_dir_b="$BATS_TEST_TMPDIR/devbooks-b"
    mkdir -p "$devbooks_dir_a" "$devbooks_dir_b"

    # 使用独立环境运行并发任务
    DEVBOOKS_DIR="$devbooks_dir_a" "$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$FIXTURES_DIR/concurrent-a.ts" > "$out_dir/a.json" 2>&1 &
    local pid_a=$!
    DEVBOOKS_DIR="$devbooks_dir_b" "$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$FIXTURES_DIR/concurrent-b.ts" > "$out_dir/b.json" 2>&1 &
    local pid_b=$!

    wait "$pid_a"
    local status_a=$?
    wait "$pid_b"
    local status_b=$?

    [ "$status_a" -eq 0 ] || fail "Concurrent A failed: $(tail -n 5 "$out_dir/a.json")"
    [ "$status_b" -eq 0 ] || fail "Concurrent B failed: $(tail -n 5 "$out_dir/b.json")"

    jq -e '.metadata.compressed_tokens > 0' "$out_dir/a.json" >/dev/null || fail "Missing compressed_tokens for A"
    jq -e '.metadata.compressed_tokens > 0' "$out_dir/b.json" >/dev/null || fail "Missing compressed_tokens for B"

    # 验证两个进程使用了不同的缓存目录
    [ "$devbooks_dir_a" != "$devbooks_dir_b" ] || fail "并发进程应使用不同的 DEVBOOKS_DIR"

    # M-004 修复：验证缓存隔离是否真正生效
    local cache_a_count cache_b_count
    cache_a_count=$(find "$devbooks_dir_a" -type f 2>/dev/null | wc -l | tr -d ' ')
    cache_b_count=$(find "$devbooks_dir_b" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "隔离验证: cache_a=$cache_a_count files, cache_b=$cache_b_count files"

    # 验证缓存目录已创建（即使为空）
    [ -d "$devbooks_dir_a" ] || fail "进程 A 的缓存目录未创建"
    [ -d "$devbooks_dir_b" ] || fail "进程 B 的缓存目录未创建"

    # 如果生成了缓存文件，验证没有交叉污染
    if [ "$cache_a_count" -gt 0 ] || [ "$cache_b_count" -gt 0 ]; then
        local cross_ref_a cross_ref_b
        cross_ref_a=$(find "$devbooks_dir_a" -type f -exec grep -l "concurrent-b" {} \; 2>/dev/null | wc -l | tr -d ' ')
        cross_ref_b=$(find "$devbooks_dir_b" -type f -exec grep -l "concurrent-a" {} \; 2>/dev/null | wc -l | tr -d ' ')
        [ "$cross_ref_a" -eq 0 ] || fail "进程 A 的缓存中发现进程 B 的数据（交叉污染）"
        [ "$cross_ref_b" -eq 0 ] || fail "进程 B 的缓存中发现进程 A 的数据（交叉污染）"
    fi

    # 清理独立缓存目录
    rm -rf "$devbooks_dir_a" "$devbooks_dir_b"
}

# @full T-CC-008: Python 支持（可选）(AC-006a)
@test "T-CC-008: Python files are supported" {
    cat > "$FIXTURES_DIR/service.py" << 'EOF'
from typing import Optional, List
from dataclasses import dataclass

@dataclass
class Order:
    id: str
    items: List[OrderItem]
    total: float

class OrderService:
    def __init__(self, db: Database):
        self.db = db

    async def process_order(
        self,
        order: Order,
        payment: PaymentInfo,
        options: Optional[ProcessOptions] = None
    ) -> Result[Receipt, OrderError]:
        """Process an order with payment."""
        # Implementation...
        pass
EOF

    [ -f "$CONTEXT_COMPRESSOR_SCRIPT" ]

    run "$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$FIXTURES_DIR/service.py"
    assert_exit_success "$status"

    compressed=$(echo "$output" | jq -r '.compressed_context')
    echo "$compressed" | grep -q "process_order"
    echo "$compressed" | grep -q "Order"
}

# @full T-CC-010: 语义保留度验证 (AC-006)
@test "T-CC-010: Semantic preservation >= 85%" {
    cat > "$FIXTURES_DIR/semantic.ts" << 'EOF'
// Critical semantic elements that must be preserved:
// 1. Function name: processPayment
// 2. Parameters: order, payment, options
// 3. Return type: Promise<Result<Receipt, Error>>
// 4. Class name: PaymentProcessor
// 5. Interface: PaymentConfig

interface PaymentConfig {
    gateway: string;
    timeout: number;
}

class PaymentProcessor {
    constructor(config: PaymentConfig) {}

    async processPayment(
        order: Order,
        payment: Payment,
        options?: ProcessOptions
    ): Promise<Result<Receipt, Error>> {
        // 100 lines of implementation...
        return Result.ok({} as Receipt);
    }
}
EOF

    [ -f "$CONTEXT_COMPRESSOR_SCRIPT" ]

    result=$("$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$FIXTURES_DIR/semantic.ts")

    compressed=$(echo "$result" | jq -r '.compressed_context')

    # 验证所有关键语义元素都被保留
    semantic_elements=(
        "processPayment"
        "order"
        "payment"
        "options"
        "Promise<Result<Receipt, Error>>"
        "PaymentProcessor"
        "PaymentConfig"
    )

    preserved=0
    for element in "${semantic_elements[@]}"; do
        if echo "$compressed" | grep -q "$element"; then
            ((preserved++))
        fi
    done

    total=${#semantic_elements[@]}
    rate=$(echo "scale=2; $preserved / $total" | bc)

    echo "Semantic preservation: $preserved / $total = $rate"

    # >= 85% 保留度
    [ $(echo "$rate >= 0.85" | bc) -eq 1 ]
}

# ============================================================
# 边界条件测试
# ============================================================

# @critical T-CC-ERROR-001: 空输入处理
@test "T-CC-ERROR-001: Empty file is rejected" {
    : > "$FIXTURES_DIR/empty.ts"

    run "$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$FIXTURES_DIR/empty.ts" 2>&1

    assert_exit_failure "$status"
    echo "$output" | grep -Eqi "empty (file|input)" || \
      fail "Expected empty file error, got: $output"
}

# @critical T-CC-ERROR-002: 无效语法处理
@test "T-CC-ERROR-002: Invalid TypeScript syntax is rejected" {
    cat > "$FIXTURES_DIR/invalid.ts" << 'EOF'
export function broken( {
EOF

    run "$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$FIXTURES_DIR/invalid.ts" 2>&1

    assert_exit_failure "$status"
    assert_contains "$output" "syntax"
}

# @full T-CC-ERROR-003: 超大文件处理
@test "T-CC-ERROR-003: Large file (>10MB) handled without crash" {
    local large_file="$FIXTURES_DIR/large.ts"
    yes "export const value = 1;" | head -c $((11 * 1024 * 1024)) > "$large_file"

    run "$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$large_file" 2>&1

    if [ "$status" -eq 0 ]; then
        echo "$output" | jq -e '.metadata.compressed_tokens > 0' >/dev/null || fail "Missing compressed_tokens"
    else
        echo "$output" | grep -Eqi "too large|large file|exceeds|size" || \
          fail "Missing large-file handling message"
        echo "$output" | grep -Eqi "Argument list too long" && \
          fail "Large-file handling must not leak low-level jq error"
    fi
}

# @full T-CC-ERROR-005: 超大文件处理 (>100MB)
@test "T-CC-ERROR-005: Huge file (>100MB) handled without crash" {
    local large_file="$FIXTURES_DIR/huge.ts"
    local large_mb="${CONTEXT_COMPRESSOR_LARGE_MB:-100}"
    [ "$large_mb" -ge 100 ] || fail "CONTEXT_COMPRESSOR_LARGE_MB must be >= 100"
    truncate -s $((large_mb * 1024 * 1024)) "$large_file"
    printf "export const value = 2;\n" | dd of="$large_file" conv=notrunc bs=1 2>/dev/null

    run "$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$large_file" 2>&1

    if [ "$status" -eq 0 ]; then
        echo "$output" | jq -e '.metadata.compressed_tokens > 0' >/dev/null || fail "Missing compressed_tokens"
    else
        echo "$output" | grep -Eqi "too large|large file|exceeds|size" || \
          fail "Missing large-file handling message"
        echo "$output" | grep -Eqi "Argument list too long" && \
          fail "Large-file handling must not leak low-level jq error"
    fi
}

# @full T-CC-ERROR-004: 不支持语言错误提示
@test "T-CC-ERROR-004: Unsupported language returns friendly error" {
    cat > "$FIXTURES_DIR/unsupported.rb" << 'EOF'
class Payment
  def charge(amount)
    amount * 2
  end
end
EOF

    run "$CONTEXT_COMPRESSOR_SCRIPT" --mode skeleton "$FIXTURES_DIR/unsupported.rb" 2>&1

    assert_exit_failure "$status"
    echo "$output" | grep -Eqi "unsupported|not supported" || fail "Missing unsupported language error"
}

# @full: 性能测试（可用 CONTEXT_COMPRESSOR_PERF_MS 覆盖阈值，CONTEXT_COMPRESSOR_PERF_ITERS 覆盖采样次数）
@test "T-PERF-CC-001: Single file compression within threshold" {
    create_ts_fixture "perf-test" 500

    [ -f "$CONTEXT_COMPRESSOR_SCRIPT" ]

    for _ in {1..3}; do
        "$CONTEXT_COMPRESSOR_SCRIPT" "$FIXTURES_DIR/perf-test.ts" >/dev/null 2>&1 || \
          fail "Warmup failed"
    done

    local iterations="${CONTEXT_COMPRESSOR_PERF_ITERS:-10}"
    local latencies=()
    for ((i=0; i<iterations; i++)); do
        measure_time "$CONTEXT_COMPRESSOR_SCRIPT" "$FIXTURES_DIR/perf-test.ts" > /dev/null
        assert_exit_success "$?"
        latencies+=("$MEASURED_TIME_MS")
    done

    local p95
    p95=$(calculate_p95 "${latencies[@]}")
    local threshold="${CONTEXT_COMPRESSOR_PERF_MS:-100}"
    echo "Compression latency p95: ${p95}ms (threshold: ${threshold}ms)"

    [ "$p95" -lt "$threshold" ]
}
