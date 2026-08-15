import { supabase } from '../lib/supabase';
import type { FaSalaryAdvance } from '../types';
import { newId } from '../types';

const map = (row: any): FaSalaryAdvance => ({
  id: row.id,
  advanceDate: row.advance_date,
  employeeId: row.employee_id,
  employeeName: row.employee_name || '',
  amount: Number(row.amount) || 0,
  notes: row.notes || '',
  createdAt: row.created_at,
});

export async function listSalaryAdvances(opts?: {
  monthKey?: string;
}): Promise<FaSalaryAdvance[]> {
  let q = supabase.from('fa_salary_advances').select('*').order('advance_date', { ascending: false });
  if (opts?.monthKey) {
    q = q.gte('advance_date', `${opts.monthKey}-01`).lte('advance_date', `${opts.monthKey}-31`);
  }
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return (data || []).map(map);
}

export async function saveSalaryAdvance(input: {
  id?: string;
  advanceDate: string;
  employeeId: string;
  employeeName: string;
  amount: number;
  notes?: string;
}): Promise<FaSalaryAdvance> {
  const id = input.id || newId('adv');
  const row = {
    id,
    advance_date: input.advanceDate,
    employee_id: input.employeeId,
    employee_name: input.employeeName.trim(),
    amount: Number(input.amount) || 0,
    notes: (input.notes || '').trim(),
  };
  const { data, error } = await supabase.from('fa_salary_advances').upsert(row).select('*').single();
  if (error) throw new Error(error.message);
  return map(data);
}

export async function deleteSalaryAdvance(id: string): Promise<void> {
  const { error } = await supabase.from('fa_salary_advances').delete().eq('id', id);
  if (error) throw new Error(error.message);
}

/** Sum advances per employee for dates in the given set (YYYY-MM-DD). */
export function sumAdvancesByEmployee(
  advances: FaSalaryAdvance[],
  dateSet: Set<string>,
): Map<string, number> {
  const map = new Map<string, number>();
  for (const row of advances) {
    if (!dateSet.has(row.advanceDate)) continue;
    map.set(row.employeeId, (map.get(row.employeeId) || 0) + (Number(row.amount) || 0));
  }
  return map;
}
