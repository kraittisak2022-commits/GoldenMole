import type { Customer, Product } from '../../types';
import {
  STEPS,
  buildItems,
  driverFeeKey,
  editedDriverFee,
  initialWizardState,
  quantitiesOf,
  stepIndex,
  toDraft,
  validateStep,
  withDeliveryPlan,
  type WizardState,
} from './wizardState';

const products: Product[] = [
  { id: 'small-stone', name: 'หินเล็กคละ เบอร์ 1-3', category: 'stone', unit: 'คิว', pricePerUnit: 400, pickupPricePerUnit: 300, sortOrder: 1, active: true },
  { id: 'fill-sand', name: 'ทรายถม (ทรายขี้เป็ด)', category: 'sand', unit: 'คิว', pricePerUnit: 220, pickupPricePerUnit: 200, sortOrder: 3, active: true },
];

const customer: Customer = {
  id: 'cus-1',
  name: 'สมชาย',
  aliases: [],
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

const SOURCE = stepIndex('source');
const PRODUCTS = stepIndex('products');
const CUSTOMER = stepIndex('customer');
const FULFILLMENT = stepIndex('fulfillment');

describe('validateStep', () => {
  it('asks for the order source first, then products, then the customer', () => {
    expect(STEPS.map((s) => s.key)).toEqual(['source', 'products', 'customer', 'fulfillment', 'summary', 'confirm']);
    expect(validateStep(SOURCE, state({}))).toMatch(/ประเภท/);
    expect(validateStep(SOURCE, state({ source: 'pit' }))).toBe('');
    expect(validateStep(PRODUCTS, state({ loads: { 'small-stone': { perTrip: 3, trips: 0 } } }))).toMatch(/สินค้า/);
    expect(validateStep(PRODUCTS, state({ loads: { 'small-stone': { perTrip: 3, trips: 1 } } }))).toBe('');
    expect(validateStep(CUSTOMER, state({}))).toMatch(/ลูกค้า/);
    expect(validateStep(CUSTOMER, state({ customer }))).toBe('');
  });

  it('pickup needs nothing else; delivery needs location, tambon and driver', () => {
    expect(validateStep(FULFILLMENT, state({ fulfillment: 'pickup' }))).toBe('');
    expect(validateStep(FULFILLMENT, state({ fulfillment: 'delivery' }))).toMatch(/ปักหมุด/);
    expect(validateStep(FULFILLMENT, state({ fulfillment: 'delivery', pin: { lat: 19.2, lng: 99.6 } }))).toMatch(/ตำบล/);
    expect(
      validateStep(FULFILLMENT, state({ fulfillment: 'delivery', pin: { lat: 19.2, lng: 99.6 }, zoneId: 'thung-hua' })),
    ).toBe('เลือกคนขับ');
  });

  it('asks to confirm the driver is available', () => {
    const s = state({ fulfillment: 'delivery', deliveryAddress: 'x', zoneId: 'thung-hua', driverId: 'drv-ko' });
    expect(validateStep(FULFILLMENT, s)).toMatch(/คิวว่าง/);
    expect(validateStep(FULFILLMENT, { ...s, driverConfirmed: true })).toBe('');
  });
});

describe('toDraft', () => {
  it('builds items and driver wage from the wizard', () => {
    const s = state({
      source: 'shop',
      customer,
      loads: { 'small-stone': { perTrip: 5, trips: 1 }, 'fill-sand': { perTrip: 5, trips: 1 } },
      fulfillment: 'delivery',
      zoneId: 'thung-hua',
      trips: 2,
      truckSize: 5,
      feePerCubic: 40,
      feePerTrip: 350,
      driverId: 'drv-ko',
      driverConfirmed: true,
      paymentMethod: 'cash',
      paidNow: true,
      deliveryDiscount: 100,
    });
    const d = toDraft(s, products, 500);
    expect(d.source).toBe('shop');
    expect(d.items.map((i) => i.amount)).toEqual([2000, 1100]);
    expect(d.driverWage).toBe(1000);
    expect(d.driverWageManual).toBe(false);
    const free = toDraft({ ...s, driverFeeEdit: { perTrip: 0, key: driverFeeKey(s) } }, products, 0);
    expect(free.driverWage).toBe(0);
    expect(free.driverWageManual).toBe(true);
    expect(d.deliveryDiscount).toBe(100);
    expect(d.feePerCubic).toBe(40);
    expect(d.paidNow).toBe(true);
  });

  it('credit orders are never paid now and pickup drops delivery fields', () => {
    const d = toDraft(
      state({
        source: 'pit',
        customer,
        loads: { 'fill-sand': { perTrip: 3, trips: 1 } },
        fulfillment: 'pickup',
        paymentMethod: 'credit',
        paidNow: true,
        deliveryDiscount: 200,
      }),
      products,
      500,
    );
    expect(d.source).toBe('pit');
    expect(d.paidNow).toBe(false);
    expect(d.trips).toBe(0);
    expect(d.driverWage).toBe(0);
    expect(d.deliveryDiscount).toBe(0);
  });

  it('sends the chosen order date, or null so the database uses today', () => {
    const base = { source: 'shop' as const, customer, loads: { 'fill-sand': { perTrip: 3, trips: 1 } }, fulfillment: 'pickup' as const, paymentMethod: 'cash' as const };
    expect(toDraft(state(base), products, 0).orderDate).toBeNull();
    expect(toDraft(state({ ...base, orderDate: '2026-10-01' }), products, 0).orderDate).toBe('2026-10-01');
  });

  it('refuses to build an order without a source', () => {
    expect(() =>
      toDraft(state({ customer, loads: { 'fill-sand': { perTrip: 3, trips: 1 } }, fulfillment: 'pickup', paymentMethod: 'cash' }), products, 0),
    ).toThrow();
  });

  it('skips products with zero quantity', () => {
    expect(buildItems(products, { 'small-stone': 0, 'fill-sand': 1 })).toHaveLength(1);
  });

  it('prices pickup orders at the pickup price and delivery (or undecided) at the delivery price', () => {
    const qty = { 'small-stone': 5 };
    const price = (f: WizardState['fulfillment']) => buildItems(products, qty, { 'small-stone': 350 }, f)[0];
    expect(price('pickup')).toMatchObject({ unitPrice: 300, amount: 1500, discountPerUnit: 300 });
    expect(price('delivery')).toMatchObject({ unitPrice: 400, amount: 2000, discountPerUnit: 350 });
    expect(price(null).unitPrice).toBe(400);

    const loads = { 'small-stone': { perTrip: 5, trips: 1 } };
    const draft = (f: 'pickup' | 'delivery') =>
      toDraft(state({ source: 'shop', customer, loads, fulfillment: f, paymentMethod: 'cash' }), products, 0);
    expect(draft('pickup').items[0].unitPrice).toBe(300);
    expect(draft('delivery').items[0].unitPrice).toBe(400);
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

describe('editedDriverFee', () => {
  it('uses the typed driver pay only for the tambon and truck size it was typed for', () => {
    const s = state({ zoneId: 'z1', truckSize: 5 });
    const edited = { ...s, driverFeeEdit: { perTrip: 450, key: driverFeeKey(s) } };
    expect(editedDriverFee(s)).toBeNull();
    expect(editedDriverFee(edited)).toBe(450);
    expect(editedDriverFee({ ...edited, truckSize: 3 })).toBeNull();
    expect(editedDriverFee({ ...edited, zoneId: 'z2' })).toBeNull();
  });
});