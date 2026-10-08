import { formatAliases, parseAliases } from '../lib/customerSearch';
import { digitsOnly } from '../lib/format';
import { newId } from '../lib/ids';
import { supabase } from '../lib/supabase';
import { demoFilter, demoSession, isVisibleDemo } from '../tour/tourSession';
import type { Customer, CustomerSnapshot } from '../types';
import { throwIfError } from './errors';

export const mapCustomer = (row: any): Customer => ({
  id: row.id,
  name: row.name,
  aliases: parseAliases(row.aliases || ''),
  phone: row.phone || '',
  address: row.address || '',
  zoneId: row.zone_id,
  taxId: row.tax_id || '',
  lat: row.lat,
  lng: row.lng,
  isCredit: !!row.is_credit,
  note: row.note || '',
  createdAt: row.created_at,
});

export const toSnapshot = (c: Customer): CustomerSnapshot => ({
  name: c.name,
  phone: c.phone,
  address: c.address,
  taxId: c.taxId,
});

export async function listCustomers(): Promise<Customer[]> {
  const { data, error } = await demoFilter(supabase.from('ss_customers').select('*')).order('name');
  if (error) throw new Error(error.message);
  return (data || []).map(mapCustomer);
}

export async function searchCustomers(query: string, limit = 8): Promise<Customer[]> {
  const q = query.trim();
  if (!q) return [];
  const digits = digitsOnly(q);
  const escaped = q.replace(/[%,()]/g, ' ');
  const filters = [`name.ilike.%${escaped}%`, `aliases.ilike.%${escaped}%`];
  if (digits.length >= 3) filters.push(`phone.ilike.%${digits}%`);
  const { data, error } = await supabase
    .from('ss_customers')
    .select('*')
    .or(filters.join(','))
    .order('name')
    .limit(limit + 4);
  if (error) throw new Error(error.message);
  // A second .or() would collide with the search filter, so demo rows are dropped here.
  return (data || [])
    .filter((row) => isVisibleDemo(row.demo_session))
    .slice(0, limit)
    .map(mapCustomer);
}

export async function getCustomer(id: string): Promise<Customer | null> {
  const { data, error } = await supabase.from('ss_customers').select('*').eq('id', id).maybeSingle();
  if (error) throw new Error(error.message);
  return data ? mapCustomer(data) : null;
}

export type CustomerInput = Omit<Customer, 'id' | 'createdAt'> & { id?: string };

export async function saveCustomer(input: CustomerInput): Promise<Customer> {
  const row = {
    name: input.name.trim(),
    aliases: formatAliases(input.aliases),
    phone: digitsOnly(input.phone),
    address: input.address.trim(),
    zone_id: input.zoneId || null,
    tax_id: input.taxId.trim(),
    lat: input.lat,
    lng: input.lng,
    is_credit: input.isCredit,
    note: input.note.trim(),
  };
  const query = input.id
    ? supabase.from('ss_customers').update(row).eq('id', input.id)
    : supabase.from('ss_customers').insert({ id: newId('cus'), ...row, demo_session: demoSession() });
  const { data, error } = await query.select('*').single();
  if (error) throw new Error(error.message);
  return mapCustomer(data);
}

export async function deleteCustomer(id: string): Promise<void> {
  const { error } = await supabase.from('ss_customers').delete().eq('id', id);
  throwIfError(error, 'ลูกค้ารายนี้มีออเดอร์หรือใบวางบิลอยู่ ต้องลบออเดอร์และใบวางบิลของลูกค้าก่อน');
}
