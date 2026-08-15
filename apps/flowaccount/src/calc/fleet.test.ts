import { describe, expect, it } from 'vitest';
import { calcFleetCost, calcFleetMargin } from './fleet';

describe('fleet calc', () => {
  it('cost = dailyRate * days + ot', () => {
    expect(calcFleetCost({ dailyRate: 3500, workDays: 5, otAmount: 1000 })).toBe(18500);
  });

  it('margin = income - cost', () => {
    expect(calcFleetMargin(22000, 18500)).toBe(3500);
  });
});
