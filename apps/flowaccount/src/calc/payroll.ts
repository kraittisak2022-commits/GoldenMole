import type { EmployeeType } from '../types';

export function calcPayrollTotal(input: {
  employeeType: EmployeeType;
  basePay: number;
  workDays: number;
  otAmount: number;
  specialAmount: number;
}): number {
  const base = Number(input.basePay) || 0;
  const days = Number(input.workDays) || 0;
  const ot = Number(input.otAmount) || 0;
  const special = Number(input.specialAmount) || 0;

  if (input.employeeType === 'monthly') {
    return round2(base + ot + special);
  }
  return round2(base * days + ot + special);
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
