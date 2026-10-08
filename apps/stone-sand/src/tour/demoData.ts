import { lineAmount } from '../calc/pricing';
import type { OrderDraft } from '../data/orders';
import type { Customer, OrderSource, Product } from '../types';

export const DEMO_CUSTOMER_NAME = 'ลูกค้าตัวอย่าง (สาธิต)';

/** A ready-made credit pickup order so the tour can jump straight to วางบิล. */
export function demoCreditDraft(customer: Customer, product: Product, source: OrderSource): OrderDraft {
  const quantity = 2;
  return {
    source,
    orderDate: null,
    customer,
    items: [
      {
        id: 'demo-item',
        productId: product.id,
        name: product.name,
        unit: product.unit,
        unitPrice: product.pricePerUnit,
        quantity,
        amount: lineAmount(product.pricePerUnit, quantity),
        discountPerUnit: 0,
      },
    ],
    fulfillment: 'pickup',
    deliveryAddress: '',
    pinLat: null,
    pinLng: null,
    zoneId: null,
    roadDistanceKm: null,
    truckSize: null,
    trips: 0,
    driverId: null,
    feePerTrip: 0,
    remoteSurcharge: 0,
    deliveryDiscount: 0,
    discountType: 'baht',
    discountValue: 0,
    paymentMethod: 'credit',
    paidNow: false,
    driverWage: 0,
    note: 'ออเดอร์สาธิต',
  };
}
