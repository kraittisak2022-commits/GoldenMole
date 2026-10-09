import type { DiscountType, OrderSource, PaymentMethod } from '../../src/types';

export type ProductId = 'small-stone' | 'big-stone' | 'fill-sand' | 'mortar-sand';
export type ZoneId =
  | 'thung-hua'
  | 'wang-kaeo'
  | 'wang-nuea'
  | 'wang-sai'
  | 'wang-tai'
  | 'wang-sai-kham'
  | 'wang-thong'
  | 'rong-kho';

export interface CaseItem {
  product: ProductId;
  perTrip: number;
  trips: number;
  /** ลดคิวละ (บาท) */
  unitDiscount?: number;
}

export interface CaseDelivery {
  zone: ZoneId;
  address: string;
  driver: string;
  remote?: number;
  /** ลดค่าส่งที่ให้แอดมินพิมพ์ (ระบบอาจตัดให้ไม่เกินค่าส่ง) */
  deliveryDiscount?: number;
}

/** Actions after the order is saved, done in order; generate.ts works out what the system should show after each. */
export type AfterStep =
  /** Open the driver's confirm link and press ยืนยันส่งสำเร็จ; cash = what the driver reports for COD. */
  | { do: 'driverLink'; cash?: 'full' | number }
  | { do: 'shopDelivered' }
  | { do: 'shopDispatched' }
  | { do: 'receive'; method: 'cash' | 'transfer' | 'cod' }
  | { do: 'undoPay' }
  | { do: 'statement' }
  /** tryFullAsPartial: first type the whole balance as "จ่ายบางส่วน", which the form must refuse. */
  | { do: 'payStatement'; amount: number | 'full'; method: 'cash' | 'transfer'; tryFullAsPartial?: boolean }
  | { do: 'deleteStatementPayment' }
  | { do: 'deleteStatement' }
  /** net = deduct the fee from the COD cash now; later = take all the cash, pay the fee in the monthly clearing. */
  | { do: 'clearDriver'; mode?: 'net' | 'later' }
  | { do: 'deletePayout' }
  | { do: 'cancel' }
  | { do: 'restore' };

export interface StudyCase {
  title: string;
  level: 'พื้นฐาน' | 'ปานกลาง' | 'ท้าทาย';
  topics: string[];
  story: string;
  source: OrderSource;
  customer: { name: string; phone: string; address: string };
  items: CaseItem[];
  delivery?: CaseDelivery;
  billDiscount?: { type: DiscountType; value: number };
  payment: PaymentMethod;
  /** Defaults to true for cash/transfer. */
  paidNow?: boolean;
  note?: string;
  /** Extra steps the admin must try while entering the case. */
  tryFirst?: string[];
  /** What the checker should see for those steps. */
  expectBehaviour?: string[];
  after?: AfterStep[];
}

