import { supabase } from '../lib/supabase';
import { DEFAULT_SETTINGS, type AppSettings, type Product, type Zone } from '../types';

const toNum = (v: unknown) => Number(v ?? 0);

const mapProduct = (row: any): Product => ({
  id: row.id,
  name: row.name,
  unit: row.unit,
  pricePerUnit: toNum(row.price_per_unit),
  sortOrder: row.sort_order,
  active: !!row.active,
});

const mapZone = (row: any): Zone => ({
  id: row.id,
  name: row.name,
  feeMin: toNum(row.fee_min),
  feeMax: toNum(row.fee_max),
  sortOrder: row.sort_order,
});

export async function listProducts(): Promise<Product[]> {
  const { data, error } = await supabase.from('ss_products').select('*').order('sort_order');
  if (error) throw new Error(error.message);
  return (data || []).map(mapProduct);
}

export async function saveProduct(p: Pick<Product, 'id' | 'name' | 'pricePerUnit' | 'active'>): Promise<void> {
  const { error } = await supabase
    .from('ss_products')
    .update({ name: p.name.trim(), price_per_unit: p.pricePerUnit, active: p.active })
    .eq('id', p.id);
  if (error) throw new Error(error.message);
}

export async function listZones(): Promise<Zone[]> {
  const { data, error } = await supabase.from('ss_zones').select('*').order('sort_order');
  if (error) throw new Error(error.message);
  return (data || []).map(mapZone);
}

export async function saveZone(z: Pick<Zone, 'id' | 'feeMin' | 'feeMax'>): Promise<void> {
  const { error } = await supabase
    .from('ss_zones')
    .update({ fee_min: z.feeMin, fee_max: z.feeMax })
    .eq('id', z.id);
  if (error) throw new Error(error.message);
}

export async function getSettings(): Promise<AppSettings> {
  const { data, error } = await supabase.from('ss_settings').select('key, value');
  if (error) throw new Error(error.message);
  const byKey = Object.fromEntries((data || []).map((r: any) => [r.key, r.value]));
  return {
    company: { ...DEFAULT_SETTINGS.company, ...(byKey.company || {}) },
    delivery: { ...DEFAULT_SETTINGS.delivery, ...(byKey.delivery || {}) },
    payment: { ...DEFAULT_SETTINGS.payment, ...(byKey.payment || {}) },
  };
}

export async function saveSetting<K extends keyof AppSettings>(key: K, value: AppSettings[K]): Promise<void> {
  const { error } = await supabase
    .from('ss_settings')
    .upsert({ key, value, updated_at: new Date().toISOString() });
  if (error) throw new Error(error.message);
}
