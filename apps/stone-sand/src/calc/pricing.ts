import type { DiscountType } from '../types';

export const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

export function lineAmount(unitPrice: number, quantity: number): number {
  if (!(unitPrice > 0) || !(quantity > 0)) return 0;
  return round2(unitPrice * quantity);
}

/** บาทต่อคิว off one line, capped at the unit price. */
export function lineDiscount(unitPrice: number, quantity: number, discountPerUnit = 0): number {
  if (!(discountPerUnit > 0) || !(quantity > 0)) return 0;
  return round2(Math.min(discountPerUnit, Math.max(0, unitPrice)) * quantity);
}

export interface TotalsInput {
  items: { unitPrice: number; quantity: number; discountPerUnit?: number }[];
  feePerTrip: number;
  trips: number;
  remoteSurcharge: number;
  discountType: DiscountType;
  discountValue: number;
}

export interface Totals {
  subtotal: number;
  deliveryTotal: number;
  /** Sum of the per-คิว discounts on the lines. */
  itemDiscount: number;
  /** Per-คิว discounts plus the bill discount. */
  discountAmount: number;
  total: number;
  totalQuantity: number;
}

/**
 * Per-คิว discounts come off each line first. Percent discounts then apply to the discounted
 * product subtotal only; baht discounts can also cover delivery. The grand total never goes below zero.
 */
export function computeTotals(input: TotalsInput): Totals {
  const subtotal = round2(input.items.reduce((sum, it) => sum + lineAmount(it.unitPrice, it.quantity), 0));
  const totalQuantity = round2(input.items.reduce((sum, it) => sum + (it.quantity > 0 ? it.quantity : 0), 0));
  const trips = Math.max(0, Math.floor(input.trips || 0));
  const deliveryTotal = round2(Math.max(0, input.feePerTrip || 0) * trips + Math.max(0, input.remoteSurcharge || 0));
  const gross = subtotal + deliveryTotal;
  const itemDiscount = round2(
    input.items.reduce((sum, it) => sum + lineDiscount(it.unitPrice, it.quantity, it.discountPerUnit), 0),
  );

  const value = Math.max(0, input.discountValue || 0);
  const billDiscount =
    input.discountType === 'percent' ? ((subtotal - itemDiscount) * Math.min(value, 100)) / 100 : value;
  const discountAmount = round2(Math.min(itemDiscount + billDiscount, gross));

  return {
    subtotal,
    deliveryTotal,
    itemDiscount,
    discountAmount,
    total: round2(gross - discountAmount),
    totalQuantity,
  };
}