export const CASES: StudyCase[] = [
  {
    title: 'ลูกค้ามารับเอง จ่ายเงินสด',
    level: 'พื้นฐาน',
    topics: ['มารับเอง', 'เงินสด'],
    story: 'ลุงแก้วขับรถกระบะมาที่ท่าทราย ขอซื้อทรายถม 3 คิว ตักใส่รถเที่ยวเดียว จ่ายเงินสดทันที',
    source: 'pit',
    customer: { name: 'ทดสอบ01 ลุงแก้ว ใจดี', phone: '0990000101', address: '12 ม.3 ต.วังเหนือ' },
    items: [{ product: 'fill-sand', perTrip: 3, trips: 1 }],
    payment: 'cash',
  },
  {
    title: 'มารับเอง โอนเงินแล้ว',
    level: 'พื้นฐาน',
    topics: ['มารับเอง', 'โอนเงิน'],
    story: 'ช่างบุญมีมารับหินเล็กคละ 5 คิว ด้วยรถตัวเอง โอนเงินเข้าบัญชีร้านเรียบร้อยแล้ว (เห็นสลิปแล้ว)',
    source: 'pit',
    customer: { name: 'ทดสอบ02 ช่างบุญมี', phone: '0990000102', address: '45 ม.7 ต.วังแก้ว' },
    items: [{ product: 'small-stone', perTrip: 5, trips: 1 }],
    payment: 'transfer',
  },
  {
    title: 'มารับเอง บอกว่าจะโอน แต่ยังไม่โอน',
    level: 'พื้นฐาน',
    topics: ['มารับเอง', 'โอนเงิน', 'ยังไม่ได้รับเงิน'],
    story: 'ป้าจันทร์มารับทรายก่อ/เท 2 เที่ยว เที่ยวละ 3 คิว บอกว่าจะโอนให้ตอนเย็น ตอนนี้ยังไม่ได้รับเงิน',
    source: 'pit',
    customer: { name: 'ทดสอบ03 ป้าจันทร์ แสงดี', phone: '0990000103', address: '8 ม.1 ต.ทุ่งฮั้ว' },
    items: [{ product: 'mortar-sand', perTrip: 3, trips: 2 }],
    payment: 'transfer',
    paidNow: false,
    tryFirst: ['ขั้นสรุป: เลือก "โอนเงิน" แล้ว เอาติ๊ก "ได้รับเงินแล้ว" ออก'],
    expectBehaviour: ['บิลต้องยังค้างรับเต็มจำนวน และในสรุปบิลขึ้น "รอรับเงิน"'],
  },
  {
    title: 'ร้านวัสดุสั่งส่ง ตำบลที่ค่าส่ง 0 บาท',
    level: 'พื้นฐาน',
    topics: ['ร้านวัสดุ', 'จัดส่ง', 'รถ 5 คิว', 'เงินสด'],
    story:
      'ร้านวัสดุโทรมาสั่งทรายถม 5 คิว ให้ส่งที่หน้างานลูกค้าในตำบลวังเหนือ 1 เที่ยว ร้านจ่ายเงินสดมาแล้ว ให้อ้ายโกไปส่ง',
    source: 'shop',
    customer: { name: 'ทดสอบ04 ร้านรุ่งเรืองวัสดุ', phone: '0990000104', address: '99 ถ.พหลโยธิน ต.วังเหนือ' },
    items: [{ product: 'fill-sand', perTrip: 5, trips: 1 }],
    delivery: { zone: 'wang-nuea', address: 'บ้านนายสมพร ม.5 ข้างวัด', driver: 'อ้ายโก' },
    payment: 'cash',
    expectBehaviour: ['ค่าส่งเก็บลูกค้า = 0 แต่ค่ารถคนขับไม่เป็น 0 → ในสรุปบิล "คงเหลือเข้าร้าน" ต้องน้อยกว่ายอดบิล'],
  },
  {
    title: 'จัดส่ง 2 เที่ยว ตำบลมีค่าส่ง เก็บเงินปลายทาง',
    level: 'พื้นฐาน',
    topics: ['จัดส่ง', 'ค่าส่งต่อคิว', 'หลายเที่ยว', 'จ่ายปลายทาง'],
    story: 'คุณวิชัยสั่งหินเล็กคละ 10 คิว (2 เที่ยว เที่ยวละ 5 คิว) ส่งตำบลวังใต้ จ่ายเงินสดกับคนขับตอนของถึง ให้สมศักดิ์ไปส่ง',
    source: 'pit',
    customer: { name: 'ทดสอบ05 คุณวิชัย มั่นคง', phone: '0990000105', address: '21 ม.2 ต.วังใต้' },
    items: [{ product: 'small-stone', perTrip: 5, trips: 2 }],
    delivery: { zone: 'wang-tai', address: 'ไร่คุณวิชัย ทางเข้าโรงเรียน', driver: 'สมศักดิ์' },
    payment: 'cod',
    expectBehaviour: ['หลังบันทึก ต้องมีหน้าต่างให้เลือก "คัดลอกข้อความส่งคนขับ" หรือ "ออกบิล"'],
  },
  {
    title: 'รถเล็ก 3 คิว',
    level: 'พื้นฐาน',
    topics: ['จัดส่ง', 'รถ 3 คิว', 'เงินสด'],
    story: 'น้องฝนสั่งทรายก่อ/เท 3 คิว ส่งตำบลทุ่งฮั้ว 1 เที่ยว ทางเข้าบ้านแคบ ต้องใช้รถเล็ก ให้แซมไปส่ง จ่ายเงินสดแล้ว',
    source: 'pit',
    customer: { name: 'ทดสอบ06 น้องฝน', phone: '0990000106', address: '5 ม.9 ต.ทุ่งฮั้ว' },
    items: [{ product: 'mortar-sand', perTrip: 3, trips: 1 }],
    delivery: { zone: 'thung-hua', address: 'ซอยข้างร้านค้าสหกรณ์ บ้านหลังที่ 3', driver: 'แซม' },
    payment: 'cash',
  },
  {
    title: 'ของ 3 คิว แต่ใช้รถ 5 คิว',
    level: 'ปานกลาง',
    topics: ['ร้านวัสดุ', 'ขนาดรถ', 'ค่ารถคนขับ'],
    story:
      'ร้านวัสดุสั่งทรายถม 3 คิว ส่งตำบลวังแก้ว รถเล็กไม่ว่าง ต้องให้อ้ายเบล (รถ 5 คิว) ไปส่ง ร้านโอนเงินมาแล้ว',
    source: 'shop',
    customer: { name: 'ทดสอบ07 ร้านมั่นคงการช่าง', phone: '0990000107', address: '3 ม.4 ต.วังแก้ว' },
    items: [{ product: 'fill-sand', perTrip: 3, trips: 1 }],
    delivery: { zone: 'wang-kaeo', address: 'หน้างานสร้างบ้าน ม.4 ตรงข้ามศาลา', driver: 'อ้ายเบล' },
    payment: 'transfer',
    expectBehaviour: ['เมื่อเลือกอ้ายเบล ขนาดรถต้องเปลี่ยนเป็น 5 คิว และค่ารถคิดตามอัตรารถ 5 คิว (ไม่ใช่รถ 3 คิว)'],
  },
  {
    title: 'งานใหญ่ 3 เที่ยว เครดิตรายเดือน',
    level: 'ปานกลาง',
    topics: ['จัดส่ง', 'เครดิต', 'ตำบลไกล'],
    story:
      'ผู้รับเหมาสมชาย สั่งหินคละใหญ่ 15 คิว (3 เที่ยว เที่ยวละ 5 คิว) ส่งตำบลวังทอง ขอเครดิตรวมจ่ายสิ้นเดือน ให้โอเว่นไปส่ง',
    source: 'pit',
    customer: { name: 'ทดสอบ08 ผรม.สมชาย ก่อสร้าง', phone: '0990000108', address: '77 ม.6 ต.วังทอง' },
    items: [{ product: 'big-stone', perTrip: 5, trips: 3 }],
    delivery: { zone: 'wang-thong', address: 'โครงการถนน ม.6 จุดกองวัสดุ', driver: 'โอเว่น' },
    payment: 'credit',
  },
  {
    title: 'สินค้า 2 อย่าง รถเล็ก 2 เที่ยว',
    level: 'ปานกลาง',
    topics: ['ร้านวัสดุ', 'หลายสินค้า', 'รถ 3 คิว'],
    story:
      'ร้านวัสดุสั่งทรายถม 3 คิว และหินเล็กคละ 3 คิว (อย่างละ 1 เที่ยว) ส่งตำบลวังซ้าย ใช้หลวงพูน (รถ 3 คิว) โอนเงินมาแล้ว',
    source: 'shop',
    customer: { name: 'ทดสอบ09 ร้านเจริญพาณิชย์', phone: '0990000109', address: '10 ม.2 ต.วังซ้าย' },
    items: [
      { product: 'fill-sand', perTrip: 3, trips: 1 },
      { product: 'small-stone', perTrip: 3, trips: 1 },
    ],
    delivery: { zone: 'wang-sai', address: 'บ้านลูกค้าร้าน ม.2 หลังตลาด', driver: 'หลวงพูน' },
    payment: 'transfer',
  },
  {
    title: 'คิวต่อเที่ยวไม่เต็ม (2.5 คิว)',
    level: 'ปานกลาง',
    topics: ['คิวต่อเที่ยว "อื่นๆ"', 'จ่ายปลายทาง'],
    story:
      'ลุงประเสริฐสั่งทรายก่อ/เท 5 คิว แต่ทางเข้าบ้านเป็นสะพานไม้ ต้องแบ่งส่ง 2 เที่ยว เที่ยวละ 2.5 คิว ส่งตำบลร่องเคาะ ให้อินจันส่ง เก็บเงินปลายทาง',
    source: 'pit',
    customer: { name: 'ทดสอบ10 ลุงประเสริฐ', phone: '0990000110', address: '4 ม.8 ต.ร่องเคาะ' },
    items: [{ product: 'mortar-sand', perTrip: 2.5, trips: 2 }],
    delivery: { zone: 'rong-kho', address: 'บ้านริมห้วย ข้ามสะพานไม้', driver: 'อินจัน' },
    payment: 'cod',
    tryFirst: ['ขั้นสินค้า: กด "อื่นๆ" แล้วพิมพ์ 2.5 คิว/เที่ยว จำนวน 2 เที่ยว'],
    expectBehaviour: ['รวมต้องได้ 5 คิว 2 เที่ยว ระบบแนะนำรถ 3 คิว'],
  },
  {
    title: 'ส่วนลดต่อคิว',
    level: 'ปานกลาง',
    topics: ['ส่วนลดคิวละ', 'จัดส่ง', 'เงินสด'],
    story:
      'ลูกค้าประจำ คุณสุดา สั่งหินเล็กคละ 10 คิว (2 เที่ยว เที่ยวละ 5) ส่งตำบลวังทรายคำ ขอลดคิวละ 30 บาท ให้พ่อเลี้ยงตุ๋ยส่ง จ่ายเงินสดแล้ว',
    source: 'pit',
    customer: { name: 'ทดสอบ11 คุณสุดา รักษ์ดี', phone: '0990000111', address: '18 ม.3 ต.วังทรายคำ' },
    items: [{ product: 'small-stone', perTrip: 5, trips: 2, unitDiscount: 30 }],
    delivery: { zone: 'wang-sai-kham', address: 'บ้านคุณสุดา ประตูสีเขียว', driver: 'พ่อเลี้ยงตุ๋ย' },
    payment: 'cash',
  },
  {
    title: 'ส่วนลดท้ายบิล 5% มารับเอง เครดิต',
    level: 'ปานกลาง',
    topics: ['ร้านวัสดุ', 'ส่วนลด %', 'มารับเอง', 'เครดิต'],
    story:
      'ร้านวัสดุส่งรถมารับเอง: ทรายถม 10 คิว (2 เที่ยว เที่ยวละ 5) และหินคละใหญ่ 5 คิว (1 เที่ยว) ขอส่วนลดท้ายบิล 5% และขอเครดิตรายเดือน',
    source: 'shop',
    customer: { name: 'ทดสอบ12 ร้านทองดีวัสดุ', phone: '0990000112', address: '55 ม.1 ต.วังเหนือ' },
    items: [
      { product: 'fill-sand', perTrip: 5, trips: 2 },
      { product: 'big-stone', perTrip: 5, trips: 1 },
    ],
    billDiscount: { type: 'percent', value: 5 },
    payment: 'credit',
  },
  {
    title: 'ส่วนลด % ต้องไม่ลดค่าส่ง',
    level: 'ปานกลาง',
    topics: ['ส่วนลด %', 'จัดส่ง', 'โอนเงิน'],
    story:
      'คุณมาลีสั่งทรายก่อ/เท 5 คิว ส่งตำบลวังใต้ 1 เที่ยว ขอลด 10% ให้อาวชาติไปส่ง โอนเงินมาแล้ว',
    source: 'pit',
    customer: { name: 'ทดสอบ13 คุณมาลี ศรีสุข', phone: '0990000113', address: '30 ม.5 ต.วังใต้' },
    items: [{ product: 'mortar-sand', perTrip: 5, trips: 1 }],
    delivery: { zone: 'wang-tai', address: 'บ้านคุณมาลี ใกล้ อบต.', driver: 'อาวชาติ' },
    billDiscount: { type: 'percent', value: 10 },
    payment: 'transfer',
    expectBehaviour: ['ส่วนลด 10% ต้องคิดจากค่าสินค้าเท่านั้น ไม่รวมค่าส่ง'],
  },
  {
    title: 'ส่วนลดท้ายบิลเป็นบาท (ปัดเศษ)',
    level: 'ปานกลาง',
    topics: ['ร้านวัสดุ', 'ส่วนลดบาท', 'หลายสินค้า', 'จ่ายปลายทาง'],
    story:
      'ร้านวัสดุสั่งทรายถม 5 คิว และหินเล็กคละ 5 คิว (อย่างละ 1 เที่ยว) ส่งตำบลวังเหนือ ขอปัดเศษลด 50 บาท ให้เทวาส่ง เก็บเงินปลายทาง',
    source: 'shop',
    customer: { name: 'ทดสอบ14 ร้านสมบูรณ์ค้าวัสดุ', phone: '0990000114', address: '1 ม.10 ต.วังเหนือ' },
    items: [
      { product: 'fill-sand', perTrip: 5, trips: 1 },
      { product: 'small-stone', perTrip: 5, trips: 1 },
    ],
    delivery: { zone: 'wang-nuea', address: 'หน้างานลูกค้าร้าน ม.10 ซอยโรงสี', driver: 'เทวา' },
    billDiscount: { type: 'baht', value: 50 },
    payment: 'cod',
  },
  {
    title: 'ลดค่าส่งบางส่วน',
    level: 'ปานกลาง',
    topics: ['ลดค่าส่ง', 'จัดส่ง', 'เงินสด'],
    story:
      'คุณอนันต์สั่งทรายถม 10 คิว (2 เที่ยว เที่ยวละ 5) ส่งตำบลวังทอง ขอลดค่าส่ง 200 บาท ให้โอ็ตไปส่ง จ่ายเงินสดแล้ว',
    source: 'pit',
    customer: { name: 'ทดสอบ15 คุณอนันต์ ใจกว้าง', phone: '0990000115', address: '66 ม.2 ต.วังทอง' },
    items: [{ product: 'fill-sand', perTrip: 5, trips: 2 }],
    delivery: { zone: 'wang-thong', address: 'ที่ดินเปล่าคุณอนันต์ ติดถนนดำ', driver: 'โอ็ต', deliveryDiscount: 200 },
    payment: 'cash',
  },
  {
    title: 'พิมพ์ลดค่าส่งเกินค่าส่ง',
    level: 'ท้าทาย',
    topics: ['ลดค่าส่ง', 'ตรวจขอบเขต', 'เครดิต'],
    story:
      'คุณนิดสั่งหินเล็กคละ 3 คิว ส่งตำบลวังทรายคำ 1 เที่ยว ให้ลุงช่วยส่ง ขอเครดิต พนักงานเผลอพิมพ์ลดค่าส่ง 500 บาท',
    source: 'pit',
    customer: { name: 'ทดสอบ16 คุณนิด', phone: '0990000116', address: '9 ม.7 ต.วังทรายคำ' },
    items: [{ product: 'small-stone', perTrip: 3, trips: 1 }],
    delivery: { zone: 'wang-sai-kham', address: 'บ้านคุณนิด ท้ายหมู่บ้าน', driver: 'ลุงช่วย', deliveryDiscount: 500 },
    payment: 'credit',
    tryFirst: ['ขั้นสรุป: พิมพ์ "ลดค่าส่ง" 500'],
    expectBehaviour: ['ระบบต้องตัดส่วนลดค่าส่งให้ไม่เกินค่าส่งจริง (ค่าส่งเหลือ 0) และไม่ไปลดค่าสินค้า'],
  },
  {
    title: 'ที่กันดาร บวกค่าส่งเพิ่ม',
    level: 'ท้าทาย',
    topics: ['ร้านวัสดุ', 'ที่กันดาร', 'โอนเงิน'],
    story:
      'ร้านวัสดุสั่งทรายถม 5 คิว ส่งตำบลร่องเคาะ ทางขึ้นดอย ต้องบวกค่าที่กันดาร 300 บาท ให้สมศักดิ์ไปส่ง ร้านโอนเงินมาแล้ว',
    source: 'shop',
    customer: { name: 'ทดสอบ17 ร้านดอยงามวัสดุ', phone: '0990000117', address: '2 ม.11 ต.ร่องเคาะ' },
    items: [{ product: 'fill-sand', perTrip: 5, trips: 1 }],
    delivery: { zone: 'rong-kho', address: 'บ้านบนดอย ม.11 ทางลูกรัง', driver: 'สมศักดิ์', remote: 300 },
    payment: 'transfer',
    expectBehaviour: ['ค่าที่กันดารบวกเข้าค่าส่งของลูกค้า แต่ไม่บวกเข้าค่ารถคนขับ'],
  },
  {
    title: 'ลืมเลือกคนขับ',
    level: 'ท้าทาย',
    topics: ['ตรวจการบังคับกรอก', 'คนขับ', 'จ่ายปลายทาง'],
    story:
      'คุณเอกสั่งทรายก่อ/เท 3 คิว ส่งตำบลวังแก้ว 1 เที่ยว เก็บเงินปลายทาง ให้หลวงพูนส่ง ลองกด "ถัดไป" ก่อนเลือกคนขับดูก่อน',
    source: 'pit',
    customer: { name: 'ทดสอบ18 คุณเอก', phone: '0990000118', address: '14 ม.3 ต.วังแก้ว' },
    items: [{ product: 'mortar-sand', perTrip: 3, trips: 1 }],
    delivery: { zone: 'wang-kaeo', address: 'บ้านคุณเอก หน้าโรงเรียน', driver: 'หลวงพูน' },
    payment: 'cod',
    tryFirst: [
      'ขั้นการรับสินค้า: ใส่ที่อยู่และตำบลแล้วกด "ถัดไป" โดยยังไม่เลือกคนขับ',
      'เลือกหลวงพูนแล้วกด "ถัดไป" โดยยังไม่ติ๊กยืนยันรถเข้าหน้างานได้',
    ],
    expectBehaviour: [
      'ครั้งแรกต้องขึ้น "เลือกคนขับ" และไปต่อไม่ได้',
      'ครั้งที่สองต้องขึ้น "ยืนยันว่ารถเข้าหน้างานได้และมีคิวว่าง"',
    ],
  },
  {
    title: 'ของเที่ยวละ 5 คิว เลือกรถ 3 คิวไม่ได้',
    level: 'ท้าทาย',
    topics: ['ร้านวัสดุ', 'ขนาดรถ', 'ตรวจขอบเขต', 'เครดิต'],
    story:
      'ร้านวัสดุสั่งหินคละใหญ่ 5 คิว ส่งตำบลทุ่งฮั้ว 1 เที่ยว ขอเครดิต ลองเลือกอินจัน (รถ 3 คิว) ก่อน แล้วค่อยเปลี่ยนเป็นอ้ายเบล',
    source: 'shop',
    customer: { name: 'ทดสอบ19 ร้านทุ่งทองวัสดุ', phone: '0990000119', address: '6 ม.6 ต.ทุ่งฮั้ว' },
    items: [{ product: 'big-stone', perTrip: 5, trips: 1 }],
    delivery: { zone: 'thung-hua', address: 'หน้างานบ้านลูกค้าร้าน ม.6', driver: 'อ้ายเบล' },
    payment: 'credit',
    tryFirst: ['ขั้นการรับสินค้า: ลองกดเลือกอินจัน (รถ 3 คิว)'],
    expectBehaviour: ['อินจันต้องกดไม่ได้ และขึ้น "รถเล็กเกิน (สินค้าเที่ยวละ 5 คิว)"'],
  },
  {
    title: 'บิลใหญ่ รวมทุกอย่าง',
    level: 'ท้าทาย',
    topics: ['หลายสินค้า', 'ส่วนลดคิวละ', 'ส่วนลดบาท', 'เครดิต'],
    story:
      'ผู้รับเหมาใหญ่สั่ง: ทรายถม 10 คิว (2 เที่ยว เที่ยวละ 5) ลดคิวละ 20, หินเล็กคละ 5 คิว (1 เที่ยว), ทรายก่อ/เท 3 คิว (1 เที่ยว) ส่งตำบลวังใต้ ขอลดท้ายบิลอีก 500 บาท เครดิตรายเดือน ให้โอเว่นส่ง',
    source: 'pit',
    customer: { name: 'ทดสอบ20 หจก.ทดสอบรุ่งโรจน์', phone: '0990000120', address: '100 ม.1 ต.วังใต้' },
    items: [
      { product: 'fill-sand', perTrip: 5, trips: 2, unitDiscount: 20 },
      { product: 'small-stone', perTrip: 5, trips: 1 },
      { product: 'mortar-sand', perTrip: 3, trips: 1 },
    ],
    delivery: { zone: 'wang-tai', address: 'โครงการบ้านจัดสรร ม.1 แปลง A', driver: 'โอเว่น' },
    billDiscount: { type: 'baht', value: 500 },
    payment: 'credit',
  },
];
