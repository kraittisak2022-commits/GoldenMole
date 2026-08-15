import { supabase } from '../lib/supabase';
import { calcPayrollTotal } from '../calc/payroll';
import type { FaEmployee, FaPayrollSlip } from '../types';
import { newId } from '../types';
import { saveLedgerEntry } from './ledger';

const map = (row: any): FaPayrollSlip => ({
  id: row.id,
  payDate: row.pay_date,
  employeeId: row.employee_id,
  employeeName: row.employee_name,
  employeeType: row.employee_type,
  basePay: Number(row.base_pay) || 0,
  workDays: Number(row.work_days) || 0,
  otAmount: Number(row.ot_amount) || 0,
  specialAmount: Number(row.special_amount) || 0,
  total: Number(row.total) || 0,
  ledgerEntryId: row.ledger_entry_id,
  createdAt: row.created_at,
});

export async function listPayrollSlips(): Promise<FaPayrollSlip[]> {
  const { data, error } = await supabase
    .from('fa_payroll_slips')
    .select('*')
    .order('pay_date', { ascending: false });
  if (error) throw new Error(error.message);
  return (data || []).map(map);
}

export async function getPayrollSlip(id: string): Promise<FaPayrollSlip | null> {
  const { data, error } = await supabase.from('fa_payroll_slips').select('*').eq('id', id).maybeSingle();
  if (error) throw new Error(error.message);
  return data ? map(data) : null;
}

export async function createPayrollSlip(input: {
  employee: FaEmployee;
  payDate: string;
  workDays: number;
  otAmount: number;
  specialAmount: number;
  postToLedger?: boolean;
  salaryCategoryId?: string;
  createdBy?: string;
}): Promise<FaPayrollSlip> {
  const total = calcPayrollTotal({
    employeeType: input.employee.type,
    basePay: input.employee.basePay,
    workDays: input.workDays,
    otAmount: input.otAmount,
    specialAmount: input.specialAmount,
  });

  let ledgerEntryId: string | null = null;
  if (input.postToLedger && input.salaryCategoryId) {
    const ledger = await saveLedgerEntry({
      date: input.payDate,
      description: `จ่ายเงินเดือน: ${input.employee.name}`,
      categoryId: input.salaryCategoryId,
      entryType: 'expense',
      amount: total,
      source: 'payroll',
      createdBy: input.createdBy ?? null,
    });
    ledgerEntryId = ledger.id;
  }

  const id = newId('pay');
  const row = {
    id,
    pay_date: input.payDate,
    employee_id: input.employee.id,
    employee_name: input.employee.name,
    employee_type: input.employee.type,
    base_pay: input.employee.basePay,
    work_days: Number(input.workDays) || 0,
    ot_amount: Number(input.otAmount) || 0,
    special_amount: Number(input.specialAmount) || 0,
    total,
    ledger_entry_id: ledgerEntryId,
  };

  const { data, error } = await supabase.from('fa_payroll_slips').insert(row).select('*').single();
  if (error) throw new Error(error.message);
  return map(data);
}
