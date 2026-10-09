import { computeTotals, lineAmount } from '../calc/pricing';
import { parseAliases } from '../lib/customerSearch';
import { supabase } from '../lib/supabase';
import { demoSession } from '../tour/tourSession';
import { scoped } from './sourceScope';
import type {
  Customer,
  DeliveryStatus,
  DiscountType,
  Fulfillment,
  Order,
  OrderItem,
  OrderSource,
  PaymentMethod,
  TruckSize,
} from '../types';
import { normalizeDeliveryStatus } from '../types';
import { toSnapshot } from './customers';

const num = (v: unknown) => (v == null ? 0 : Number(v));
const numOrNull = (v: unknown) => (v == null ? null : Number(v));

const ORDER_SELECT = '*, items:ss_order_items(*), stmt:ss_statement_orders(statement_id), cust:ss_customers(aliases)';

function mapItem(row: any): OrderItem {
  return {
    id: row.id,
    productId: row.product_id,
    name: row.name,
    unit: row.unit,
    unitPrice: num(row.unit_price),
    quantity: num(row.quantity),
    amount: num(row.amount),
    discountPerUnit: num(row.discount_per_unit),
  };
}

export function mapOrder(row: any): Order {
  const stmt = Array.isArray(row.stmt) ? row.stmt[0] : row.stmt;
  const items = Array.isArray(row.items) ? [...row.items] : [];
  items.sort((a: any, b: any) => (a.sort_order ?? 0) - (b.sort_order ?? 0));
  return {
    id: row.id,
    orderNo: row.order_no,
    receiptNo: row.receipt_no,
    source: row.source === 'pit' ? 'pit' : 'shop',
    orderDate: row.order_date,
    customerId: row.customer_id,
    customer: {
      name: row.customer_snapshot?.name || '',
      phone: row.customer_snapshot?.phone || '',
      address: row.customer_snapshot?.address || '',
      taxId: row.customer_snapshot?.taxId || '',
    },
    customerAliases: parseAliases(row.cust?.aliases || ''),
    fulfillment: row.fulfillment,
    deliveryAddress: row.delivery_address || '',
    pinLat: row.pin_lat,
    pinLng: row.pin_lng,
    zoneId: row.zone_id,
    roadDistanceKm: numOrNull(row.road_distance_km),
    truckSize: row.truck_size,
    trips: row.trips,
    driverId: row.driver_id,
    feePerCubic: num(row.fee_per_cubic),
    feePerTrip: num(row.fee_per_trip),
    remoteSurcharge: num(row.remote_surcharge),
    discountType: row.discount_type,
    discountValue: num(row.discount_value),
    subtotal: num(row.subtotal),
    deliveryTotal: num(row.delivery_total),
    deliveryDiscount: num(row.delivery_discount),
    discountAmount: num(row.discount_amount),
    total: num(row.total),
    paymentMethod: row.payment_method,
    paymentStatus: row.payment_status,
    paidAt: row.paid_at,
    deliveryStatus: normalizeDeliveryStatus(row.delivery_status),
    deliveredAt: row.delivered_at,
    cleared: !!row.cleared,
    clearedAt: row.cleared_at,
    driverWage: num(row.driver_wage),
    note: row.note || '',
    cancelled: !!row.cancelled,
    verifyToken: row.verify_token,
    driverToken: row.driver_token ?? undefined,
    driverCashReported: numOrNull(row.driver_cash_reported),
    driverReportedAt: row.driver_reported_at ?? null,
    statusLog: Array.isArray(row.status_log) ? row.status_log : [],
    createdBy: row.created_by,
    createdAt: row.created_at,
    items: items.map(mapItem),
    statementId: stmt?.statement_id ?? null,
    driverPayoutId: row.driver_payout_id ?? null,
    demo: !!row.demo_session,
  };
}

export interface ListOrdersOptions {
  from?: string;
  to?: string;
  customerId?: string;
  source?: OrderSource;
  deliveryStatuses?: DeliveryStatus[];
  limit?: number;
}

export async function listOrders(opts: ListOrdersOptions = {}): Promise<Order[]> {
  let q = scoped(supabase.from('ss_orders').select(ORDER_SELECT))
    .order('order_date', { ascending: false })
    .order('created_at', { ascending: false })
    .limit(opts.limit ?? 500);
  if (opts.from) q = q.gte('order_date', opts.from);
  if (opts.to) q = q.lte('order_date', opts.to);
  if (opts.customerId) q = q.eq('customer_id', opts.customerId);
  if (opts.source) q = q.eq('source', opts.source);
  if (opts.deliveryStatuses?.length) q = q.in('delivery_status', opts.deliveryStatuses).eq('cancelled', false);
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return (data || []).map(mapOrder);
}

