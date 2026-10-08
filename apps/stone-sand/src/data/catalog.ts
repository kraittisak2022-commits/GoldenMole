import { newId } from '../lib/ids';
import { supabase } from '../lib/supabase';
import { DEFAULT_SETTINGS, type AppSettings, type Product, type Zone } from '../types';
import { throwIfError } from './errors';

const toNum = (v: unknown) => Number(v ?? 0);

const mapProduct = (row: any): Product => ({
  id: row.id,
  name: row.name,
  category: row.category === 'sand' ? 'sand' : 'stone',
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

export async function saveProduct(p: Pick<Product, 'id' | 'name' | 'category' | 'pricePerUnit' | 'active'>): Promise<void> {
  const { error } = await supabase
    .from('ss_products')
    .update({ name: p.name.trim(), category: p.category, price_per_unit: p.pricePerUnit, active: p.active })
    .eq('id', p.id);
  if (error) throw new Error(error.message);
}

export async function createProduct(p: Pick<Product, 'name' | 'category' | 'unit' | 'pricePerUnit' | 'sortOrder'>): Promise<void> {
  const { error } = await supabase.from('ss_products').insert({
    id: newId('prd'),
    name: p.name.trim(),
    category: p.category,
    unit: p.unit.trim() || 'คิว',
    price_per_unit: p.pricePerUnit,
    sort_order: p.sortOrder,
    active: true,
  });
  if (error) throw new Error(error.message);
}

/** Past orders keep their own copy of the product name and price. */
export async function deleteProduct(id: string): Promise<void> {
  const { error } = await supabase.from('ss_products').delete().eq('id', id);
  if (error) throw new Error(error.message);
}

export async function listZones(): Promise<Zone[]> {
  const { data, error } = await supabase.from('ss_zones').select('*').order('sort_order');
  if (error) throw new Error(error.message);
  return (data || []).map(mapZone);
}

export async function saveZone(z: Pick<Zone, 'id' | 'name' | 'feeMin' | 'feeMax'>): Promise<void> {
  const { error } = await supabase
    .from('ss_zones')
    .update({ name: z.name.trim(), fee_min: z.feeMin, fee_max: z.feeMax })
    .eq('id', z.id);
  if (error) throw new Error(error.message);
}

export async function createZone(z: Pick<Zone, 'name' | 'feeMin' | 'feeMax' | 'sortOrder'>): Promise<void> {
  const { error } = await supabase.from('ss_zones').insert({
    id: newId('zone'),
    name: z.name.trim(),
    fee_min: z.feeMin,
    fee_max: z.feeMax,
    sort_order: z.sortOrder,
  });
  if (error) throw new Error(error.message);
}

export async function deleteZone(id: string): Promise<void> {
  const { error } = await supabase.from('ss_zones').delete().eq('id', id);
  throwIfError(error, 'มีลูกค้าหรือออเดอร์ที่ใช้ตำบลนี้อยู่ ลบไม่ได้');
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
