import { supabase } from '../lib/supabase';
import type { FaCategory, CategoryKind } from '../types';
import { newId } from '../types';

const map = (row: any): FaCategory => ({
  id: row.id,
  name: row.name,
  kind: row.kind,
  archived: !!row.archived,
  sortOrder: Number(row.sort_order) || 0,
});

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
