import { computeTotals, lineAmount, lineDiscount } from './pricing';

describe('lineAmount', () => {
  it('matches the price list for 1, 3 and 5 คิว', () => {
    expect(lineAmount(400, 1)).toBe(400);
    expect(lineAmount(400, 3)).toBe(1200);
    expect(lineAmount(400, 5)).toBe(2000);
    expect(lineAmount(300, 5)).toBe(1500);
    expect(lineAmount(220, 3)).toBe(660);
    expect(lineAmount(220, 5)).toBe(1100);
  });

  it('handles fractional quantities and invalid input', () => {
    expect(lineAmount(220, 1.5)).toBe(330);
    expect(lineAmount(400, 0)).toBe(0);
    expect(lineAmount(400, -2)).toBe(0);
  });
});

describe('computeTotals', () => {
  const base = {
    items: [
      { unitPrice: 400, quantity: 5 },
      { unitPrice: 220, quantity: 5 },
    ],
    feePerTrip: 350,
    trips: 2,
    remoteSurcharge: 0,
    discountType: 'baht' as const,
    discountValue: 0,
  };

  it('adds products and delivery per trip', () => {
    expect(computeTotals(base)).toEqual({
      subtotal: 3100,
      deliveryTotal: 700,
      itemDiscount: 0,
      deliveryDiscount: 0,
      billDiscount: 0,
      discountAmount: 0,
      total: 3800,
      totalQuantity: 10,
    });
  });

  it('adds the remote surcharge once', () => {
    expect(computeTotals({ ...base, remoteSurcharge: 200 }).deliveryTotal).toBe(900);
  });

  it('applies a baht discount', () => {
    const t = computeTotals({ ...base, discountValue: 100 });
    expect(t.discountAmount).toBe(100);
    expect(t.total).toBe(3700);
  });

  it('applies a percent discount to products only', () => {
    const t = computeTotals({ ...base, discountType: 'percent', discountValue: 10 });
    expect(t.discountAmount).toBe(310);
    expect(t.total).toBe(3490);
  });

  it('never goes below zero', () => {
    expect(computeTotals({ ...base, discountValue: 99999 }).total).toBe(0);
    expect(computeTotals({ ...base, discountType: 'percent', discountValue: 500 }).discountAmount).toBe(3100);
  });

  it('pickup orders have no delivery', () => {
    expect(computeTotals({ ...base, feePerTrip: 0, trips: 0 }).total).toBe(3100);
  });

  it('takes a per-คิว discount off each product separately', () => {
    const t = computeTotals({
      ...base,
      items: [
        { unitPrice: 400, quantity: 5, discountPerUnit: 30 },
        { unitPrice: 220, quantity: 5, discountPerUnit: 20 },
      ],
    });
    expect(t.subtotal).toBe(3100);
    expect(t.itemDiscount).toBe(250);
    expect(t.discountAmount).toBe(250);
    expect(t.total).toBe(3550);
  });

  it('stacks the bill discount on top; percent uses the discounted products', () => {
    const items = [{ unitPrice: 400, quantity: 5, discountPerUnit: 40 }];
    expect(computeTotals({ ...base, items, discountValue: 100 }).discountAmount).toBe(300);
    expect(computeTotals({ ...base, items, discountType: 'percent', discountValue: 10 }).discountAmount).toBe(380);
  });

  it('takes ส่วนลดค่าส่ง off the delivery fee, never more than the fee', () => {
    const t = computeTotals({ ...base, deliveryDiscount: 100 });
    expect(t.deliveryTotal).toBe(700);
    expect(t.deliveryDiscount).toBe(100);
    expect(t.discountAmount).toBe(100);
    expect(t.total).toBe(3700);
    expect(computeTotals({ ...base, deliveryDiscount: 5000 }).deliveryDiscount).toBe(700);
    expect(computeTotals({ ...base, feePerTrip: 0, trips: 0, deliveryDiscount: 100 }).deliveryDiscount).toBe(0);
  });

  it('keeps the bill discount separate from ส่วนลดค่าส่ง; percent still uses products only', () => {
    const t = computeTotals({ ...base, deliveryDiscount: 100, discountType: 'percent', discountValue: 10 });
    expect(t.billDiscount).toBe(310);
    expect(t.discountAmount).toBe(410);
    expect(t.total).toBe(3390);
  });
});

describe('lineDiscount', () => {
  it('never discounts more than the unit price', () => {
    expect(lineDiscount(220, 5, 20)).toBe(100);
    expect(lineDiscount(220, 5, 999)).toBe(1100);
    expect(lineDiscount(220, 0, 20)).toBe(0);
    expect(lineDiscount(220, 5)).toBe(0);
  });
});
