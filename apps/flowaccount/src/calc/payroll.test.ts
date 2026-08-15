import { describe, expect, it } from 'vitest';
import { calcPayrollTotal } from './payroll';

describe('calcPayrollTotal', () => {
  it('monthly: base + ot + special (days not multiplied)', () => {
    expect(
      calcPayrollTotal({
        employeeType: 'monthly',
        basePay: 18000,
        workDays: 22,
        otAmount: 1000,
        specialAmount: 500,
      }),
    ).toBe(19500);
  });

  it('daily: base * days + ot + special', () => {
    expect(
      calcPayrollTotal({
        employeeType: 'daily',
        basePay: 500,
        workDays: 12,
        otAmount: 500,
        specialAmount: 200,
      }),
    ).toBe(6700);
  });

  it('daily_driver uses same formula as daily', () => {
    expect(
      calcPayrollTotal({
        employeeType: 'daily_driver',
        basePay: 650,
        workDays: 10,
        otAmount: 0,
        specialAmount: 0,
      }),
    ).toBe(6500);
  });
});
