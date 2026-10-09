import type { BadgeTone } from '../components/ui/Badge';
import type { DeliverySettings, Order, Zone } from '../types';
import { customerDeliveryFee, suggestedDriverPay } from './driverPay';
import { outstanding } from './orderStatus';

/** Where an order is held up, in the order the desk works through them. */
export type BillStage =
  | 'needDriver'
  | 'waitDelivery'
  | 'onTheWay'
  | 'driverCash'
  | 'unbilled'
  | 'billed'
  | 'awaitPayment'
  | 'payDriver'
  | 'done'
  | 'cancelled';

export const BILL_STAGES: { id: BillStage; label: string; tone: BadgeTone }[] = [
  { id: 'needDriver', label: 'รอเลือกคนขับ', tone: 'danger' },
  { id: 'waitDelivery', label: 'รอจัดส่ง', tone: 'warning' },
  { id: 'onTheWay', label: 'กำลังส่ง', tone: 'warning' },
  { id: 'driverCash', label: 'รอรับเงินจากคนขับ', tone: 'warning' },
  { id: 'unbilled', label: 'รอวางบิล', tone: 'info' },
  { id: 'billed', label: 'รอลูกค้าจ่ายตามใบวางบิล', tone: 'info' },
  { id: 'awaitPayment', label: 'รอรับเงิน', tone: 'warning' },
  { id: 'payDriver', label: 'รอเคลียร์ค่ารถ', tone: 'info' },
  { id: 'done', label: 'ปิดงานแล้ว', tone: 'success' },
  { id: 'cancelled', label: 'ยกเลิก', tone: 'neutral' },
];

export const BILL_STAGE = Object.fromEntries(BILL_STAGES.map((s) => [s.id, s])) as Record<
  BillStage,
  (typeof BILL_STAGES)[number]
>;

export type StepState = 'done' | 'current' | 'todo' | 'skip';

export interface BillStep {
  key: 'order' | 'delivery' | 'payment' | 'driver';
  label: string;
  state: StepState;
}

export interface BillSummary {
  /** ยอดบิล: what the customer is charged. */
  revenue: number;
  /** ค่าสินค้า after all discounts other than the delivery discount. */
  goods: number;
  /** ค่าส่งที่เก็บลูกค้า after the delivery discount. */
  deliveryFee: number;
  /** ค่ารถที่จ่ายคนขับ: the paid amount, or the default rate while unpaid. */
  driverCost: number;
  /** driverCost is a forecast because the driver has not been paid yet. */
  driverCostEstimated: boolean;
  /** เงินที่เหลือเข้าร้าน: revenue − driverCost. */
  net: number;
  /** ค่าส่งที่เก็บลูกค้า − ค่ารถคนขับ; negative means delivery runs at a loss. */
  deliveryMargin: number;
  received: number;
  receivable: number;
  stage: BillStage;
  steps: BillStep[];
}

type ZoneOf = (id: string | null) => Pick<Zone, 'driverFee' | 'driverFee3'> | undefined;

function moneyStage(o: Order): BillStage | null {
  if (o.cleared || o.paymentStatus === 'paid') return null;
  if (o.statementId) return 'billed';
  if (o.paymentMethod === 'cod' && o.fulfillment === 'delivery') return 'driverCash';
  if (o.paymentStatus === 'credit') return 'unbilled';
  return 'awaitPayment';
}

export function billStage(o: Order): BillStage {
  if (o.cancelled) return 'cancelled';
  const delivery = o.fulfillment === 'delivery';
  if (delivery && !o.driverId) return 'needDriver';
  if (delivery && o.deliveryStatus === 'waiting') return 'waitDelivery';
  if (delivery && o.deliveryStatus === 'dispatched') return 'onTheWay';
  const money = moneyStage(o);
  if (money) return money;
  if (delivery && !o.driverPayoutId) return 'payDriver';
  return 'done';
}

function billSteps(o: Order): BillStep[] {
  const delivery = o.fulfillment === 'delivery';
  const delivered = !delivery || o.deliveryStatus === 'delivered';
  const paid = o.cleared || o.paymentStatus === 'paid';
  const driverPaid = !!o.driverPayoutId;
  const steps: BillStep[] = [
    { key: 'order', label: 'เปิดบิล', state: 'done' },
    { key: 'delivery', label: delivery ? 'จัดส่ง' : 'รับสินค้า', state: delivered ? 'done' : 'todo' },
    { key: 'payment', label: 'รับเงิน', state: paid ? 'done' : 'todo' },
    { key: 'driver', label: 'จ่ายค่ารถ', state: !delivery ? 'skip' : driverPaid ? 'done' : 'todo' },
  ];
  if (!o.cancelled) {
    const next = steps.find((s) => s.state === 'todo');
    if (next) next.state = 'current';
  }
  return steps;
}

