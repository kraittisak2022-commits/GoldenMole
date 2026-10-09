import { STEPS as WIZARD_STEPS } from '../pages/new-order/wizardState';

/** State of the order detail page currently on screen (read from its data-* attributes). */
export interface OrderDom {
  id: string;
  payment: string;
  delivery: string;
  cancelled: boolean;
  cleared: boolean;
}

export interface TourVars {
  customerId?: string;
  orderId?: string;
  creditOrderId?: string;
  statementId?: string;
}

export interface TourEnv {
  path: string;
  has: (selector: string) => boolean;
  wizardStep: string | null;
  order: OrderDom | null;
  vars: TourVars;
}

export type TourAction = 'createCredit' | 'finish';

export interface TourStep {
  chapter: number;
  title: string;
  body: string;
  /** CSS selector of the element to spotlight. */
  target?: string;
  /** Pages (pathname) where this step's target lives. */
  on?: RegExp;
  /** Where to go when the step is entered from elsewhere or resumed. */
  route?: (v: TourVars) => string | null;
  /** The user did what the step asks: move on automatically. */
  done?: (env: TourEnv) => boolean;
  capture?: (env: TourEnv) => Partial<TourVars>;
  /** Step does not apply (e.g. delivery steps on a pickup order). */
  skip?: (env: TourEnv) => boolean;
  place?: 'top' | 'bottom';
  action?: TourAction;
  actionLabel?: string;
  /** Later steps depend on it, so it cannot be skipped. */
  required?: boolean;
}

export const CHAPTERS = [
  'ภาพรวม',
  'สร้างออเดอร์',
  'บิลและการจัดส่ง',
  'รับเงิน',
  'แก้ไข / ยกเลิก',
  'ออเดอร์เครดิต',
  'วางบิล',
  'เคลียร์บิล',
  'จบการสอน',
] as const;

const dt = (name: string) => `[data-tour="${name}"]`;

const HOME = /^\/$/;
const WIZARD = /^\/new$/;
const ORDER_PAGE = /^\/orders\/[^/]+$/;
const ORDER_BILL = /^\/bill\/order\/[^/]+$/;
const STATEMENT_BILL = /^\/bill\/statement\/[^/]+$/;
const STATEMENTS = /^\/statements$/;

const idFrom = (path: string, re: RegExp) => re.exec(path)?.[1];

function wizardPast(env: TourEnv, key: (typeof WIZARD_STEPS)[number]['key']): boolean {
  const current = WIZARD_STEPS.findIndex((s) => s.key === env.wizardStep);
  return current > WIZARD_STEPS.findIndex((s) => s.key === key);
}

const orderRoute = (v: TourVars) => (v.orderId ? `/orders/${v.orderId}` : null);
const creditRoute = (v: TourVars) => (v.creditOrderId ? `/orders/${v.creditOrderId}` : null);
const onOrder = (env: TourEnv) => (env.order?.id === env.vars.orderId ? env.order : null);
const isPickup = (env: TourEnv) => onOrder(env)?.delivery === 'pickup';

