import { supabase } from '../lib/supabase';
import type { FaEmployee, EmployeeType } from '../types';
import { newId } from '../types';

const map = (row: any): FaEmployee => ({
  id: row.id,
  name: row.name,
  type: row.type,
  basePay: Number(row.base_pay) || 0,
  inactive: !!row.inactive,
});

export async function listEmployees(opts?: { includeInactive?: boolean }): Promise<FaEmployee[]> {
  let q = supabase.from('fa_employees').select('*').order('name', { ascending: true });
  if (!opts?.includeInactive) q = q.eq('inactive', false);
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return (data || []).map(map);
}

export async function saveEmployee(input: {
  id?: string;
  name: string;
  type: EmployeeType;
  basePay: number;
}): Promise<FaEmployee> {
  const id = input.id || newId('emp');
  const row = {
    id,
    name: input.name.trim(),
    type: input.type,
    base_pay: Number(input.basePay) || 0,
    inactive: false,
  };
  const { data, error } = await supabase.from('fa_employees').upsert(row).select('*').single();
  if (error) throw new Error(error.message);
  return map(data);
}

export async function setEmployeeInactive(id: string, inactive: boolean): Promise<void> {
  const { error } = await supabase.from('fa_employees').update({ inactive }).eq('id', id);
  if (error) throw new Error(error.message);
}
