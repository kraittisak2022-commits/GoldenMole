import '../logic/wizard_state.dart';
import '../models/models.dart';

/// Screens the tour knows about; screens report themselves with a TourMarker.
enum TourPage { home, menu, wizard, orderBill, order, orderEdit, statements, statementCreate, statementBill }

class TourVars {
  const TourVars({this.customerId, this.orderId, this.creditOrderId, this.statementId});
  final String? customerId;
  final String? orderId;
  final String? creditOrderId;
  final String? statementId;

  TourVars merge(TourVars o) => TourVars(
    customerId: o.customerId ?? customerId,
    orderId: o.orderId ?? orderId,
    creditOrderId: o.creditOrderId ?? creditOrderId,
    statementId: o.statementId ?? statementId,
  );

  factory TourVars.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    String? s(String k) => m[k] is String ? m[k] as String : null;
    return TourVars(
      customerId: s('customerId'),
      orderId: s('orderId'),
      creditOrderId: s('creditOrderId'),
      statementId: s('statementId'),
    );
  }

  Map<String, dynamic> toJson() => {
    'customerId': ?customerId,
    'orderId': ?orderId,
    'creditOrderId': ?creditOrderId,
    'statementId': ?statementId,
  };
}

/// The order detail screen on display.
class TourOrder {
  const TourOrder({
    required this.id,
    required this.paid,
    required this.delivery,
    required this.pickup,
    required this.cancelled,
  });
  final String id;
  final bool paid;
  final DeliveryStatus delivery;
  final bool pickup;
  final bool cancelled;

  factory TourOrder.of(Order o) => TourOrder(
    id: o.id,
    paid: o.paymentStatus == PaymentStatus.paid,
    delivery: o.deliveryStatus,
    pickup: o.fulfillment == Fulfillment.pickup,
    cancelled: o.cancelled,
  );
}

class TourEnv {
  const TourEnv({
    required this.page,
    this.pageId,
    this.targets = const {},
    this.wizardStep,
    this.order,
    this.vars = const TourVars(),
  });
  final TourPage? page;
  final String? pageId;
  final Set<String> targets;
  final StepKey? wizardStep;
  final TourOrder? order;
  final TourVars vars;

  bool has(String target) => targets.contains(target);
}

/// Where a step lives, so the tour can take the user there.
class TourNav {
  const TourNav(this.page, [this.id]);
  final TourPage page;
  final String? id;
}

enum TourAction { createCredit, finish }

class TourStep {
  const TourStep({
    required this.chapter,
    required this.title,
    required this.body,
    this.target,
    this.on,
    this.route,
    this.done,
    this.capture,
    this.skip,
    this.placeTop,
    this.action,
    this.actionLabel,
    this.required = false,
  });
  final int chapter;
  final String title;
  final String body;

  /// Name of the TourTarget to spotlight.
  final String? target;

  /// Screens where [target] lives; null = anywhere.
  final Set<TourPage>? on;
  final TourNav? Function(TourVars v)? route;

  /// The user did what the step asks: move on automatically.
  final bool Function(TourEnv e)? done;
  final TourVars Function(TourEnv e)? capture;

  /// Step does not apply (e.g. delivery steps on a pickup order).
  final bool Function(TourEnv e)? skip;
  final bool? placeTop;
  final TourAction? action;
  final String? actionLabel;

  /// Later steps depend on it, so it cannot be skipped.
  final bool required;

  bool isOn(TourPage? page) => on == null || on!.contains(page);
}

const tourChapters = [
  'ภาพรวม',
  'สร้างออเดอร์',
  'บิลและการจัดส่ง',
  'รับเงิน',
  'แก้ไข / ยกเลิก',
  'ออเดอร์เครดิต',
  'วางบิล',
  'เคลียร์บิล',
  'จบการสอน',
];

const _home = {TourPage.home};
const _wizard = {TourPage.wizard};
const _orderPage = {TourPage.order};
const _orderBill = {TourPage.orderBill};
const _statementBill = {TourPage.statementBill};

