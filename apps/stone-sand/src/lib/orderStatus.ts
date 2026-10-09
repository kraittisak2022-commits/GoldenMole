import type { BadgeTone } from '../components/ui/Badge';
import { DELIVERY_STATUS_LABEL, type Driver, type Order, type OrderSource, type Statement, type Zone } from '../types';
import { codToCollect } from './driverPay';
import { driverJobUrl, formatMoney, formatNumber, formatPhone, googleMapsUrl } from './format';

export type OrderFilter = 'all' | 'unpaid' | 'credit' | 'waiting' | 'delivered' | 'uncleared' | 'cancelled';

export const ORDER_FILTERS: { id: OrderFilter; label: string }[] = [
  { id: 'all', label: 'ทั้งหมด' },
  { id: 'unpaid', label: 'ยังไม่จ่าย' },
  { id: 'credit', label: 'ค้างเครดิต' },
  { id: 'waiting', label: 'รอส่ง' },
  { id: 'delivered', label: 'ส่งแล้ว' },
  { id: 'uncleared', label: 'ยังไม่เคลียร์บิล' },
  { id: 'cancelled', label: 'ยกเลิก' },
];

export function matchesFilter(o: Order, f: OrderFilter): boolean {
  if (f === 'cancelled') return o.cancelled;
  if (o.cancelled) return f === 'all';
  switch (f) {
    case 'unpaid':
      return o.paymentStatus === 'unpaid';
    case 'credit':
      return o.paymentStatus === 'credit' && !o.cleared;
    case 'waiting':
      return o.deliveryStatus === 'waiting' || o.deliveryStatus === 'dispatched';
    case 'delivered':
      return o.deliveryStatus === 'delivered';
    case 'uncleared':
      return !o.cleared;
    default:
      return true;
  }
}

export function matchesSearch(o: Order, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  const digits = q.replace(/\D/g, '');
  return (
    o.customer.name.toLowerCase().includes(q) ||
    (o.customerAliases ?? []).some((a) => a.toLowerCase().includes(q)) ||
    o.orderNo.toLowerCase().includes(q) ||
    (o.receiptNo ?? '').toLowerCase().includes(q) ||
    (digits.length >= 3 && o.customer.phone.replace(/\D/g, '').includes(digits))
  );
}

export function paymentBadge(o: Order): { tone: BadgeTone; label: string } {
  if (o.paymentStatus === 'paid') return { tone: 'success', label: 'จ่ายแล้ว' };
  if (o.paymentStatus === 'credit') return o.cleared ? { tone: 'success', label: 'เคลียร์แล้ว' } : { tone: 'info', label: 'ค้างเครดิต' };
  return { tone: 'warning', label: 'ยังไม่จ่าย' };
}

export function deliveryBadge(o: Order): { tone: BadgeTone; label: string } {
  const tone: BadgeTone =
    o.deliveryStatus === 'delivered' ? 'success' : o.deliveryStatus === 'pickup' ? 'neutral' : 'warning';
  return { tone, label: DELIVERY_STATUS_LABEL[o.deliveryStatus] };
}

/** Text the sales desk pastes into LINE for the driver. */
export function driverMessage(o: Order, zone: Zone | undefined, driver: Driver | undefined): string {
  const lines = [
    `ออเดอร์ ${o.orderNo}${driver ? ` · ${driver.name}` : ''}`,
    `ลูกค้า: ${o.customer.name}${o.customer.phone ? ` ${formatPhone(o.customer.phone)}` : ''}`,
    `สินค้า: ${o.items.map((it) => `${it.name} ${formatNumber(it.quantity)} ${it.unit}`).join(', ')}`,
  ];
  if (o.truckSize) lines.push(`รถ ${o.truckSize} คิว × ${o.trips} เที่ยว`);
  if (zone) lines.push(`ตำบล: ${zone.name}`);
  if (o.deliveryAddress) lines.push(`ที่อยู่: ${o.deliveryAddress}`);
  if (o.pinLat != null && o.pinLng != null) lines.push(`แผนที่: ${googleMapsUrl(o.pinLat, o.pinLng)}`);
  const cod = codToCollect(o);
  if (cod) lines.push(`เก็บเงินปลายทาง: ${formatMoney(cod)} บาท`);
  if (o.note) lines.push(`หมายเหตุ: ${o.note}`);
  if (o.driverToken && o.fulfillment === 'delivery' && !o.cancelled) {
    lines.push(
      '',
      cod
        ? 'หากส่งแล้ว กดลิงก์นี้เพื่อยืนยันส่งสำเร็จและแจ้งยอดเงินที่เก็บ:'
        : 'หากส่งแล้ว กดลิงก์นี้เพื่อยืนยันส่งสำเร็จ:',
      driverJobUrl(o.driverToken),
    );
  }
  return lines.join('\n');
}

export function outstanding(o: Order): number {
  return o.cancelled || o.cleared ? 0 : o.total;
}

/** One row per customer and order source: a statement never mixes ร้านวัสดุ and ท่าทราย orders. */
export interface CustomerOutstanding {
  customerId: string;
  source: OrderSource;
  name: string;
  phone: string;
  total: number;
  count: number;
  /** Uncleared orders not yet on any statement. */
  unbilledTotal: number;
  unbilledCount: number;
  oldestDate: string;
}

/** Partial payments already received on open statements, by statement id. */
export function statementPaidMap(statements: Pick<Statement, 'id' | 'status' | 'paidAmount'>[]): Record<string, number> {
  const paid: Record<string, number> = {};
  for (const s of statements) if (s.status === 'open' && s.paidAmount > 0) paid[s.id] = s.paidAmount;
  return paid;
}

export function summarizeOutstanding(orders: Order[], paidByStatement: Record<string, number> = {}): CustomerOutstanding[] {
  const map = new Map<string, CustomerOutstanding>();
  const deducted = new Set<string>();
  for (const o of orders) {
    const amount = outstanding(o);
    if (!amount) continue;
    const key = `${o.customerId}:${o.source}`;
    const row = map.get(key) ?? {
      customerId: o.customerId,
      source: o.source,
      name: o.customer.name,
      phone: o.customer.phone,
      total: 0,
      count: 0,
      unbilledTotal: 0,
      unbilledCount: 0,
      oldestDate: o.orderDate,
    };
    row.total += amount;
    row.count += 1;
    if (o.statementId && !deducted.has(o.statementId)) {
      deducted.add(o.statementId);
      row.total -= paidByStatement[o.statementId] ?? 0;
    }
    if (!o.statementId) {
      row.unbilledTotal += amount;
      row.unbilledCount += 1;
    }
    if (o.orderDate < row.oldestDate) row.oldestDate = o.orderDate;
    map.set(key, row);
  }
  return [...map.values()].sort((a, b) => b.total - a.total);
}
