import { supabase } from '../lib/supabase';
import type { FaReimbPayer } from '../types';
import { newId } from '../types';

const map = (row: any): FaReimbPayer => ({
  id: row.id,
  name: row.name,
  shareToken: row.share_token,
  inactive: !!row.inactive,
  createdAt: row.created_at,
});

export async function listPayers(opts?: { includeInactive?: boolean }): Promise<FaReimbPayer[]> {
  let q = supabase.from('fa_reimb_payers').select('*').order('name', { ascending: true });
  if (!opts?.includeInactive) q = q.eq('inactive', false);
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return (data || []).map(map);
}

export async function getPayerByToken(token: string): Promise<FaReimbPayer | null> {
  const { data, error } = await supabase
    .from('fa_reimb_payers')
    .select('*')
    .eq('share_token', token.trim())
    .eq('inactive', false)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return data ? map(data) : null;
}

export async function savePayer(input: { id?: string; name: string }): Promise<FaReimbPayer> {
  const name = input.name.trim();
  if (input.id) {
    const { data, error } = await supabase
      .from('fa_reimb_payers')
      .update({ name, inactive: false })
      .eq('id', input.id)
      .select('*')
      .single();
    if (error) throw new Error(error.message);
    return map(data);
  }

  const id = newId('payer');
  const share_token =
    typeof crypto !== 'undefined' && crypto.randomUUID
      ? crypto.randomUUID().replace(/-/g, '')
      : newId('tok').replace(/^tok-/, '');
  const { data, error } = await supabase
    .from('fa_reimb_payers')
    .insert({ id, name, share_token, inactive: false })
    .select('*')
    .single();
  if (error) throw new Error(error.message);
  return map(data);
}

export async function setPayerInactive(id: string, inactive = true): Promise<void> {
  const { error } = await supabase.from('fa_reimb_payers').update({ inactive }).eq('id', id);
  if (error) throw new Error(error.message);
}

export function payerClaimUrl(shareToken: string, origin = window.location.origin): string {
  return `${origin}/claim/${encodeURIComponent(shareToken)}`;
}
