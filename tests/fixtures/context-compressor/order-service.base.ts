export type Result<T, E> =
    | { ok: true; value: T }
    | { ok: false; error: E };

export interface Order {
    id: string;
    items: OrderItem[];
    totalCents: number;
}

export interface OrderItem {
    sku: string;
    quantity: number;
    priceCents: number;
}

export interface PaymentInfo {
    provider: "stripe" | "paypal";
    token: string;
    currency: "USD" | "EUR";
}

export interface Receipt {
    receiptId: string;
    paidAt: string;
}

export type OrderError =
    | { code: "OUT_OF_STOCK"; message: string }
    | { code: "PAYMENT_FAILED"; message: string };

export interface OrderRepository {
    reserveItems(order: Order): Promise<void>;
    releaseItems(order: Order): Promise<void>;
    markPaid(order: Order, receipt: Receipt): Promise<void>;
}

export interface PaymentGateway {
    charge(info: PaymentInfo, amountCents: number): Promise<Receipt>;
}

export class OrderService {
    constructor(
        private readonly repo: OrderRepository,
        private readonly payment: PaymentGateway
    ) {}

    async processOrder(
        order: Order,
        payment: PaymentInfo
    ): Promise<Result<Receipt, OrderError>> {
        await this.repo.reserveItems(order);
        try {
            const receipt = await this.payment.charge(payment, order.totalCents);
            await this.repo.markPaid(order, receipt);
            return { ok: true, value: receipt };
        } catch (error) {
            await this.repo.releaseItems(order);
            return { ok: false, error: { code: "PAYMENT_FAILED", message: String(error) } };
        }
    }
}