TourNav _homeRoute(TourVars _) => const TourNav(TourPage.home);
TourNav _wizardRoute(TourVars _) => const TourNav(TourPage.wizard);
TourNav? _orderRoute(TourVars v) => v.orderId == null ? null : TourNav(TourPage.order, v.orderId);
TourNav? _creditRoute(TourVars v) => v.creditOrderId == null ? null : TourNav(TourPage.order, v.creditOrderId);
TourNav? _orderBillRoute(TourVars v) => v.orderId == null ? null : TourNav(TourPage.orderBill, v.orderId);
TourNav? _statementBillRoute(TourVars v) =>
    v.statementId == null ? null : TourNav(TourPage.statementBill, v.statementId);
TourNav _createStatementRoute(TourVars v) => TourNav(TourPage.statementCreate, v.customerId);
TourNav _statementsRoute(TourVars _) => const TourNav(TourPage.statements);

bool _wizardPast(TourEnv e, StepKey key) {
  final current = e.wizardStep;
  return e.page == TourPage.wizard && current != null && stepIndex(current) > stepIndex(key);
}

TourOrder? _onOrder(TourEnv e) =>
    e.page == TourPage.order && e.order != null && e.order!.id == e.vars.orderId ? e.order : null;

bool _isPickup(TourEnv e) => _onOrder(e)?.pickup ?? false;

