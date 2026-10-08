import { newId } from '../lib/ids';
import { supabase } from '../lib/supabase';
import type { Driver } from '../types';

export const mapDriver = (row: any): Driver => ({
  id: row.id,
  name: row.name,
  village: row.village || '',
  routeGroup: row.route_group,
  truckSize: row.truck_size,
  truckCount: row.truck_count,
  contacts: Array.isArray(row.contacts) ? row.contacts : [],
  contactNote: row.contact_note || '',
  wagePerTrip: Number(row.wage_per_trip || 0),
  active: !!row.active,
  sortOrder: row.sort_order,
});

export async function listDrivers(opts?: { includeInactive?: boolean }): Promise<Driver[]> {
  let q = supabase.from('ss_drivers').select('*').order('sort_order').order('name');
  if (!opts?.includeInactive) q = q.eq('active', true);
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return (data || []).map(mapDriver);
}

export async function saveDriver(d: Omit<Driver, 'id' | 'sortOrder'> & { id?: string }): Promise<void> {
  const row = {
    name: d.name.trim(),
    village: d.village.trim(),
    route_group: d.routeGroup,
    truck_size: d.truckSize,
    truck_count: d.truckCount,
    contacts: d.contacts.filter((c) => c.phone.trim()),
    contact_note: d.contactNote.trim(),
    wage_per_trip: d.wagePerTrip,
    active: d.active,
  };
  const { error } = d.id
    ? await supabase.from('ss_drivers').update(row).eq('id', d.id)
    : await supabase.from('ss_drivers').insert({ id: newId('drv'), sort_order: 100, ...row });
  if (error) throw new Error(error.message);
}
