import { supabase } from '../lib/supabase';
import type { FaReimbursement } from '../types';
import { newId } from '../types';
import { saveLedgerEntry } from './ledger';

const map = (row: any): FaReimbursement => ({
  id: row.id,
  date: row.date,
  payerName: row.payer_name,
  description: row.description || '',
  amount: Number(row.amount) || 0,
  status: row.status,
  approvedCategoryId: row.approved_category_id,
  ledgerEntryId: row.ledger_entry_id,
  approvedBy: row.approved_by,
  approvedAt: row.approved_at,
  createdAt: row.created_at,
});

export async function listReimbursements(): Promise<FaReimbursement[]> {
  const { data, error } = await supabase
    .from('fa_reimbursements')
    .select('*')
    .order('date', { ascending: false });
  if (error) throw new Error(error.message);
  return (data || []).map(map);
}

export async function saveReimbursement(input: {
  id?: string;
  date: string;
  payerName: string;
  description: string;
  amount: number;
}): Promise<FaReimbursement> {
  const id = input.id || newId('reimb');
  const row = {
    id,
    date: input.date,
    payer_name: input.payerName.trim(),
    description: input.description.trim(),
    amount: Number(input.amount) || 0,
    status: 'pending',
  };
  const { data, error } = await supabase.from('fa_reimbursements').upsert(row).select('*').single();
  if (error) throw new Error(error.message);
  return map(data);
}

export async function approveReimbursement(input: {
  reimbursement: FaReimbursement;
  categoryId: string;
  approvedBy: string;
}): Promise<FaReimbursement> {
  if (input.reimbursement.status === 'approved') {
    throw new Error('รายการนี้ถูกอนุมัติแล้ว');
  }

  const ledger = await saveLedgerEntry({
    date: input.reimbursement.date,
    description: `เบิกสำรองจ่าย: ${input.reimbursement.description} (${input.reimbursement.payerName})`,
    categoryId: input.categoryId,
    entryType: 'expense',
    amount: input.reimbursement.amount,
    source: 'reimbursement',
    sourceId: input.reimbursement.id,
    createdBy: input.approvedBy,
  });

  const { data, error } = await supabase
    .from('fa_reimbursements')
    .update({
      status: 'approved',
      approved_category_id: input.categoryId,
      ledger_entry_id: ledger.id,
      approved_by: input.approvedBy,
      approved_at: new Date().toISOString(),
    })
    .eq('id', input.reimbursement.id)
    .select('*')
    .single();

  if (error) throw new Error(error.message);
  return map(data);
}

export async function rejectReimbursement(id: string): Promise<void> {
  const { error } = await supabase
    .from('fa_reimbursements')
    .update({ status: 'rejected' })
    .eq('id', id)
    .eq('status', 'pending');
  if (error) throw new Error(error.message);
}
