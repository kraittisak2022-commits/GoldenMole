import { supabase } from '../lib/supabase';
import type { DeliveryStatus } from '../types';

/** What the public /d/:token page may see: no prices beyond the cash to collect. */
export interface DriverJob {
  orderNo: string;
  orderDate: string;
  driver: string | null;
  customer: string;
  phone: string;
  items: { name: string; quantity: number; unit: string }[];
  truckSize: number | null;
  trips: number;
  zone: string | null;
  address: string;
  lat: number | null;
  lng: number | null;
  note: string;
  /** Cash the driver must collect; 0 when nothing is due at the door. */
  codAmount: number;
  paid: boolean;
  deliveryStatus: DeliveryStatus;
  deliveredAt: string | null;
  cashReported: number | null;
  reportedAt: string | null;
  cancelled: boolean;
}

function mapJob(raw: unknown): DriverJob | null {
  if (!raw || typeof raw !== 'object') return null;
  const j = raw as Record<string, unknown>;
  const num = (v: unknown) => (v == null ? null : Number(v));
  return {
    orderNo: String(j.orderNo ?? ''),
    orderDate: String(j.orderDate ?? ''),
    driver: (j.driver as string | null) ?? null,
    customer: String(j.customer ?? ''),
    phone: String(j.phone ?? ''),
    items: Array.isArray(j.items)
      ? j.items.map((it: Record<string, unknown>) => ({
          name: String(it.name ?? ''),
          quantity: Number(it.quantity) || 0,
          unit: String(it.unit ?? ''),
        }))
      : [],
    truckSize: num(j.truckSize),
    trips: Number(j.trips) || 1,
    zone: (j.zone as string | null) ?? null,
    address: String(j.address ?? ''),
    lat: num(j.lat),
    lng: num(j.lng),
    note: String(j.note ?? ''),
    codAmount: Number(j.codAmount) || 0,
    paid: !!j.paid,
    deliveryStatus: j.deliveryStatus as DeliveryStatus,
    deliveredAt: (j.deliveredAt as string | null) ?? null,
    cashReported: num(j.cashReported),
    reportedAt: (j.reportedAt as string | null) ?? null,
    cancelled: !!j.cancelled,
  };
}

export async function fetchDriverJob(token: string): Promise<DriverJob | null> {
  const { data, error } = await supabase.rpc('ss_driver_job', { p_token: token });
  if (error) throw new Error(error.message);
  return mapJob(data);
}

/** Marks the order delivered; `cash` is required when the job has cash to collect. */
export async function confirmDriverJob(token: string, cash: number | null): Promise<DriverJob> {
  const { data, error } = await supabase.rpc('ss_driver_confirm', { p_token: token, p_cash: cash });
  if (error) throw new Error(error.message);
  const job = mapJob(data);
  if (!job) throw new Error('ไม่พบงานนี้');
  return job;
}