/** Not cleared and not cancelled, oldest first (outstanding balances and monthly statements). */
export async function listUnclearedOrders(opts: { customerId?: string } = {}): Promise<Order[]> {
  let q = scoped(supabase.from('ss_orders').select(ORDER_SELECT))
    .eq('cleared', false)
    .eq('cancelled', false)
    .order('order_date')
    .order('created_at')
    .limit(2000);
  if (opts.customerId) q = q.eq('customer_id', opts.customerId);
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return (data || []).map(mapOrder);
}

/** Delivery orders with a driver whose ค่ารถ has not been paid yet, oldest first. */
export async function listDriverUnpaidOrders(): Promise<Order[]> {
  const { data, error } = await scoped(supabase.from('ss_orders').select(ORDER_SELECT))
    .is('demo_session', null)
    .eq('fulfillment', 'delivery')
    .eq('cancelled', false)
    .not('driver_id', 'is', null)
    .is('driver_payout_id', null)
    .order('order_date')
    .order('created_at')
    .limit(2000);
  if (error) throw new Error(error.message);
  return (data || []).map(mapOrder);
}

export async function getOrder(id: string): Promise<Order | null> {
  const { data, error } = await scoped(supabase.from('ss_orders').select(ORDER_SELECT)).eq('id', id).maybeSingle();
  if (error) throw new Error(error.message);
  return data ? mapOrder(data) : null;
}

export async function getOrdersByIds(ids: string[]): Promise<Order[]> {
  if (!ids.length) return [];
  const { data, error } = await scoped(supabase.from('ss_orders').select(ORDER_SELECT))
    .in('id', ids)
    .order('order_date')
    .order('created_at');
  if (error) throw new Error(error.message);
  return (data || []).map(mapOrder);
}

export interface OrderDraft {
  source: OrderSource;
  /** YYYY-MM-DD; null lets the database use today (Bangkok). */
  orderDate: string | null;
  customer: Customer;
  items: OrderItem[];
  fulfillment: Fulfillment;
  deliveryAddress: string;
  pinLat: number | null;
  pinLng: number | null;
  zoneId: string | null;
  roadDistanceKm: number | null;
  truckSize: TruckSize | null;
  trips: number;
  driverId: string | null;
  feePerCubic: number;
  feePerTrip: number;
  remoteSurcharge: number;
  deliveryDiscount: number;
  discountType: DiscountType;
  discountValue: number;
  paymentMethod: PaymentMethod;
  paidNow: boolean;
  driverWage: number;
  note: string;
}

export function draftTotals(
  d: Pick<
    OrderDraft,
    'items' | 'fulfillment' | 'feePerCubic' | 'feePerTrip' | 'trips' | 'remoteSurcharge' | 'deliveryDiscount' | 'discountType' | 'discountValue'
  >,
) {
  const delivery = d.fulfillment === 'delivery';
  return computeTotals({
    items: d.items,
    feePerCubic: delivery ? d.feePerCubic : 0,
    feePerTrip: delivery ? d.feePerTrip : 0,
    trips: delivery ? d.trips : 0,
    remoteSurcharge: delivery ? d.remoteSurcharge : 0,
    deliveryDiscount: delivery ? d.deliveryDiscount : 0,
    discountType: d.discountType,
    discountValue: d.discountValue,
  });
}

export async function createOrder(d: OrderDraft, by: string): Promise<Order> {
  const totals = draftTotals(d);
  const delivery = d.fulfillment === 'delivery';
  const paymentStatus = d.paidNow ? 'paid' : d.paymentMethod === 'credit' ? 'credit' : 'unpaid';
  const order = {
    source: d.source,
    order_date: d.orderDate,
    customer_id: d.customer.id,
    customer_snapshot: toSnapshot(d.customer),
    fulfillment: d.fulfillment,
    delivery_address: delivery ? d.deliveryAddress.trim() : '',
    pin_lat: delivery ? d.pinLat : null,
    pin_lng: delivery ? d.pinLng : null,
    zone_id: delivery ? d.zoneId : null,
    road_distance_km: delivery ? d.roadDistanceKm : null,
    truck_size: delivery ? d.truckSize : null,
    trips: delivery ? d.trips : 0,
    driver_id: delivery ? d.driverId : null,
    fee_per_cubic: delivery ? d.feePerCubic : 0,
    fee_per_trip: delivery ? d.feePerTrip : 0,
    remote_surcharge: delivery ? d.remoteSurcharge : 0,
    delivery_discount: totals.deliveryDiscount,
    discount_type: d.discountType,
    discount_value: d.discountValue,
    subtotal: totals.subtotal,
    delivery_total: totals.deliveryTotal,
    discount_amount: totals.discountAmount,
    total: totals.total,
    payment_method: d.paymentMethod,
    payment_status: paymentStatus,
    delivery_status: (delivery ? 'dispatched' : 'pickup') as DeliveryStatus,
    driver_wage: delivery ? d.driverWage : 0,
    note: d.note.trim(),
    demo_session: demoSession(),
  };
  const items = d.items
    .filter((it) => it.quantity > 0)
    .map((it) => ({
      product_id: it.productId,
      name: it.name,
      unit: it.unit,
      unit_price: it.unitPrice,
      quantity: it.quantity,
      amount: it.amount,
      discount_per_unit: it.discountPerUnit || 0,
    }));

  const { data, error } = await supabase.rpc('ss_create_order', { p_order: order, p_items: items, p_by: by });
  if (error) throw new Error(error.message);
  const created = await getOrder((data as any).id);
  if (!created) throw new Error('บันทึกออเดอร์แล้วแต่โหลดข้อมูลไม่ได้');
  return created;
}