export const TOUR_STEPS: TourStep[] = [
  {
    chapter: 0,
    title: 'ยินดีต้อนรับสู่โหมดสอนใช้งาน',
    body:
      'เราจะพาทำจริงทีละขั้น ตั้งแต่สร้างออเดอร์ ออกบิล รับเงิน จนถึงวางบิลและเคลียร์บิล\n\nทุกอย่างที่สร้างในโหมดนี้มีป้าย "สาธิต" เลขเอกสารขึ้นต้นด้วย DEMO- คนอื่นมองไม่เห็น และจะถูกลบทิ้งเมื่อจบการสอน',
    route: () => '/',
  },
  {
    chapter: 0,
    title: 'ตัวเลขของวัน',
    body: 'แถวนี้สรุปวันที่เลือก: จำนวนออเดอร์ ปริมาณสินค้า เงินที่รับแล้ว และยอดที่ยังค้างรับ เลื่อนดูวันอื่นได้จากแถบวันที่ด้านบน',
    target: dt('dash-kpis'),
    on: HOME,
    route: () => '/',
  },
  {
    chapter: 0,
    title: 'งานค้าง',
    body: 'ออเดอร์ที่ยังไม่ได้ส่ง ยังไม่จ่าย และยอดเครดิตที่ยังไม่เคลียร์ แตะการ์ดเพื่อดูรายการได้ทันที',
    target: dt('dash-pending'),
    on: HOME,
    route: () => '/',
  },
  {
    chapter: 0,
    title: 'เมนูหลัก',
    body: 'สลับไปหน้าออเดอร์ ลูกค้า เคลียร์บิล และเมนูอื่น ๆ ได้จากตรงนี้',
    target: dt('main-nav'),
    on: HOME,
    route: () => '/',
  },
  {
    chapter: 0,
    title: 'เริ่มสร้างออเดอร์',
    body: 'กดปุ่ม "สร้างออเดอร์" (ปุ่ม + ) ที่ไฮไลต์ไว้',
    target: dt('new-order'),
    on: HOME,
    route: () => '/',
    done: (e) => WIZARD.test(e.path),
    required: true,
  },

  {
    chapter: 1,
    title: 'ขั้นตอนการสร้างออเดอร์',
    body: 'การสร้างออเดอร์มี 6 ขั้น แถบนี้บอกว่าอยู่ขั้นไหน แตะชื่อขั้นที่ทำไปแล้วเพื่อย้อนกลับไปแก้ได้',
    target: dt('wiz-progress'),
    on: WIZARD,
    route: () => '/new',
    place: 'bottom',
  },
  {
    chapter: 1,
    title: 'ประเภทออเดอร์',
    body: 'เลือกวันที่ แล้วเลือกว่าเป็นออเดอร์ของร้านวัสดุก่อสร้าง หรือสั่งที่ท่าทรายโดยตรง เลือกแล้วระบบไปขั้นถัดไปให้เอง (บัญชีที่สร้างได้ประเภทเดียว เลือกแค่วันที่แล้วกด "ถัดไป")',
    target: dt('wiz-source'),
    on: WIZARD,
    route: () => '/new',
    done: (e) => wizardPast(e, 'source'),
    place: 'top',
  },
  {
    chapter: 1,
    title: 'เลือกสินค้า',
    body: 'แตะหมวด หิน หรือ ทราย → เลือกคิวต่อเที่ยว → ใส่จำนวนเที่ยว\nจากนั้นกด "ถัดไป" ด้านล่าง',
    target: dt('wiz-products'),
    on: WIZARD,
    route: () => '/new',
    done: (e) => wizardPast(e, 'products'),
    place: 'top',
  },
  {
    chapter: 1,
    title: 'เลือกลูกค้า',
    body: 'พิมพ์ "ลูกค้าตัวอย่าง" แล้วแตะเลือก (ลูกค้านี้สร้างไว้ให้สำหรับการสอน)\nของจริงค้นได้จากชื่อ ชื่อเรียก หรือเบอร์โทร หรือกด "เพิ่มลูกค้าใหม่"',
    target: dt('wiz-customer-search'),
    on: WIZARD,
    route: () => '/new',
    done: (e) => wizardPast(e, 'customer'),
    place: 'bottom',
  },
  {
    chapter: 1,
    title: 'การรับสินค้า',
    body: 'แนะนำให้เลือก "ให้รถไปส่ง" เพื่อดูขั้นตอนจัดส่ง แล้วเลือกตำบล ขนาดรถ และคนขับ\nระบบคำนวณค่าส่งให้ เสร็จแล้วกด "ถัดไป"',
    target: dt('wiz-fulfillment'),
    on: WIZARD,
    route: () => '/new',
    done: (e) => wizardPast(e, 'fulfillment'),
    place: 'top',
  },
  {
    chapter: 1,
    title: 'สรุปยอดและส่วนลด',
    body: 'ตรวจราคาและยอดสุทธิ ใส่ส่วนลดได้ 3 แบบ: ลดต่อคิว ลดค่าส่ง และส่วนลดท้ายบิล (บาท หรือ %)',
    target: dt('wiz-totals'),
    on: WIZARD,
    route: () => '/new',
    place: 'top',
  },
  {
    chapter: 1,
    title: 'วิธีชำระเงิน',
    body: 'เลือก "เงินสด" และเอาติ๊ก "ได้รับเงินแล้ว" ออก เพื่อฝึกกดรับเงินทีหลัง\nถ้าลูกค้าจ่ายทันที ติ๊กไว้ได้เลย ระบบจะออกใบเสร็จให้ แล้วกด "ถัดไป"',
    target: dt('wiz-payment'),
    on: WIZARD,
    route: () => '/new',
    done: (e) => wizardPast(e, 'summary'),
    place: 'top',
  },
  {
    chapter: 1,
    title: 'ตรวจสอบก่อนออกบิล',
    body: 'ทวนข้อมูลทั้งหมดอีกครั้ง ถ้าผิดตรงไหนแตะ "แก้ไข" ข้างหัวข้อนั้นเพื่อกลับไปแก้',
    target: dt('wiz-confirm'),
    on: WIZARD,
    route: () => '/new',
    place: 'top',
  },
  {
    chapter: 1,
    title: 'ยืนยันและออกบิล',
    body: 'กด "ยืนยันและออกบิล" ระบบจะบันทึกออเดอร์และเปิดใบส่งของให้ทันที',
    target: dt('wiz-submit'),
    on: WIZARD,
    route: () => '/new',
    done: (e) => ORDER_BILL.test(e.path),
    capture: (e) => ({ orderId: idFrom(e.path, /^\/bill\/order\/([^/]+)$/) }),
    place: 'top',
    required: true,
  },

  {
    chapter: 2,
    title: 'ใบส่งของ',
    body: 'นี่คือบิลที่ระบบออกให้ ตัวจริงจะมีต้นฉบับกับสำเนาในกระดาษ A4 แผ่นเดียว\nลายน้ำ "ตัวอย่าง" มีเฉพาะในโหมดสาธิต',
    target: dt('bill-sheet'),
    on: ORDER_BILL,
    route: (v) => (v.orderId ? `/bill/order/${v.orderId}` : null),
    place: 'bottom',
  },
  {
    chapter: 2,
    title: 'ตัวเลือกการพิมพ์',
    body: 'สลับประเภทเอกสาร (ใบส่งของ / ใบเสร็จ) และเลือกพิมพ์ต้นฉบับ + สำเนา หรือต้นฉบับอย่างเดียว',
    target: dt('bill-options'),
    on: ORDER_BILL,
    route: (v) => (v.orderId ? `/bill/order/${v.orderId}` : null),
    place: 'bottom',
  },
  {
    chapter: 2,
    title: 'พิมพ์หรือส่งรูป',
    body: 'กด "พิมพ์" เพื่อพิมพ์ หรือ "บันทึกรูป" เพื่อส่งบิลให้ลูกค้าทาง LINE (ในการสอนไม่ต้องกดก็ได้)',
    target: dt('bill-print'),
    on: ORDER_BILL,
    route: (v) => (v.orderId ? `/bill/order/${v.orderId}` : null),
    place: 'bottom',
  },
  {
    chapter: 2,
    title: 'ไปหน้ารายละเอียดออเดอร์',
    body: 'กดลูกศรกลับด้านซ้ายบน เพื่อไปหน้ารายละเอียดของออเดอร์นี้',
    target: dt('bill-back'),
    on: ORDER_BILL,
    route: (v) => (v.orderId ? `/bill/order/${v.orderId}` : null),
    done: (e) => !!onOrder(e),
    place: 'bottom',
    required: true,
  },
  {
    chapter: 2,
    title: 'สถานะของออเดอร์',
    body: 'ทุกออเดอร์ติดตาม 3 เรื่อง: การชำระเงิน การจัดส่ง และการเคลียร์บิล\nป้ายสีบอกสถานะ ณ ตอนนี้',
    target: dt('status-card'),
    on: ORDER_PAGE,
    route: orderRoute,
  },
  {
    chapter: 2,
    title: 'ส่งงานให้คนขับ',
    body: 'กด "คัดลอกข้อความ" แล้ววางใน LINE ส่งคนขับ ข้อความมีสินค้า ที่อยู่ และลิงก์แผนที่ครบ',
    target: dt('copy-driver'),
    on: ORDER_PAGE,
    route: orderRoute,
    skip: isPickup,
  },
  {
    chapter: 2,
    title: 'อัปเดตการจัดส่ง',
    body: 'เมื่อรถออกให้กด "กำลังส่ง" และเมื่อส่งถึงให้กด "ส่งแล้ว"\nลองกดจนถึง "ส่งแล้ว"',
    target: dt('delivery-steps'),
    on: ORDER_PAGE,
    route: orderRoute,
    done: (e) => onOrder(e)?.delivery === 'delivered',
    skip: isPickup,
  },

  {
    chapter: 3,
    title: 'รับเงิน',
    body: 'เมื่อลูกค้าจ่าย กด "รับเงินสด" หรือ "รับโอนแล้ว" ตามจริง\nลองกด "รับเงินสด"',
    target: dt('pay-buttons'),
    on: ORDER_PAGE,
    route: orderRoute,
    done: (e) => onOrder(e)?.payment === 'paid',
  },
  {
    chapter: 3,
    title: 'ใบเสร็จออกให้อัตโนมัติ',
    body: 'รับเงินแล้วระบบออกเลขใบเสร็จให้ทันที กด "ดู / พิมพ์บิล" เพื่อดูใบเสร็จ',
    target: dt('bill-link'),
    on: ORDER_PAGE,
    route: orderRoute,
    done: (e) => ORDER_BILL.test(e.path),
  },
  {
    chapter: 3,
    title: 'ใบเสร็จรับเงิน',
    body: 'ตอนนี้บิลเปิดเป็น "ใบเสร็จรับเงิน" ให้อัตโนมัติ สลับกลับไปดูใบส่งของได้จากตัวเลือกด้านบน',
    target: dt('bill-options'),
    on: ORDER_BILL,
    route: (v) => (v.orderId ? `/bill/order/${v.orderId}` : null),
    place: 'bottom',
  },
  {
    chapter: 3,
    title: 'กลับหน้าออเดอร์',
    body: 'กดลูกศรกลับ เพื่อไปฝึกแก้ไขและยกเลิกออเดอร์',
    target: dt('bill-back'),
    on: ORDER_BILL,
    route: (v) => (v.orderId ? `/bill/order/${v.orderId}` : null),
    done: (e) => !!onOrder(e),
    place: 'bottom',
    required: true,
  },

  {
    chapter: 4,
    title: 'แก้ไขออเดอร์',
    body: 'ถ้าลงข้อมูลผิด กด "แก้ไขออเดอร์" เพื่อแก้สินค้า จำนวน ราคา หรือส่วนลด',
    target: dt('edit-order'),
    on: ORDER_PAGE,
    route: orderRoute,
    done: (e) => e.has('[role="dialog"]'),
  },
  {
    chapter: 4,
    title: 'ลองแก้แล้วบันทึก',
    body: 'ลองเปลี่ยนจำนวนหรือส่วนลด แล้วกดบันทึก ยอดและบิลจะอัปเดตตาม (หรือกดปิดถ้าไม่ต้องการแก้)',
    target: '[role="dialog"] .modal-panel',
    on: ORDER_PAGE,
    route: orderRoute,
    done: (e) => !e.has('[role="dialog"]'),
    place: 'top',
  },
  {
    chapter: 4,
    title: 'ยกเลิกออเดอร์',
    body: 'ถ้าลูกค้ายกเลิก กด "ยกเลิกออเดอร์" แล้วยืนยัน ออเดอร์จะไม่ถูกนับยอด และบิลขึ้นคำว่า VOID',
    target: dt('cancel-order'),
    on: ORDER_PAGE,
    route: orderRoute,
    done: (e) => !!onOrder(e)?.cancelled,
  },
  {
    chapter: 4,
    title: 'กู้คืนออเดอร์',
    body: 'ยกเลิกผิด กู้คืนได้เสมอ กด "กู้คืนออเดอร์" แล้วยืนยัน',
    target: dt('cancel-order'),
    on: ORDER_PAGE,
    route: orderRoute,
    done: (e) => onOrder(e)?.cancelled === false,
  },

  {
    chapter: 5,
    title: 'ลูกค้าเครดิต',
    body: 'ลูกค้าประจำซื้อก่อนจ่ายทีหลัง เลือกวิธีชำระ "เครดิต" ตอนสร้างออเดอร์ แล้วรวมยอดเป็นใบวางบิลรายเดือน\n\nกดปุ่มด้านล่าง ระบบจะสร้างออเดอร์เครดิตตัวอย่างให้ทันที',
    action: 'createCredit',
    actionLabel: 'สร้างออเดอร์เครดิตตัวอย่าง',
    required: true,
  },
  {
    chapter: 5,
    title: 'ออเดอร์เครดิต',
    body: 'สถานะการชำระเป็น "เครดิต" ไม่ต้องกดรับเงินทีละออเดอร์ ยอดจะไปเคลียร์รวมในใบวางบิล',
    target: dt('status-card'),
    on: ORDER_PAGE,
    route: creditRoute,
  },
  {
    chapter: 5,
    title: 'รวมเข้าใบวางบิล',
    body: 'กด "รวมเข้าใบวางบิลรายเดือน" เพื่อไปหน้าเคลียร์บิลของลูกค้ารายนี้',
    target: dt('to-statement'),
    on: ORDER_PAGE,
    route: creditRoute,
    done: (e) => STATEMENTS.test(e.path),
    required: true,
  },

  {
    chapter: 6,
    title: 'สร้างใบวางบิล',
    body: 'เลือกช่วงวันที่ แล้วติ๊กออเดอร์ที่จะรวมในใบวางบิล ระบบรวมยอดให้ด้านล่าง',
    target: dt('st-create'),
    on: STATEMENTS,
    route: (v) => (v.customerId ? `/statements?customer=${v.customerId}` : '/statements'),
  },
  {
    chapter: 6,
    title: 'ออกใบวางบิล',
    body: 'กด "สร้างใบวางบิลและพิมพ์" แล้วส่งใบวางบิลให้ลูกค้า',
    target: dt('st-create-submit'),
    on: STATEMENTS,
    route: (v) => (v.customerId ? `/statements?customer=${v.customerId}` : '/statements'),
    done: (e) => STATEMENT_BILL.test(e.path),
    capture: (e) => ({ statementId: idFrom(e.path, /^\/bill\/statement\/([^/]+)$/) }),
    required: true,
  },
  {
    chapter: 6,
    title: 'ใบวางบิล',
    body: 'ใบวางบิลรวมทุกออเดอร์ในช่วงที่เลือก พร้อมยอดรวม พิมพ์หรือบันทึกรูปส่งลูกค้าได้เหมือนบิลทั่วไป',
    target: dt('bill-sheet'),
    on: STATEMENT_BILL,
    route: (v) => (v.statementId ? `/bill/statement/${v.statementId}` : null),
    place: 'bottom',
  },
  {
    chapter: 6,
    title: 'กลับหน้าเคลียร์บิล',
    body: 'กดลูกศรกลับ เพื่อไปเคลียร์บิลเมื่อลูกค้าจ่ายเงิน',
    target: dt('bill-back'),
    on: STATEMENT_BILL,
    route: (v) => (v.statementId ? `/bill/statement/${v.statementId}` : null),
    done: (e) => STATEMENTS.test(e.path),
    place: 'bottom',
    required: true,
  },

  {
    chapter: 7,
    title: 'ใบวางบิลรอเคลียร์',
    body: 'ใบวางบิลที่ยังไม่ได้เก็บเงินอยู่ในรายการนี้ พร้อมยอดที่ต้องเก็บ',
    target: dt('st-demo-row'),
    on: STATEMENTS,
    route: () => '/statements',
  },
  {
    chapter: 7,
    title: 'เคลียร์บิล',
    body: 'เมื่อลูกค้าจ่ายเงิน กด "เคลียร์บิล" (ถ้าลูกค้าจ่ายไม่ครบ ก็บันทึกเป็นจ่ายบางส่วนได้)',
    target: dt('st-clear'),
    on: STATEMENTS,
    route: () => '/statements',
    done: (e) => e.has(dt('st-clear-modal')),
  },
  {
    chapter: 7,
    title: 'ยืนยันการรับเงิน',
    body: 'เลือก "จ่ายครบ" (หรือ "จ่ายบางส่วน" แล้วใส่ยอด) เลือกเงินสดหรือโอน แล้วกด "ยืนยันเคลียร์บิล"',
    target: dt('st-clear-modal'),
    on: STATEMENTS,
    route: () => '/statements',
    done: (e) => !e.has(dt('st-clear-modal')) && !e.has(dt('st-clear')),
    place: 'top',
  },
  {
    chapter: 7,
    title: 'ปิดออเดอร์ครบแล้ว',
    body: 'ทุกออเดอร์ในใบวางบิลเปลี่ยนเป็น "จ่ายแล้ว" และ "เคลียร์แล้ว" พร้อมเลขใบเสร็จอัตโนมัติ',
    target: dt('status-card'),
    on: ORDER_PAGE,
    route: creditRoute,
  },

  {
    chapter: 8,
    title: 'จบการสอนแล้ว',
    body: 'ตอนนี้คุณทำได้ครบทั้งวงจร: สร้างออเดอร์ → ออกบิล → ส่งของ → รับเงิน → แก้ไข/ยกเลิก → วางบิล → เคลียร์บิล\n\nกดปุ่มด้านล่างเพื่อลบข้อมูลสาธิตทั้งหมดและกลับไปใช้งานจริง',
    action: 'finish',
    actionLabel: 'ลบข้อมูลสาธิตและจบการสอน',
  },
];
