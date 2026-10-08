import type { Customer, Product } from '../../types';
import { buildItems, initialWizardState, toDraft, validateStep, type WizardState } from './wizardState';

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
  it('requires a customer then products', () => {
    expect(validateStep(0, state({}))).not.toBe('');
    expect(validateStep(0, state({ customer }))).toBe('');
    expect(validateStep(1, state({ quantities: { 'small-stone': 0 } }))).not.toBe('');
    expect(validateStep(1, state({ quantities: { 'small-stone': 3 } }))).toBe('');
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
      quantities: { 'small-stone': 5, 'fill-sand': 5 },
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
      state({ customer, quantities: { 'fill-sand': 3 }, fulfillment: 'pickup', paymentMethod: 'credit', paidNow: true }),
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
