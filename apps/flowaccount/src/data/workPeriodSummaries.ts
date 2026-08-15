import { supabase } from '../lib/supabase';
import type { FaWorkPeriodSummary } from '../types';
import { newId } from '../types';

const map = (row: any): FaWorkPeriodSummary => ({
  id: row.id,
  periodKey: row.period_key,
  employeeId: row.employee_id,
  paid: !!row.paid,
  specialAmount: Number(row.special_amount) || 0,
  advanceAmount: Number(row.advance_amount) || 0,
  notes: row.notes || '',
  createdAt: row.created_at,
});

export async function listWorkPeriodSummaries(periodKey: string): Promise<FaWorkPeriodSummary[]> {
  const { data, error } = await supabase
    .from('fa_work_period_summaries')
    .select('*')
    .eq('period_key', periodKey);
  if (error) throw new Error(error.message);
  return (data || []).map(map);
}

export async function saveWorkPeriodSummary(input: {
  id?: string;
  periodKey: string;
  employeeId: string;
  paid?: boolean;
  specialAmount?: number;
  advanceAmount?: number;
  notes?: string;
}): Promise<FaWorkPeriodSummary> {
  let id = input.id;
  if (!id) {
    const { data: existing } = await supabase
      .from('fa_work_period_summaries')
      .select('id')
      .eq('period_key', input.periodKey)
      .eq('employee_id', input.employeeId)
      .maybeSingle();
    id = existing?.id || newId('wps');
  }
  const row = {
    id,
    period_key: input.periodKey,
    employee_id: input.employeeId,
    paid: !!input.paid,
    special_amount: Number(input.specialAmount) || 0,
    advance_amount: Number(input.advanceAmount) || 0,
    notes: (input.notes || '').trim(),
  };
  const { data, error } = await supabase
    .from('fa_work_period_summaries')
    .upsert(row)
    .select('*')
    .single();
  if (error) throw new Error(error.message);
  return map(data);
}
