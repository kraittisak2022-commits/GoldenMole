export function calcFleetCost(input: {
  dailyRate: number;
  workDays: number;
  otAmount: number;
}): number {
  const rate = Number(input.dailyRate) || 0;
  const days = Number(input.workDays) || 0;
  const ot = Number(input.otAmount) || 0;
  return round2(rate * days + ot);
}

export function calcFleetMargin(incomeAmount: number, totalCost: number): number {
  return round2((Number(incomeAmount) || 0) - (Number(totalCost) || 0));
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
