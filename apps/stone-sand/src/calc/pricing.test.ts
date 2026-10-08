import { computeTotals, lineAmount } from './pricing';

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
});
