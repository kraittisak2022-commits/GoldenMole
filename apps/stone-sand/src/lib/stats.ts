import type { Order } from '../types';

export interface PeriodStats {
  orderCount: number;
  productSales: number;
  deliveryFees: number;
  discounts: number;
  net: number;
  driverWages: number;
  paid: number;
  /** Unpaid and credit totals still to collect. */
  outstanding: number;
  quantity: number;
  trips: number;
  quantityByProduct: { name: string; unit: string; quantity: number; amount: number }[];
}

export function periodStats(orders: Order[]): PeriodStats {
  const live = orders.filter((o) => !o.cancelled);
  const byProduct = new Map<string, { name: string; unit: string; quantity: number; amount: number }>();
  for (const o of live) {
    for (const it of o.items) {
      const key = it.productId ?? it.name;
      const row = byProduct.get(key) ?? { name: it.name, unit: it.unit, quantity: 0, amount: 0 };
      row.quantity += it.quantity;
      row.amount += it.amount;
      byProduct.set(key, row);
    }
  }
  const sum = (f: (o: Order) => number) => live.reduce((s, o) => s + f(o), 0);
  const quantityByProduct = [...byProduct.values()].sort((a, b) => b.amount - a.amount);
  return {
    orderCount: live.length,
    productSales: sum((o) => o.subtotal),
    deliveryFees: sum((o) => o.deliveryTotal),
    discounts: sum((o) => o.discountAmount),
    net: sum((o) => o.total),
    driverWages: sum((o) => o.driverWage),
    paid: sum((o) => (o.paymentStatus === 'paid' ? o.total : 0)),
    outstanding: sum((o) => (o.paymentStatus === 'paid' ? 0 : o.total)),
    quantity: quantityByProduct.reduce((s, p) => s + p.quantity, 0),
    trips: sum((o) => o.trips || 0),
    quantityByProduct,
  };
}
