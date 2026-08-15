export type CategoryKind = 'income' | 'expense' | 'both';
export type EntryType = 'income' | 'expense';
export type LedgerSource = 'manual' | 'reimbursement' | 'payroll' | 'fleet';
export type EmployeeType = 'monthly' | 'daily' | 'daily_driver';
export type ReimbursementStatus = 'pending' | 'approved' | 'rejected';

export interface FaCategory {
  id: string;
  name: string;
  kind: CategoryKind;
  archived: boolean;
  sortOrder: number;
}

export interface FaEmployee {
  id: string;
  name: string;
  type: EmployeeType;
  basePay: number;
  inactive: boolean;
}

export interface FaFleetAsset {
  id: string;
  name: string;
  dailyRate: number;
  inactive: boolean;
}

export interface FaLedgerEntry {
  id: string;
  date: string;
  description: string;
  categoryId: string;
  entryType: EntryType;
  amount: number;
  source: LedgerSource;
  sourceId?: string | null;
  createdBy?: string | null;
  createdAt?: string;
}

export interface FaReimbursement {
  id: string;
  date: string;
  payerName: string;
  description: string;
  amount: number;
  status: ReimbursementStatus;
  approvedCategoryId?: string | null;
  ledgerEntryId?: string | null;
  approvedBy?: string | null;
  approvedAt?: string | null;
  createdAt?: string;
}

export interface FaPayrollSlip {
  id: string;
  payDate: string;
  employeeId: string;
  employeeName: string;
  employeeType: EmployeeType;
  basePay: number;
  workDays: number;
  otAmount: number;
  specialAmount: number;
  total: number;
  ledgerEntryId?: string | null;
  createdAt?: string;
}

export interface FaFleetLog {
  id: string;
  workDate: string;
  assetId: string;
  driverName: string;
  workDays: number;
  otAmount: number;
  incomeAmount: number;
  totalCost: number;
  dailyRateSnapshot: number;
  assetNameSnapshot: string;
  ledgerEntryId?: string | null;
  createdAt?: string;
}

export const EMPLOYEE_TYPE_LABEL: Record<EmployeeType, string> = {
  monthly: 'พนักงานเงินเดือน',
  daily: 'พนักงานรายวัน',
  daily_driver: 'พนักงานขับรถรายวัน',
};

export function newId(prefix: string): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return `${prefix}-${crypto.randomUUID()}`;
  }
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

export function formatMoney(n: number): string {
  return new Intl.NumberFormat('th-TH', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  }).format(n);
}