async function rpcOrder(fn: string, args: Record<string, unknown>): Promise<Order> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new Error(error.message);
  const order = await getOrder((data as any).id);
  if (!order) throw new Error('ไม่พบออเดอร์');
  return order;
}

export const markOrderPaid = (id: string, method: 'cash' | 'transfer' | 'cod', by: string) =>
  rpcOrder('ss_mark_order_paid', { p_order_id: id, p_method: method, p_by: by });

export const markOrderUnpaid = (id: string, by: string) =>
  rpcOrder('ss_mark_order_unpaid', { p_order_id: id, p_by: by });

export const setDeliveryStatus = (id: string, status: DeliveryStatus, by: string) =>
  rpcOrder('ss_set_delivery_status', { p_order_id: id, p_status: status, p_by: by });

export type OrderEdit = Pick<
  Order,
  | 'orderDate'
  | 'items'
  | 'truckSize'
  | 'trips'
  | 'feePerCubic'
  | 'feePerTrip'
  | 'remoteSurcharge'
  | 'deliveryDiscount'
  | 'discountType'
  | 'discountValue'
  | 'paymentMethod'
  | 'deliveryAddress'
  | 'note'
>;

export async function updateOrder(current: Order, e: OrderEdit, by: string): Promise<Order> {
  const items = e.items.filter((it) => it.quantity > 0);
  const totals = draftTotals({ ...e, items, fulfillment: current.fulfillment });
  const order = {
    order_date: e.orderDate,
    delivery_address: e.deliveryAddress.trim(),
    truck_size: e.truckSize,
    trips: e.trips,
    fee_per_cubic: e.feePerCubic,
    fee_per_trip: e.feePerTrip,
    remote_surcharge: e.remoteSurcharge,
    delivery_discount: totals.deliveryDiscount,
    discount_type: e.discountType,
    discount_value: e.discountValue,
    subtotal: totals.subtotal,
    delivery_total: totals.deliveryTotal,
    discount_amount: totals.discountAmount,
    total: totals.total,
    payment_method: e.paymentMethod,
    note: e.note.trim(),
  };
  const rows = items.map((it) => ({
    product_id: it.productId,
    name: it.name,
    unit: it.unit,
    unit_price: it.unitPrice,
    quantity: it.quantity,
    amount: lineAmount(it.unitPrice, it.quantity),
    discount_per_unit: it.discountPerUnit || 0,
  }));
  return rpcOrder('ss_update_order', { p_order_id: current.id, p_order: order, p_items: rows, p_by: by });
}

/** Also drops it from its statement (an emptied statement is deleted). */
export async function deleteOrder(id: string): Promise<void> {
  const { error } = await supabase.rpc('ss_delete_order', { p_order_id: id });
  if (error) throw new Error(error.message);
}

export async function updateOrderFields(
  id: string,
  patch: Partial<{ driverId: string | null; driverWage: number; note: string; cancelled: boolean }>,
  by: string,
  current: Order,
): Promise<Order> {
  const row: Record<string, unknown> = {};
  const events: string[] = [];
  if (patch.driverId !== undefined) {
    row.driver_id = patch.driverId;
    events.push('driver');
  }
  if (patch.driverWage !== undefined) {
    row.driver_wage = patch.driverWage;
    events.push(`wage:${patch.driverWage}`);
  }
  if (patch.note !== undefined) row.note = patch.note;
  if (patch.cancelled !== undefined) {
    row.cancelled = patch.cancelled;
    events.push(patch.cancelled ? 'cancelled' : 'restored');
  }
  if (events.length) {
    const at = new Date().toISOString();
    row.status_log = [...current.statusLog, ...events.map((event) => ({ at, by, event }))];
  }
  const { error } = await supabase.from('ss_orders').update(row).eq('id', id);
  if (error) throw new Error(error.message);
  const order = await getOrder(id);
  if (!order) throw new Error('ไม่พบออเดอร์');
  return order;
}
