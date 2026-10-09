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

/** shop = ออเดอร์จากร้านวัสดุก่อสร้าง, pit = สั่งจากท่าทรายโดยตรง (เลขที่ TS). */
export type OrderSource = 'shop' | 'pit';

export const ORDER_SOURCE_LABEL: Record<OrderSource, string> = {
  shop: 'ร้านวัสดุก่อสร้าง',
  pit: 'ท่าทราย',
};

export const ORDER_SOURCE_SHORT: Record<OrderSource, string> = {
  shop: 'ร้านวัสดุ',
  pit: 'ท่าทราย',
};

export const ORDER_SOURCES = Object.keys(ORDER_SOURCE_LABEL) as OrderSource[];

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
  /** Customer delivery fee per trip near the main road; the distance surcharge is added on top. */
  feeMin: number;
  /** Paid to the driver per trip with a 5-คิว truck. */
  driverFee: number;
  /** Paid to the driver per trip with a 3-คิว truck. */
  driverFee3: number;
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
  /** Other names the customer is called by (e.g. เสี่ยบาส for ร้านสินทวีวังเหนือ); searchable. */
  aliases: string[];
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
  /** List price × quantity; the per-คิว discount is counted in the order's discountAmount. */
  amount: number;
  /** ส่วนลดบาทต่อคิว for this product. */
  discountPerUnit?: number;
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
  source: OrderSource;
  orderDate: string;
  customerId: string;
  customer: CustomerSnapshot;
  /** From the live customer record, for search only; never part of the bill snapshot. */
  customerAliases?: string[];
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
  /** ส่วนลดค่าส่ง (baht); included in discountAmount. */
  deliveryDiscount: number;
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
  /** Secret for the driver's /d/:token confirm page. */
  driverToken?: string;
  /** Cash the driver said they collected (COD), via the confirm link. */
  driverCashReported?: number | null;
  driverReportedAt?: string | null;
  statusLog: StatusLogEntry[];
  createdBy: string | null;
  createdAt: string;
  items: OrderItem[];
  statementId?: string | null;
  driverPayoutId?: string | null;
  /** Created during the guided tour; carries DEMO- document numbers and is deleted when the tour ends. */
  demo?: boolean;
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
  source: OrderSource;
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
  /** Oldest first. */
  payments: StatementPayment[];
  paidAmount: number;
  /** total − paidAmount; 0 once cleared. */
  balance: number;
  demo?: boolean;
}

export interface StatementPayment {
  id: string;
  amount: number;
  method: 'cash' | 'transfer';
  paidAt: string;
  note: string;
  createdBy: string | null;
}

export interface CompanySettings {
  nameTh: string;
  nameEn: string;
  address: string;
  taxId: string;
  phone: string;
}

export interface DeliverySettings {
  /** Distance from the main road with no surcharge. */
  nearKm: number;
  /**
   * Baht per km beyond nearKm, per trip, by truck size (5 คิว is also used when the size is unknown).
   * Charged to the customer and paid to the driver alike.
   */
  driverPerKm5: number;
  driverPerKm3: number;
}

export interface PaymentSettings {
  promptPayId: string;
  bankText: string;
  /** Shown in the bill header as the payment channel. */
  bankName: string;
  bankAccountNo: string;
  bankAccountName: string;
  /** Text of the shop's payment QR (Thai QR / EMVCo), drawn in the bill header. */
  qrPayload: string;
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
  delivery: { nearKm: 0.5, driverPerKm5: 0, driverPerKm3: 0 },
  payment: { promptPayId: '', bankText: '', bankName: '', bankAccountNo: '', bankAccountName: '', qrPayload: '' },
};
