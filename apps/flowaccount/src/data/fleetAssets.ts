import { supabase } from '../lib/supabase';
import type { FaFleetAsset } from '../types';
import { newId } from '../types';

const map = (row: any): FaFleetAsset => ({
  id: row.id,
  name: row.name,
  dailyRate: Number(row.daily_rate) || 0,
  inactive: !!row.inactive,
});

export async function listFleetAssets(opts?: { includeInactive?: boolean }): Promise<FaFleetAsset[]> {
  let q = supabase.from('fa_fleet_assets').select('*').order('name', { ascending: true });
  if (!opts?.includeInactive) q = q.eq('inactive', false);
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return (data || []).map(map);
}

export async function saveFleetAsset(input: {
  id?: string;
  name: string;
  dailyRate: number;
}): Promise<FaFleetAsset> {
  const id = input.id || newId('fleet');
  const row = {
    id,
    name: input.name.trim(),
    daily_rate: Number(input.dailyRate) || 0,
    inactive: false,
  };
  const { data, error } = await supabase.from('fa_fleet_assets').upsert(row).select('*').single();
  if (error) throw new Error(error.message);
  return map(data);
}

export async function setFleetAssetInactive(id: string, inactive: boolean): Promise<void> {
  const { error } = await supabase.from('fa_fleet_assets').update({ inactive }).eq('id', id);
  if (error) throw new Error(error.message);
}
