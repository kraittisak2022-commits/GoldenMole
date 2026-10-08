import type { Customer, Product } from '../../types';
import {
  STEPS,
  buildItems,
  initialWizardState,
  quantitiesOf,
  toDraft,
  validateStep,
  withDeliveryPlan,
  type WizardState,
} from './wizardState';

const products: Product[] = [
  { id: 'small-stone', name: 'หินเล็กคละ เบอร์ 1-3', unit: 'คิว', pricePerUnit: 400, sortOrder: 1, active: true },
  { id: 'fill-sand', name: 'ทรายถม (ทรายขี้เป็ด)', unit: 'คิว', pricePerUnit: 220, sortOrder: 3, active: true },
];

const customer: Customer = {
  id: 'cus-1',
  name: 'สมชาย',
  phone: '0931234567',
  address: 'บ้านทุ่งฮั้ว',
  zoneId: null,
  taxId: '',
  lat: null,
  lng: null,
  isCredit: false,
  note: '',
  createdAt: '',
};

const state = (patch: Partial<WizardState>): WizardState => ({ ...initialWizardState, ...patch });

describe('validateStep', () => {
  it('asks for products first, then the customer', () => {
    expect(STEPS.map((s) => s.key)).toEqual(['products', 'customer', 'fulfillment', 'summary', 'confirm']);
    expect(validateStep(0, state({ loads: { 'small-stone': { perTrip: 3, trips: 0 } } }))).toMatch(/สินค้า/);
    expect(validateStep(0, state({ loads: { 'small-stone': { perTrip: 3, trips: 1 } } }))).toBe('');
    expect(validateStep(1, state({}))).toMatch(/ลูกค้า/);
    expect(validateStep(1, state({ customer }))).toBe('');
  });

  it('pickup needs nothing else; delivery needs tambon and location', () => {
    expect(validateStep(2, state({ fulfillment: 'pickup' }))).toBe('');
    expect(validateStep(2, state({ fulfillment: 'delivery' }))).toMatch(/ปักหมุด/);
    expect(validateStep(2, state({ fulfillment: 'delivery', pin: { lat: 19.2, lng: 99.6 } }))).toMatch(/ตำบล/);
    expect(
      validateStep(2, state({ fulfillment: 'delivery', pin: { lat: 19.2, lng: 99.6 }, zoneId: 'thung-hua' })),
    ).toBe('');
  });

  it('asks to confirm the driver is available', () => {
    const s = state({ fulfillment: 'delivery', deliveryAddress: 'x', zoneId: 'thung-hua', driverId: 'drv-ko' });
    expect(validateStep(2, s)).toMatch(/คิวว่าง/);
    expect(validateStep(2, { ...s, driverConfirmed: true })).toBe('');
  });
});

describe('toDraft', () => {
  it('builds items and driver wage from the wizard', () => {
    const s = state({
      customer,
      loads: { 'small-stone': { perTrip: 5, trips: 1 }, 'fill-sand': { perTrip: 5, trips: 1 } },
      fulfillment: 'delivery',
      zoneId: 'thung-hua',
      trips: 2,
      truckSize: 5,
      feePerTrip: 350,
      driverId: 'drv-ko',
      driverConfirmed: true,
      paymentMethod: 'cash',
      paidNow: true,
    });
    const d = toDraft(s, products, 500);
    expect(d.items.map((i) => i.amount)).toEqual([2000, 1100]);
    expect(d.driverWage).toBe(1000);
    expect(d.paidNow).toBe(true);
  });

  it('credit orders are never paid now and pickup drops delivery fields', () => {
    const d = toDraft(
      state({ customer, loads: { 'fill-sand': { perTrip: 3, trips: 1 } }, fulfillment: 'pickup', paymentMethod: 'credit', paidNow: true }),
      products,
      500,
    );
    expect(d.paidNow).toBe(false);
    expect(d.trips).toBe(0);
    expect(d.driverWage).toBe(0);
  });

  it('skips products with zero quantity', () => {
    expect(buildItems(products, { 'small-stone': 0, 'fill-sand': 1 })).toHaveLength(1);
  });
});

describe('withDeliveryPlan', () => {
  it('takes trips from the products and the smallest truck that fits', () => {
    const s = withDeliveryPlan(state({ loads: { 'small-stone': { perTrip: 3, trips: 2 }, 'fill-sand': { perTrip: 2, trips: 1 } } }));
    expect(s.trips).toBe(3);
    expect(s.truckSize).toBe(3);
  });

  it('keeps a bigger truck the user chose, but never one that is too small', () => {
    const loads = { 'small-stone': { perTrip: 3, trips: 2 } };
    expect(withDeliveryPlan(state({ loads, truckSize: 5, truckTouched: true })).truckSize).toBe(5);
    const grown = withDeliveryPlan(state({ loads: { 'small-stone': { perTrip: 5, trips: 2 } }, truckSize: 3, truckTouched: true }));
    expect(grown.truckSize).toBe(5);
    expect(grown.truckTouched).toBe(false);
  });

  it('drops a driver whose truck no longer carries the load', () => {
    const picked = state({ driverId: 'drv-ko', driverTruckSize: 3, driverConfirmed: true, truckSize: 3, truckTouched: true });
    const fits = withDeliveryPlan({ ...picked, loads: { 'small-stone': { perTrip: 3, trips: 1 } } });
    expect(fits.driverId).toBe('drv-ko');
    const tooBig = withDeliveryPlan({ ...picked, loads: { 'small-stone': { perTrip: 5, trips: 1 } } });
    expect(tooBig.driverId).toBeNull();
    expect(tooBig.driverConfirmed).toBe(false);
    expect(tooBig.truckSize).toBe(5);
  });

  it('returns the same object when nothing changes', () => {
    const s = withDeliveryPlan(state({ loads: { 'small-stone': { perTrip: 3, trips: 1 } } }));
    expect(withDeliveryPlan(s)).toBe(s);
  });
});

describe('quantitiesOf', () => {
  it('multiplies คิวต่อเที่ยว by trips', () => {
    expect(quantitiesOf({ 'small-stone': { perTrip: 3, trips: 2 }, 'fill-sand': { perTrip: 5, trips: 0 } })).toEqual({
      'small-stone': 6,
      'fill-sand': 0,
    });
  });
});
