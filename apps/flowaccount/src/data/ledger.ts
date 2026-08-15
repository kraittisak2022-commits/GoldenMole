import { supabase } from '../lib/supabase';
import type { EntryType, FaLedgerEntry, LedgerPaidBy, LedgerSource } from '../types';
import { newId } from '../types';

function normalizePaidBy(value: unknown): LedgerPaidBy | null {
  if (value === 'A' || value === 'B' || value === 'AB') return value;
  return null;
}

const map = (row: any): FaLedgerEntry => ({
  id: row.id,
  date: row.date,
  description: row.description || '',
  categoryId: row.category_id,
  entryType: row.entry_type,
  quantity: Number(row.quantity) > 0 ? Number(row.quantity) : 1,
  amount: Number(row.amount) || 0,
  paidBy: normalizePaidBy(row.paid_by),
  source: row.source || 'manual',
  sourceId: row.source_id,
  createdBy: row.created_by,
  createdAt: row.created_at,
});

export async function listLedgerEntries(): Promise<FaLedgerEntry[]> {
  const { data, error } = await supabase
    .from('fa_ledger_entries')
    .select('*')
    .order('date', { ascending: false })
    .order('created_at', { ascending: false });
  if (error) throw new Error(error.message);
  return (data || []).map(map);
}

export async function saveLedgerEntry(input: {
  id?: string;
  date: string;
  description: string;
  categoryId: string;
  entryType: EntryType;
  quantity?: number;
  amount: number;
  paidBy?: LedgerPaidBy | null;
  source?: LedgerSource;
  sourceId?: string | null;
  createdBy?: string | null;
}): Promise<FaLedgerEntry> {
  const id = input.id || newId('led');
  const quantity = Number(input.quantity);
  const row = {
    id,
    date: input.date,
    description: input.description.trim(),
    category_id: input.categoryId,
    entry_type: input.entryType,
    quantity: quantity > 0 ? quantity : 1,
    amount: Number(input.amount) || 0,
    paid_by: normalizePaidBy(input.paidBy),
    source: input.source || 'manual',
    source_id: input.sourceId ?? null,
    created_by: input.createdBy ?? null,
  };
  const { data, error } = await supabase.from('fa_ledger_entries').upsert(row).select('*').single();
  if (error) throw new Error(error.message);
  return map(data);
}

export async function deleteLedgerEntry(id: string): Promise<void> {
  const { error } = await supabase.from('fa_ledger_entries').delete().eq('id', id);
  if (error) throw new Error(error.message);
}

export async function getLedgerById(id: string): Promise<FaLedgerEntry | null> {
  const { data, error } = await supabase.from('fa_ledger_entries').select('*').eq('id', id).maybeSingle();
  if (error) throw new Error(error.message);
  return data ? map(data) : null;
}
