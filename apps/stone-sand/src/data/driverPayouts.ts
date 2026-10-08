import { supabase } from '../lib/supabase';
import type { DriverPayout } from '../types';

const PAYOUT_SELECT = '*, orders:ss_orders(id, order_no, order_date, customer_snapshot, trips, driver_wage)';

function mapPayout(row: any): DriverPayout {
  const orders = (row.orders || []).map((o: any) => ({
    id: o.id,
    orderNo: o.order_no,
    orderDate: o.order_date,
    customerName: o.customer_snapshot?.name || '',
    trips: Number(o.trips || 0),
    amount: Number(o.driver_wage || 0),
  }));
  orders.sort((a: { orderNo: string }, b: { orderNo: string }) => a.orderNo.localeCompare(b.orderNo));
  return {
    id: row.id,
    payoutNo: row.payout_no,
    driverId: row.driver_id,
    driverName: row.driver_name || '',
    total: Number(row.total || 0),
    method: row.method,
    note: row.note || '',
    createdBy: row.created_by,
    createdAt: row.created_at,
    orders,
  };
}

export async function listDriverPayouts(): Promise<DriverPayout[]> {
  const { data, error } = await supabase
    .from('ss_driver_payouts')
    .select(PAYOUT_SELECT)
    .order('created_at', { ascending: false })
    .limit(300);
  if (error) throw new Error(error.message);
  return (data || []).map(mapPayout);
}

export async function createDriverPayout(input: {
  driverId: string;
  lines: { orderId: string; amount: number }[];
  method: 'cash' | 'transfer';
  note: string;
  by: string;
}): Promise<string> {
  const { data, error } = await supabase.rpc('ss_create_driver_payout', {
    p_driver_id: input.driverId,
    p_lines: input.lines.map((l) => ({ order_id: l.orderId, amount: l.amount })),
    p_method: input.method,
    p_note: input.note.trim(),
    p_by: input.by,
  });
  if (error) throw new Error(error.message);
  return (data as any).payout_no as string;
}

/** Its orders go back to "ค่ารถยังไม่จ่าย". */
export async function deleteDriverPayout(id: string, by: string): Promise<void> {
  const { error } = await supabase.rpc('ss_delete_driver_payout', { p_payout_id: id, p_by: by });
  if (error) throw new Error(error.message);
}
