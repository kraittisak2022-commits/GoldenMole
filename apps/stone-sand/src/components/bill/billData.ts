import { lineDiscount } from '../../calc/pricing';
import type { DocKind } from '../../lib/format';
import { formatNumber } from '../../lib/format';
import {
  type CustomerSnapshot,
  type Driver,
  type Order,
  type PaymentMethod,
  type Statement,
  type Zone,
} from '../../types';

export interface BillLine {
  date?: string;
  description: string;
  detail?: string;
  quantity?: number;
  unit?: string;
  unitPrice?: number;
  amount: number;
}

export interface BillData {
  kind: DocKind;
  docNo: string;
  refs: { label: string; value: string }[];
  period?: { from: string; to: string };
  date: string;
  customer: CustomerSnapshot;
  delivery?: { address: string; zone: string; truck: string; driver: string };
  lines: BillLine[];
  /** Product lines plus delivery before discount. */
  gross: number;
  discountLabel?: string;
  discountAmount: number;
  total: number;
  paymentMethod?: PaymentMethod;
  paid: boolean;
  paidAt?: string | null;
  note?: string;
  cancelled: boolean;
  verifyToken: string;
  issuedBy?: string | null;
}

export function billFromOrder(o: Order, kind: 'delivery' | 'receipt', zone?: Zone, driver?: Driver): BillData {
  const lines: BillLine[] = o.items.map((it) => {
    const off = lineDiscount(it.unitPrice, it.quantity, it.discountPerUnit);
    return {
      description: it.name,
      detail: off ? `ลด${it.unit}ละ ${formatNumber(it.discountPerUnit ?? 0)} บาท (-${formatNumber(off)})` : undefined,
      quantity: it.quantity,
      unit: it.unit,
      unitPrice: it.unitPrice,
      amount: it.amount,
    };
  });
  const itemDiscount = o.items.reduce((s, it) => s + lineDiscount(it.unitPrice, it.quantity, it.discountPerUnit), 0);
  const billDiscountPart = o.discountAmount - itemDiscount > 0.004;
  if (o.fulfillment === 'delivery' && o.trips > 0) {
    lines.push({
      description: `ค่าขนส่ง${zone ? ` ต.${zone.name}` : ''}`,
      detail: o.truckSize ? `รถ ${o.truckSize} คิว` : undefined,
      quantity: o.trips,
      unit: 'เที่ยว',
      unitPrice: o.feePerTrip,
      amount: o.feePerTrip * o.trips,
    });
    if (o.remoteSurcharge > 0) lines.push({ description: 'ค่าขนส่งเพิ่ม (พื้นที่ห่างไกล)', amount: o.remoteSurcharge });
  }

  const refs: BillData['refs'] = [];
  if (kind === 'receipt') refs.push({ label: 'อ้างอิงใบส่งของ', value: o.orderNo });
  else if (o.receiptNo) refs.push({ label: 'ใบเสร็จ', value: o.receiptNo });

  return {
    kind,
    docNo: kind === 'receipt' && o.receiptNo ? o.receiptNo : o.orderNo,
    refs,
    date: kind === 'receipt' && o.paidAt ? o.paidAt : o.orderDate,
    customer: o.customer,
    delivery:
      o.fulfillment === 'delivery'
        ? {
            address: o.deliveryAddress,
            zone: zone?.name ?? '',
            truck: o.truckSize ? `รถ ${o.truckSize} คิว × ${o.trips} เที่ยว` : '',
            driver: driver?.name ?? '',
          }
        : undefined,
    lines,
    gross: o.subtotal + o.deliveryTotal,
    discountLabel: o.discountAmount
      ? [
          itemDiscount ? 'ส่วนลดต่อคิว' : '',
          billDiscountPart ? `ส่วนลด${o.discountType === 'percent' ? ` ${formatNumber(o.discountValue)}% (ค่าสินค้า)` : ''}` : '',
        ]
          .filter(Boolean)
          .join(' + ')
      : undefined,
    discountAmount: o.discountAmount,
    total: o.total,
    paymentMethod: o.paymentMethod,
    paid: o.paymentStatus === 'paid',
    paidAt: o.paidAt,
    note: o.note,
    cancelled: o.cancelled,
    verifyToken: o.verifyToken,
    issuedBy: o.createdBy,
  };
}

export function billFromStatement(s: Statement, orders: Order[]): BillData {
  const lines: BillLine[] = orders.map((o) => ({
    description: `${o.orderNo}${o.receiptNo ? ` / ${o.receiptNo}` : ''}`,
    detail: [
      o.items.map((it) => `${it.name} ${formatNumber(it.quantity)} ${it.unit}`).join(', '),
      o.fulfillment === 'delivery' ? `ส่ง ${o.trips} เที่ยว` : 'มารับเอง',
    ].join(' · '),
    date: o.orderDate,
    amount: o.total,
  }));
  const total = orders.reduce((sum, o) => sum + o.total, 0);
  return {
    kind: 'statement',
    docNo: s.statementNo,
    refs: [],
    period: { from: s.periodFrom, to: s.periodTo },
    date: s.createdAt,
    customer: s.customer,
    lines,
    gross: total,
    discountAmount: 0,
    total: s.total,
    paymentMethod: s.paymentMethod ?? undefined,
    paid: s.status === 'cleared',
    paidAt: s.clearedAt,
    note: s.note,
    cancelled: false,
    verifyToken: s.verifyToken,
    issuedBy: s.createdBy,
  };
}

export const PAYMENT_CHOICES: PaymentMethod[] = ['cash', 'transfer', 'cod', 'credit'];
