import { supabase } from '../lib/supabase';
import type { FaCategory, CategoryKind, FaLedgerEntry } from '../types';
import { newId } from '../types';

const map = (row: any): FaCategory => ({
  id: row.id,
  name: row.name,
  kind: row.kind,
  archived: !!row.archived,
  sortOrder: Number(row.sort_order) || 0,
});

export type CategorySummary = {
  category: FaCategory;
  entryCount: number;
  incomeTotal: number;
  expenseTotal: number;
};

export async function listCategories(opts?: { includeArchived?: boolean }): Promise<FaCategory[]> {
  let q = supabase.from('fa_categories').select('*').order('sort_order', { ascending: true });
  if (!opts?.includeArchived) q = q.eq('archived', false);
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return (data || []).map(map);
}

export async function saveCategory(input: {
  id?: string;
  name: string;
  kind: CategoryKind;
  sortOrder?: number;
}): Promise<FaCategory> {
  const id = input.id || newId('cat');
  const row = {
    id,
    name: input.name.trim(),
    kind: input.kind,
    sort_order: input.sortOrder ?? 100,
    archived: false,
  };
  const { data, error } = await supabase.from('fa_categories').upsert(row).select('*').single();
  if (error) throw new Error(error.message);
  return map(data);
}

export async function archiveCategory(id: string): Promise<void> {
  const { error } = await supabase.from('fa_categories').update({ archived: true }).eq('id', id);
  if (error) throw new Error(error.message);
}

export async function restoreCategory(id: string): Promise<void> {
  const { error } = await supabase.from('fa_categories').update({ archived: false }).eq('id', id);
  if (error) throw new Error(error.message);
}

export async function countLedgerEntriesForCategory(categoryId: string): Promise<number> {
  const { count, error } = await supabase
    .from('fa_ledger_entries')
    .select('id', { count: 'exact', head: true })
    .eq('category_id', categoryId);
  if (error) throw new Error(error.message);
  return count ?? 0;
}

/** Hard-delete when empty; otherwise archive so linked entries stay for summary. */
export async function deleteCategory(id: string): Promise<'deleted' | 'archived'> {
  const n = await countLedgerEntriesForCategory(id);
  if (n > 0) {
    await archiveCategory(id);
    return 'archived';
  }
  const { error } = await supabase.from('fa_categories').delete().eq('id', id);
  if (error) throw new Error(error.message);
  return 'deleted';
}

export function buildCategorySummaries(
  categories: FaCategory[],
  entries: FaLedgerEntry[],
): CategorySummary[] {
  return categories.map((category) => {
    const rows = entries.filter((e) => e.categoryId === category.id);
    return {
      category,
      entryCount: rows.length,
      incomeTotal: rows.filter((e) => e.entryType === 'income').reduce((s, e) => s + e.amount, 0),
      expenseTotal: rows.filter((e) => e.entryType === 'expense').reduce((s, e) => s + e.amount, 0),
    };
  });
}
