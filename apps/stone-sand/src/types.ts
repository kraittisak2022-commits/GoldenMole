export type RouteGroup = 'north' | 'south' | 'thungpao';
export type TruckSize = 3 | 5;
export type Fulfillment = 'pickup' | 'delivery';
export type PaymentMethod = 'cash' | 'transfer' | 'cod' | 'credit';
export type PaymentStatus = 'unpaid' | 'paid' | 'credit';
export type DeliveryStatus = 'pickup' | 'waiting' | 'dispatched' | 'delivered';
export type DiscountType = 'baht' | 'percent';

export type ProductCategory = 'stone' | 'sand';

export const PRODUCT_CATEGORY_LABEL: Record<ProductCategory, string> = {
  stone: 'หิน',
  sand: 'ทราย',
};

export interface Product {
  id: string;
  name: string;
  category: ProductCategory;
  unit: string;
  pricePerUnit: number;
  sortOrder: number;
  active: boolean;
}

export interface Zone {
  id: string;
  name: string;
  feeMin: number;
  feeMax: number;
  sortOrder: number;
}

export interface DriverContact {
  label: string;
  phone: string;
}

export interface Driver {
  id: string;
  name: string;
  village: string;
  routeGroup: RouteGroup;
  truckSize: TruckSize;
  truckCount: number;
  contacts: DriverContact[];
  contactNote: string;
  wagePerTrip: number;
  active: boolean;
  sortOrder: number;
}

export interface Customer {
  id: string;
  name: string;
  phone: string;
  address: string;
  zoneId: string | null;
  taxId: string;
  lat: number | null;
  lng: number | null;
  isCredit: boolean;
  note: string;
  createdAt: string;
}

export interface CustomerSnapshot {
  name: string;
  phone: string;
  address: string;
  taxId: string;
}

export interface OrderItem {
  id?: string;
  productId: string | null;
  name: string;
  unit: string;
  unitPrice: number;
  quantity: number;
  amount: number;
}

export interface StatusLogEntry {
  at: string;
  by: string;
  event: string;
}

export interface Order {
  id: string;
  orderNo: string;
  receiptNo: string | null;
  orderDate: string;
  customerId: string;
  customer: CustomerSnapshot;
  fulfillment: Fulfillment;
  deliveryAddress: string;
  pinLat: number | null;
  pinLng: number | null;
  zoneId: string | null;
  roadDistanceKm: number | null;
  truckSize: TruckSize | null;
  trips: number;
  driverId: string | null;
  feePerTrip: number;
  remoteSurcharge: number;
  discountType: DiscountType;
  discountValue: number;
  subtotal: number;
  deliveryTotal: number;
  discountAmount: number;
  total: number;
  paymentMethod: PaymentMethod;
  paymentStatus: PaymentStatus;
  paidAt: string | null;
  deliveryStatus: DeliveryStatus;
  deliveredAt: string | null;
  cleared: boolean;
  clearedAt: string | null;
  driverWage: number;
  note: string;
  cancelled: boolean;
  verifyToken: string;
  statusLog: StatusLogEntry[];
  createdBy: string | null;
  createdAt: string;
  items: OrderItem[];
  statementId?: string | null;
  driverPayoutId?: string | null;
}

export interface DriverPayoutOrder {
  id: string;
  orderNo: string;
  orderDate: string;
  customerName: string;
  trips: number;
  amount: number;
}

export interface DriverPayout {
  id: string;
  payoutNo: string;
  driverId: string;
  driverName: string;
  /** ค่ารถ paid to the driver. */
  total: number;
  /** COD money the driver handed over in this payout. */
  cashCollected: number;
  method: 'cash' | 'transfer';
  note: string;
  createdBy: string | null;
  createdAt: string;
  orders: DriverPayoutOrder[];
}

export interface Statement {
  id: string;
  statementNo: string;
  customerId: string;
  customer: CustomerSnapshot;
  periodFrom: string;
  periodTo: string;
  total: number;
  status: 'open' | 'cleared';
  paymentMethod: 'cash' | 'transfer' | null;
  clearedAt: string | null;
  verifyToken: string;
  note: string;
  createdBy: string | null;
  createdAt: string;
  orderIds: string[];
}

export interface CompanySettings {
  nameTh: string;
  nameEn: string;
  address: string;
  taxId: string;
  phone: string;
}

export interface DeliverySettings {
  nearKm: number;
  maxKm: number;
  roundTo: number;
}

export interface PaymentSettings {
  promptPayId: string;
  bankText: string;
}

export interface AppSettings {
  company: CompanySettings;
  delivery: DeliverySettings;
  payment: PaymentSettings;
}

export const ROUTE_GROUP_LABEL: Record<RouteGroup, string> = {
  north: 'สายเหนือ',
  south: 'สายใต้',
  thungpao: 'ทุ่งเป้า-บ้านใหม่',
};

export const PAYMENT_METHOD_LABEL: Record<PaymentMethod, string> = {
  cash: 'เงินสด',
  transfer: 'โอนเงิน',
  cod: 'จ่ายปลายทาง',
  credit: 'เครดิตรายเดือน',
};

export const PAYMENT_STATUS_LABEL: Record<PaymentStatus, string> = {
  unpaid: 'ยังไม่จ่าย',
  paid: 'จ่ายแล้ว',
  credit: 'ค้างเครดิต',
};

export const DELIVERY_STATUS_LABEL: Record<DeliveryStatus, string> = {
  pickup: 'มารับเอง',
  waiting: 'รอจัดส่ง',
  dispatched: 'กำลังส่ง',
  delivered: 'ส่งแล้ว',
};

export const DEFAULT_SETTINGS: AppSettings = {
  company: {
    nameTh: 'ห้างหุ้นส่วนจำกัด พีรสิทธิ์ วัสดุก่อสร้าง',
    nameEn: 'PIRASIT CONSTRUCTION MATERIALS LIMITED PARTNERSHIP',
    address: '132 หมู่ที่ 2 ตำบลวังแก้ว อำเภอวังเหนือ จังหวัดลำปาง 52140',
    taxId: '0523566002017',
    phone: '065-8124686',
  },
  delivery: { nearKm: 3, maxKm: 10, roundTo: 50 },
  payment: { promptPayId: '', bankText: '' },
};