final tourSteps = <TourStep>[
  const TourStep(
    chapter: 0,
    title: 'ยินดีต้อนรับสู่โหมดสอนใช้งาน',
    body:
        'เราจะพาทำจริงทีละขั้น ตั้งแต่สร้างออเดอร์ ออกบิล รับเงิน จนถึงวางบิลและเคลียร์บิล\n\n'
        'ทุกอย่างที่สร้างในโหมดนี้มีป้าย "ตัวอย่าง" เลขเอกสารขึ้นต้นด้วย DEMO- คนอื่นมองไม่เห็น และจะถูกลบทิ้งเมื่อจบการสอน',
    route: _homeRoute,
  ),
  const TourStep(
    chapter: 0,
    title: 'ตัวเลขของวัน',
    body:
        'แถวนี้สรุปวันที่เลือก: จำนวนออเดอร์ ปริมาณสินค้า เงินที่รับแล้ว และยอดที่ยังค้างรับ เลื่อนดูวันอื่นได้จากแถบวันที่ด้านบน',
    target: 'dash-kpis',
    on: _home,
    route: _homeRoute,
  ),
  const TourStep(
    chapter: 0,
    title: 'งานค้าง',
    body: 'ออเดอร์ที่ยังไม่ได้ส่ง ยังไม่จ่าย และยอดเครดิตที่ยังไม่เคลียร์ แตะการ์ดเพื่อดูรายการได้ทันที',
    target: 'dash-pending',
    on: _home,
    route: _homeRoute,
  ),
  const TourStep(
    chapter: 0,
    title: 'เมนูหลัก',
    body: 'สลับไปหน้าออเดอร์ ลูกค้า เคลียร์บิล และเมนูอื่น ๆ ได้จากตรงนี้',
    target: 'main-nav',
    on: _home,
    route: _homeRoute,
  ),
  TourStep(
    chapter: 0,
    title: 'เริ่มสร้างออเดอร์',
    body: 'กดปุ่ม "สร้างออเดอร์" (ปุ่ม + ) ที่ไฮไลต์ไว้',
    target: 'new-order',
    on: _home,
    route: _homeRoute,
    done: (e) => e.page == TourPage.wizard,
    required: true,
  ),
  const TourStep(
    chapter: 1,
    title: 'ขั้นตอนการสร้างออเดอร์',
    body: 'การสร้างออเดอร์มี 6 ขั้น แถบนี้บอกว่าอยู่ขั้นไหน แตะชื่อขั้นที่ทำไปแล้วเพื่อย้อนกลับไปแก้ได้',
    target: 'wiz-progress',
    on: _wizard,
    route: _wizardRoute,
    placeTop: false,
  ),
  TourStep(
    chapter: 1,
    title: 'ประเภทออเดอร์',
    body:
        'เลือกวันที่ แล้วเลือกว่าเป็นออเดอร์ของร้านวัสดุก่อสร้าง หรือสั่งที่ท่าทรายโดยตรง เลือกแล้วระบบไปขั้นถัดไปให้เอง',
    target: 'wiz-source',
    on: _wizard,
    route: _wizardRoute,
    done: (e) => _wizardPast(e, StepKey.source),
  ),
  TourStep(
    chapter: 1,
    title: 'เลือกสินค้า',
    body: 'แตะหมวด หิน หรือ ทราย → เลือกคิวต่อเที่ยว → ใส่จำนวนเที่ยว\nจากนั้นกด "ถัดไป" ด้านล่าง',
    target: 'wiz-products',
    on: _wizard,
    route: _wizardRoute,
    done: (e) => _wizardPast(e, StepKey.products),
  ),
  TourStep(
    chapter: 1,
    title: 'เลือกลูกค้า',
    body:
        'พิมพ์ "ลูกค้าตัวอย่าง" แล้วแตะเลือก (ลูกค้านี้สร้างไว้ให้สำหรับการสอน)\n'
        'ของจริงค้นได้จากชื่อ ชื่อเรียก หรือเบอร์โทร หรือกด "เพิ่มลูกค้าใหม่"',
    target: 'wiz-customer-search',
    on: _wizard,
    route: _wizardRoute,
    done: (e) => _wizardPast(e, StepKey.customer),
    placeTop: false,
  ),
  TourStep(
    chapter: 1,
    title: 'การรับสินค้า',
    body:
        'แนะนำให้เลือก "ให้รถไปส่ง" เพื่อดูขั้นตอนจัดส่ง แล้วเลือกตำบล ขนาดรถ และคนขับ\nระบบคำนวณค่าส่งให้ เสร็จแล้วกด "ถัดไป"',
    target: 'wiz-fulfillment',
    on: _wizard,
    route: _wizardRoute,
    done: (e) => _wizardPast(e, StepKey.fulfillment),
  ),
  const TourStep(
    chapter: 1,
    title: 'สรุปยอดและส่วนลด',
    body: 'ตรวจราคาและยอดสุทธิ ใส่ส่วนลดได้ 3 แบบ: ลดต่อคิว ลดค่าส่ง และส่วนลดท้ายบิล (บาท หรือ %)',
    target: 'wiz-totals',
    on: _wizard,
    route: _wizardRoute,
  ),
  TourStep(
    chapter: 1,
    title: 'วิธีชำระเงิน',
    body:
        'เลือก "เงินสด" และเอาติ๊ก "ได้รับเงินแล้ว" ออก เพื่อฝึกกดรับเงินทีหลัง\n'
        'ถ้าลูกค้าจ่ายทันที ติ๊กไว้ได้เลย ระบบจะออกใบเสร็จให้ แล้วกด "ถัดไป"',
    target: 'wiz-payment',
    on: _wizard,
    route: _wizardRoute,
    done: (e) => _wizardPast(e, StepKey.summary),
  ),
  const TourStep(
    chapter: 1,
    title: 'ตรวจสอบก่อนออกบิล',
    body: 'ทวนข้อมูลทั้งหมดอีกครั้ง ถ้าผิดตรงไหนแตะ "แก้ไข" ข้างหัวข้อนั้นเพื่อกลับไปแก้',
    target: 'wiz-confirm',
    on: _wizard,
    route: _wizardRoute,
  ),
  TourStep(
    chapter: 1,
    title: 'ยืนยันและออกบิล',
    body: 'กด "ยืนยันและออกบิล" ระบบจะบันทึกออเดอร์และเปิดใบส่งของให้ทันที',
    target: 'wiz-submit',
    on: _wizard,
    route: _wizardRoute,
    done: (e) => e.page == TourPage.orderBill,
    capture: (e) => TourVars(orderId: e.pageId),
    required: true,
  ),
  const TourStep(
    chapter: 2,
    title: 'ใบส่งของ',
    body:
        'นี่คือบิลที่ระบบออกให้ ตัวจริงมีต้นฉบับกับสำเนาในกระดาษ A4 แผ่นเดียว\nลายน้ำ "ตัวอย่าง" มีเฉพาะในโหมดสอนใช้งาน',
    target: 'bill-sheet',
    on: _orderBill,
    route: _orderBillRoute,
    placeTop: false,
  ),
  const TourStep(
    chapter: 2,
    title: 'ตัวเลือกการพิมพ์',
    body: 'สลับประเภทเอกสาร (ใบส่งของ / ใบเสร็จ) และเลือกพิมพ์ต้นฉบับ + สำเนา หรือต้นฉบับอย่างเดียว',
    target: 'bill-options',
    on: _orderBill,
    route: _orderBillRoute,
    placeTop: false,
  ),
  const TourStep(
    chapter: 2,
    title: 'พิมพ์หรือส่งรูป',
    body: 'กด "พิมพ์" เพื่อพิมพ์ หรือปุ่มรูปภาพ / PDF เพื่อส่งบิลให้ลูกค้าทาง LINE (ในการสอนไม่ต้องกดก็ได้)',
    target: 'bill-print',
    on: _orderBill,
    route: _orderBillRoute,
    placeTop: false,
  ),
  TourStep(
    chapter: 2,
    title: 'ไปหน้ารายละเอียดออเดอร์',
    body: 'กดลูกศรกลับด้านซ้ายบน เพื่อไปหน้ารายละเอียดของออเดอร์นี้',
    target: 'bill-back',
    on: _orderBill,
    route: _orderBillRoute,
    done: (e) => _onOrder(e) != null,
    placeTop: false,
    required: true,
  ),
  const TourStep(
    chapter: 2,
    title: 'สถานะของออเดอร์',
    body: 'ทุกออเดอร์ติดตาม 3 เรื่อง: การชำระเงิน การจัดส่ง และการเคลียร์บิล\nป้ายสีบอกสถานะ ณ ตอนนี้',
    target: 'status-card',
    on: _orderPage,
    route: _orderRoute,
  ),
  const TourStep(
    chapter: 2,
    title: 'ส่งงานให้คนขับ',
    body: 'กด "คัดลอกข้อความ" แล้ววางใน LINE ส่งคนขับ ข้อความมีสินค้า ที่อยู่ และลิงก์แผนที่ครบ',
    target: 'copy-driver',
    on: _orderPage,
    route: _orderRoute,
    skip: _isPickup,
  ),
  TourStep(
    chapter: 2,
    title: 'อัปเดตการจัดส่ง',
    body: 'เมื่อรถออกให้กด "กำลังส่ง" และเมื่อส่งถึงให้กด "ส่งแล้ว"\nลองกดจนถึง "ส่งแล้ว"',
    target: 'delivery-steps',
    on: _orderPage,
    route: _orderRoute,
    done: (e) => _onOrder(e)?.delivery == DeliveryStatus.delivered,
    skip: _isPickup,
  ),
  TourStep(
    chapter: 3,
    title: 'รับเงิน',
    body: 'เมื่อลูกค้าจ่าย กด "เงินสด" หรือ "โอนเงิน" ตามจริง\nลองกด "เงินสด"',
    target: 'pay-buttons',
    on: _orderPage,
    route: _orderRoute,
    done: (e) => _onOrder(e)?.paid ?? false,
  ),
  TourStep(
    chapter: 3,
    title: 'ใบเสร็จออกให้อัตโนมัติ',
    body: 'รับเงินแล้วระบบออกเลขใบเสร็จให้ทันที กด "ดู / พิมพ์บิล" เพื่อดูใบเสร็จ',
    target: 'bill-link',
    on: _orderPage,
    route: _orderRoute,
    done: (e) => e.page == TourPage.orderBill,
  ),
  const TourStep(
    chapter: 3,
    title: 'ใบเสร็จรับเงิน',
    body: 'ตอนนี้บิลเปิดเป็น "ใบเสร็จรับเงิน" ให้อัตโนมัติ สลับกลับไปดูใบส่งของได้จากตัวเลือกด้านบน',
    target: 'bill-options',
    on: _orderBill,
    route: _orderBillRoute,
    placeTop: false,
  ),
  TourStep(
    chapter: 3,
    title: 'กลับหน้าออเดอร์',
    body: 'กดลูกศรกลับ เพื่อไปฝึกแก้ไขและยกเลิกออเดอร์',
    target: 'bill-back',
    on: _orderBill,
    route: _orderBillRoute,
    done: (e) => _onOrder(e) != null,
    placeTop: false,
    required: true,
  ),
  TourStep(
    chapter: 4,
    title: 'แก้ไขออเดอร์',
    body: 'ถ้าลงข้อมูลผิด กดปุ่มแก้ไข (รูปดินสอ) เพื่อแก้สินค้า จำนวน ราคา หรือส่วนลด',
    target: 'edit-order',
    on: _orderPage,
    route: _orderRoute,
    done: (e) => e.page == TourPage.orderEdit,
    placeTop: false,
  ),
  TourStep(
    chapter: 4,
    title: 'ลองแก้แล้วบันทึก',
    body: 'ลองเปลี่ยนจำนวนหรือส่วนลด แล้วกดบันทึก ยอดและบิลจะอัปเดตตาม (หรือกดปิดถ้าไม่ต้องการแก้)',
    target: 'order-edit',
    on: const {TourPage.orderEdit},
    route: _orderRoute,
    done: (e) => e.page == TourPage.order,
  ),
  TourStep(
    chapter: 4,
    title: 'ยกเลิกออเดอร์',
    body: 'ถ้าลูกค้ายกเลิก กด "ยกเลิกออเดอร์" แล้วยืนยัน ออเดอร์จะไม่ถูกนับยอด และบิลขึ้นคำว่า VOID',
    target: 'cancel-order',
    on: _orderPage,
    route: _orderRoute,
    done: (e) => _onOrder(e)?.cancelled ?? false,
  ),
  TourStep(
    chapter: 4,
    title: 'กู้คืนออเดอร์',
    body: 'ยกเลิกผิด กู้คืนได้เสมอ กด "กู้คืนออเดอร์" แล้วยืนยัน',
    target: 'cancel-order',
    on: _orderPage,
    route: _orderRoute,
    done: (e) => _onOrder(e)?.cancelled == false,
  ),
  const TourStep(
    chapter: 5,
    title: 'ลูกค้าเครดิต',
    body:
        'ลูกค้าประจำซื้อก่อนจ่ายทีหลัง เลือกวิธีชำระ "เครดิต" ตอนสร้างออเดอร์ แล้วรวมยอดเป็นใบวางบิลรายเดือน\n\n'
        'กดปุ่มด้านล่าง ระบบจะสร้างออเดอร์เครดิตตัวอย่างให้ทันที',
    action: TourAction.createCredit,
    actionLabel: 'สร้างออเดอร์เครดิตตัวอย่าง',
    required: true,
  ),
  const TourStep(
    chapter: 5,
    title: 'ออเดอร์เครดิต',
    body: 'สถานะการชำระเป็น "เครดิต" ไม่ต้องกดรับเงินทีละออเดอร์ ยอดจะไปเคลียร์รวมในใบวางบิล',
    target: 'status-card',
    on: _orderPage,
    route: _creditRoute,
  ),
  TourStep(
    chapter: 5,
    title: 'รวมเข้าใบวางบิล',
    body: 'กด "รวมเข้าใบวางบิล" เพื่อไปหน้าเคลียร์บิลของลูกค้ารายนี้',
    target: 'to-statement',
    on: _orderPage,
    route: _creditRoute,
    done: (e) => e.page == TourPage.statementCreate,
    required: true,
  ),
  const TourStep(
    chapter: 6,
    title: 'สร้างใบวางบิล',
    body: 'เลือกช่วงวันที่ แล้วติ๊กออเดอร์ที่จะรวมในใบวางบิล ระบบรวมยอดให้ด้านล่าง',
    target: 'st-create',
    on: {TourPage.statementCreate},
    route: _createStatementRoute,
  ),
  TourStep(
    chapter: 6,
    title: 'ออกใบวางบิล',
    body: 'กด "สร้างใบวางบิลและพิมพ์" แล้วส่งใบวางบิลให้ลูกค้า',
    target: 'st-create-submit',
    on: const {TourPage.statementCreate},
    route: _createStatementRoute,
    done: (e) => e.page == TourPage.statementBill,
    capture: (e) => TourVars(statementId: e.pageId),
    required: true,
  ),
  const TourStep(
    chapter: 6,
    title: 'ใบวางบิล',
    body: 'ใบวางบิลรวมทุกออเดอร์ในช่วงที่เลือก พร้อมยอดรวม พิมพ์หรือบันทึกรูปส่งลูกค้าได้เหมือนบิลทั่วไป',
    target: 'bill-sheet',
    on: _statementBill,
    route: _statementBillRoute,
    placeTop: false,
  ),
  TourStep(
    chapter: 6,
    title: 'กลับหน้าเคลียร์บิล',
    body: 'กดลูกศรกลับ เพื่อไปเคลียร์บิลเมื่อลูกค้าจ่ายเงิน',
    target: 'bill-back',
    on: _statementBill,
    route: _statementBillRoute,
    done: (e) => e.page == TourPage.statements,
    placeTop: false,
    required: true,
  ),
  const TourStep(
    chapter: 7,
    title: 'ใบวางบิลรอเคลียร์',
    body: 'ใบวางบิลที่ยังไม่ได้เก็บเงินอยู่ในรายการนี้ พร้อมยอดที่ต้องเก็บ',
    target: 'st-demo-row',
    on: {TourPage.statements},
    route: _statementsRoute,
  ),
  TourStep(
    chapter: 7,
    title: 'เคลียร์บิล',
    body: 'เมื่อลูกค้าจ่ายครบ กด "เคลียร์บิล"',
    target: 'st-clear',
    on: const {TourPage.statements},
    route: _statementsRoute,
    done: (e) => e.has('st-clear-modal'),
  ),
  TourStep(
    chapter: 7,
    title: 'ยืนยันการรับเงิน',
    body: 'เลือกว่ารับเป็นเงินสดหรือโอน แล้วกด "ยืนยันเคลียร์บิล"',
    target: 'st-clear-modal',
    on: const {TourPage.statements},
    route: _statementsRoute,
    done: (e) => !e.has('st-clear-modal') && !e.has('st-clear'),
    placeTop: true,
  ),
  const TourStep(
    chapter: 7,
    title: 'ปิดออเดอร์ครบแล้ว',
    body: 'ทุกออเดอร์ในใบวางบิลเปลี่ยนเป็น "จ่ายแล้ว" และ "เคลียร์แล้ว" พร้อมเลขใบเสร็จอัตโนมัติ',
    target: 'status-card',
    on: _orderPage,
    route: _creditRoute,
  ),
  const TourStep(
    chapter: 8,
    title: 'จบการสอนแล้ว',
    body:
        'ตอนนี้คุณทำได้ครบทั้งวงจร: สร้างออเดอร์ → ออกบิล → ส่งของ → รับเงิน → แก้ไข/ยกเลิก → วางบิล → เคลียร์บิล\n\n'
        'กดปุ่มด้านล่างเพื่อลบข้อมูลสาธิตทั้งหมดและกลับไปใช้งานจริง',
    action: TourAction.finish,
    actionLabel: 'ลบข้อมูลสาธิตและจบการสอน',
  ),
];

/// Back only re-shows explanations on the same screen; interactive steps cannot be "undone".
bool canGoBack(List<TourStep> steps, int index) {
  if (index <= 0 || index >= steps.length) return false;
  final prev = steps[index - 1];
  final cur = steps[index];
  bool sameOn(Set<TourPage>? a, Set<TourPage>? b) =>
      a == null ? b == null : b != null && a.length == b.length && a.containsAll(b);
  return prev.done == null && prev.action == null && sameOn(prev.on, cur.on);
}

({int chapter, int chapterStep, int chapterSize}) chapterProgress(List<TourStep> steps, int index) {
  final chapter = index >= 0 && index < steps.length ? steps[index].chapter : 0;
  final inChapter = [
    for (var i = 0; i < steps.length; i++)
      if (steps[i].chapter == chapter) i,
  ];
  return (chapter: chapter, chapterStep: inChapter.indexOf(index) + 1, chapterSize: inChapter.length);
}