export function summarizeBill(o: Order, zoneOf: ZoneOf, delivery: DeliverySettings): BillSummary {
  const steps = billSteps(o);
  const stage = billStage(o);
  if (o.cancelled) {
    return {
      revenue: 0,
      goods: 0,
      deliveryFee: 0,
      driverCost: 0,
      driverCostEstimated: false,
      net: 0,
      deliveryMargin: 0,
      received: 0,
      receivable: 0,
      stage,
      steps,
    };
  }
  const deliveryFee = customerDeliveryFee(o);
  const goods = o.total - deliveryFee;
  const hasDriver = o.fulfillment === 'delivery' && !!o.driverId;
  const driverCostEstimated = hasDriver && !o.driverPayoutId;
  const driverCost = !hasDriver ? 0 : o.driverPayoutId ? o.driverWage : suggestedDriverPay(o, zoneOf(o.zoneId), delivery);
  const receivable = outstanding(o);
  return {
    revenue: o.total,
    goods,
    deliveryFee,
    driverCost,
    driverCostEstimated,
    net: o.total - driverCost,
    deliveryMargin: deliveryFee - driverCost,
    received: o.total - receivable,
    receivable,
    stage,
    steps,
  };
}

export interface BillTotals {
  count: number;
  revenue: number;
  goods: number;
  deliveryFee: number;
  driverCost: number;
  /** Part of driverCost not paid out yet. */
  driverCostPending: number;
  net: number;
  received: number;
  receivable: number;
}

export function totalBills(rows: BillSummary[]): BillTotals {
  const t: BillTotals = {
    count: 0,
    revenue: 0,
    goods: 0,
    deliveryFee: 0,
    driverCost: 0,
    driverCostPending: 0,
    net: 0,
    received: 0,
    receivable: 0,
  };
  for (const r of rows) {
    if (r.stage === 'cancelled') continue;
    t.count += 1;
    t.revenue += r.revenue;
    t.goods += r.goods;
    t.deliveryFee += r.deliveryFee;
    t.driverCost += r.driverCost;
    if (r.driverCostEstimated) t.driverCostPending += r.driverCost;
    t.net += r.net;
    t.received += r.received;
    t.receivable += r.receivable;
  }
  return t;
}

/** Share of the bill the shop keeps, as a whole percent; null when there is no revenue. */
export function netMargin(net: number, revenue: number): number | null {
  return revenue > 0 ? Math.round((net / revenue) * 100) : null;
}

const csvCell = (v: string | number) => {
  const s = String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

/** Spreadsheet export; the BOM makes Excel read the Thai text as UTF-8. */
export function billSummaryCsv(rows: { order: Order; summary: BillSummary; driverName: string }[]): string {
  const header = [
    'เลขที่',
    'วันที่',
    'ลูกค้า',
    'รับสินค้า',
    'คนขับ',
    'ยอดบิล',
    'ค่าสินค้า',
    'ค่าส่งเก็บลูกค้า',
    'ค่ารถคนขับ',
    'ค่ารถ (ประมาณ)',
    'คงเหลือเข้าร้าน',
    'กำไรค่าส่ง',
    'รับเงินแล้ว',
    'ค้างรับ',
    'ขั้นตอน',
  ];
  const lines = rows.map(({ order: o, summary: s, driverName }) =>
    [
      o.orderNo,
      o.orderDate,
      o.customer.name,
      o.fulfillment === 'delivery' ? 'จัดส่ง' : 'มารับเอง',
      driverName,
      s.revenue,
      s.goods,
      s.deliveryFee,
      s.driverCost,
      s.driverCostEstimated ? 'ใช่' : '',
      s.net,
      s.deliveryMargin,
      s.received,
      s.receivable,
      BILL_STAGE[s.stage].label,
    ]
      .map(csvCell)
      .join(','),
  );
  return `\uFEFF${[header.join(','), ...lines].join('\n')}`;
}

/** Where to go to move the order past its stage. */
export function stageAction(o: Order, stage: BillStage): { to: string; label: string } | null {
  switch (stage) {
    case 'needDriver':
    case 'waitDelivery':
    case 'onTheWay':
    case 'awaitPayment':
      return { to: `/orders/${o.id}`, label: 'เปิดออเดอร์' };
    case 'driverCash':
    case 'payDriver':
      return { to: `/driver-pay?driver=${o.driverId}`, label: 'ไปเคลียร์ค่ารถ' };
    case 'unbilled':
      return { to: `/statements?customer=${o.customerId}&source=${o.source}`, label: 'ไปออกใบวางบิล' };
    case 'billed':
      return { to: `/statements?open=${o.statementId}`, label: 'ดูใบวางบิล' };
    default:
      return null;
  }
}
