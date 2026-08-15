import { supabase } from '../lib/supabase';
import type { FaWorkLog } from '../types';
import { newId } from '../types';

const map = (row: any): FaWorkLog => ({
  id: row.id,
  workDate: row.work_date,
  employeeId: row.employee_id,
  workDays: Number(row.work_days) > 0 ? Number(row.work_days) : 1,
  amount: Number(row.amount) || 0,
  otAmount: Number(row.ot_amount) || 0,
  notes: row.notes || '',
  createdAt: row.created_at,
});

export async function listWorkLogs(opts: {
  monthKey: string;
  employeeIds?: string[];
}): Promise<FaWorkLog[]> {
  const from = `${opts.monthKey}-01`;
  const to = `${opts.monthKey}-31`;
  let q = supabase
    .from('fa_work_logs')
    .select('*')
    .gte('work_date', from)
    .lte('work_date', to)
    .order('work_date', { ascending: true });
  if (opts.employeeIds?.length) q = q.in('employee_id', opts.employeeIds);
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return (data || []).map(map);
}

export async function saveWorkLog(input: {
  id?: string;
  workDate: string;
  employeeId: string;
  workDays?: number;
  amount?: number;
  otAmount?: number;
  notes?: string;
}): Promise<FaWorkLog> {
  let id = input.id;
  if (!id) {
    const { data: existing } = await supabase
      .from('fa_work_logs')
      .select('id')
      .eq('employee_id', input.employeeId)
      .eq('work_date', input.workDate)
      .maybeSingle();
    id = existing?.id || newId('wlog');
  }
  const workDays = Number(input.workDays);
  const amount = Number(input.amount);
  const row = {
    id,
    work_date: input.workDate,
    employee_id: input.employeeId,
    work_days: workDays > 0 ? workDays : 1,
    amount: amount >= 0 ? amount : 0,
    ot_amount: Number(input.otAmount) || 0,
    notes: (input.notes || '').trim(),
  };
  const { data, error } = await supabase.from('fa_work_logs').upsert(row).select('*').single();
  if (error) throw new Error(error.message);
  return map(data);
}

export async function deleteWorkLog(id: string): Promise<void> {
  const { error } = await supabase.from('fa_work_logs').delete().eq('id', id);
  if (error) throw new Error(error.message);
}

/** Set or clear a day's wage. amount <= 0 deletes the log. */
export async function setWorkDayAmount(input: {
  employeeId: string;
  workDate: string;
  amount: number;
  existingId?: string | null;
}): Promise<FaWorkLog | null> {
  const amount = Number(input.amount) || 0;
  if (amount <= 0) {
    if (input.existingId) {
      await deleteWorkLog(input.existingId);
      return null;
    }
    const { data } = await supabase
      .from('fa_work_logs')
      .select('id')
      .eq('employee_id', input.employeeId)
      .eq('work_date', input.workDate)
      .maybeSingle();
    if (data?.id) await deleteWorkLog(data.id);
    return null;
  }
  return saveWorkLog({
    id: input.existingId || undefined,
    workDate: input.workDate,
    employeeId: input.employeeId,
    amount,
    workDays: 1,
  });
}
