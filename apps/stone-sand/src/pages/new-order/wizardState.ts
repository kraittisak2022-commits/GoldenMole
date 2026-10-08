import { lineAmount } from '../../calc/pricing';
import { totalTrips, truckFits, truckForLoads, type Load } from '../../calc/trips';
import type { OrderDraft } from '../../data/orders';
import type { Customer, DiscountType, Fulfillment, OrderItem, OrderSource, PaymentMethod, Product, TruckSize } from '../../types';

export interface WizardState {
  source: OrderSource | null;
  /** YYYY-MM-DD; '' means today. */
  orderDate: string;
  customer: Customer | null;
  loads: Record<string, Load>;
  fulfillment: Fulfillment | null;
  deliveryAddress: string;
  pin: { lat: number; lng: number } | null;
  zoneId: string | null;
  tambonMethod: 'exact' | 'nearest' | 'manual' | null;
  outsideDistrict: boolean;
  roadDistanceKm: number | null;
  roadLabel: string;
  truckSize: TruckSize;
  truckTouched: boolean;
  trips: number;
  feePerTrip: number;
  feeTouched: boolean;
  remoteSurcharge: number;
  driverId: string | null;
  driverTruckSize: TruckSize | null;
  driverConfirmed: boolean;
  /** ส่วนลดบาทต่อคิว by product id. */
  unitDiscounts: Record<string, number>;
  discountType: DiscountType;
  discountValue: number;
  paymentMethod: PaymentMethod | null;
  paidNow: boolean;
  note: string;
}

export const STEPS = [
  { key: 'source', label: 'ประเภท' },
  { key: 'products', label: 'สินค้า' },
  { key: 'customer', label: 'ลูกค้า' },
  { key: 'fulfillment', label: 'รับสินค้า' },
  { key: 'summary', label: 'สรุป' },
  { key: 'confirm', label: 'ยืนยัน' },
] as const;

export type StepKey = (typeof STEPS)[number]['key'];

export const stepIndex = (key: StepKey): number => STEPS.findIndex((s) => s.key === key);

export const initialWizardState: WizardState = {
  source: null,
  orderDate: '',
  customer: null,
  loads: {},
  fulfillment: null,
  deliveryAddress: '',
  pin: null,
  zoneId: null,
  tambonMethod: null,
  outsideDistrict: false,
  roadDistanceKm: null,
  roadLabel: '',
  truckSize: 5,
  truckTouched: false,
  trips: 0,
  feePerTrip: 0,
  feeTouched: false,
  remoteSurcharge: 0,
  driverId: null,
  driverTruckSize: null,
  driverConfirmed: false,
  unitDiscounts: {},
  discountType: 'baht',
  discountValue: 0,
  paymentMethod: null,
  paidNow: false,
  note: '',
};

export function buildItems(
  products: Product[],
  quantities: Record<string, number>,
  unitDiscounts: Record<string, number> = {},
): OrderItem[] {
  return products
    .filter((p) => (quantities[p.id] || 0) > 0)
    .map((p) => ({
      productId: p.id,
      name: p.name,
      unit: p.unit,
      unitPrice: p.pricePerUnit,
      quantity: quantities[p.id],
      amount: lineAmount(p.pricePerUnit, quantities[p.id]),
      discountPerUnit: Math.min(Math.max(0, unitDiscounts[p.id] || 0), p.pricePerUnit),
    }));
}

export function totalQuantity(quantities: Record<string, number>): number {
  return Object.values(quantities).reduce((s, q) => s + (q > 0 ? q : 0), 0);
}

export function quantitiesOf(loads: Record<string, Load>): Record<string, number> {
  return Object.fromEntries(
    Object.entries(loads).map(([id, l]) => [id, Math.round(l.perTrip * l.trips * 10) / 10]),
  );
}

/**
 * Keeps the delivery step in line with the products step: trips are the trips entered per product,
 * and the truck (and selected driver's truck) must carry the largest คิวต่อเที่ยว.
 */
export function withDeliveryPlan(s: WizardState): WizardState {
  const loads = Object.values(s.loads);
  const trips = totalTrips(loads);
  const keepTruck = s.truckTouched && truckFits(s.truckSize, loads);
  const truckSize = keepTruck ? s.truckSize : truckForLoads(loads);
  const dropDriver = !!s.driverId && s.driverTruckSize != null && !truckFits(s.driverTruckSize, loads);

  if (trips === s.trips && truckSize === s.truckSize && keepTruck === s.truckTouched && !dropDriver) return s;
  return {
    ...s,
    trips,
    truckSize,
    truckTouched: keepTruck,
    ...(dropDriver ? { driverId: null, driverTruckSize: null, driverConfirmed: false } : {}),
  };
}

/** Error message for the step, or '' when the step is complete. */
export function validateStep(step: number, s: WizardState): string {
  switch (STEPS[step]?.key) {
    case 'source':
      return s.source ? '' : 'เลือกประเภทออเดอร์';
    case 'products':
      return totalQuantity(quantitiesOf(s.loads)) > 0 ? '' : 'เลือกสินค้าอย่างน้อย 1 รายการ';
    case 'customer':
      return s.customer ? '' : 'เลือกหรือเพิ่มลูกค้าก่อน';
    case 'fulfillment':
      if (!s.fulfillment) return 'เลือกว่ามารับเองหรือจัดส่ง';
      if (s.fulfillment === 'delivery') {
        if (!s.pin && !s.deliveryAddress.trim()) return 'ปักหมุดหรือใส่ที่อยู่จัดส่ง';
        if (!s.zoneId) return 'เลือกตำบลที่จัดส่ง';
        if (s.driverId && !s.driverConfirmed) return 'ยืนยันว่ารถเข้าหน้างานได้และมีคิวว่าง';
      }
      return '';
    case 'summary':
      return s.paymentMethod ? '' : 'เลือกวิธีชำระเงิน';
    default:
      return '';
  }
}

export function defaultPaidNow(method: PaymentMethod): boolean {
  return method === 'cash' || method === 'transfer';
}

export function toDraft(s: WizardState, products: Product[], driverWagePerTrip: number): OrderDraft {
  if (!s.source || !s.customer || !s.fulfillment || !s.paymentMethod) throw new Error('ข้อมูลออเดอร์ยังไม่ครบ');
  const delivery = s.fulfillment === 'delivery';
  return {
    source: s.source,
    orderDate: s.orderDate || null,
    customer: s.customer,
    items: buildItems(products, quantitiesOf(s.loads), s.unitDiscounts),
    fulfillment: s.fulfillment,
    deliveryAddress: s.deliveryAddress,
    pinLat: s.pin?.lat ?? null,
    pinLng: s.pin?.lng ?? null,
    zoneId: s.zoneId,
    roadDistanceKm: s.roadDistanceKm,
    truckSize: delivery ? s.truckSize : null,
    trips: delivery ? s.trips : 0,
    driverId: delivery ? s.driverId : null,
    feePerTrip: s.feePerTrip,
    remoteSurcharge: s.remoteSurcharge,
    discountType: s.discountType,
    discountValue: s.discountValue,
    paymentMethod: s.paymentMethod,
    paidNow: s.paymentMethod === 'credit' ? false : s.paidNow,
    driverWage: delivery && s.driverId ? driverWagePerTrip * s.trips : 0,
    note: s.note,
  };
}
