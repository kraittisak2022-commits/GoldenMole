import type { Order } from '../types';
import { periodStats } from './stats';

const make = (patch: Partial<Order>): Order =>
  ({
    cancelled: false,
    subtotal: 1000,
    deliveryTotal: 300,
    discountAmount: 100,
    total: 1200,
    driverWage: 200,
    paymentStatus: 'paid',
    items: [{ productId: 'fill-sand', name: 'ทรายถม', unit: 'คิว', unitPrice: 220, quantity: 5, amount: 1100 }],
    ...patch,
  }) as Order;

describe('periodStats', () => {
  it('sums live orders and ignores cancelled ones', () => {
    const s = periodStats([make({}), make({ paymentStatus: 'credit' }), make({ cancelled: true })]);
    expect(s.orderCount).toBe(2);
    expect(s.net).toBe(2400);
    expect(s.deliveryFees).toBe(600);
    expect(s.driverWages).toBe(400);
    expect(s.paid).toBe(1200);
    expect(s.quantityByProduct).toEqual([{ name: 'ทรายถม', unit: 'คิว', quantity: 10, amount: 2200 }]);
  });

  it('totals คิว, trips and money still to collect', () => {
    const s = periodStats([make({ trips: 2 }), make({ trips: 1, paymentStatus: 'unpaid' }), make({ trips: 3, cancelled: true })]);
    expect(s.quantity).toBe(10);
    expect(s.trips).toBe(3);
    expect(s.outstanding).toBe(1200);
  });
});
