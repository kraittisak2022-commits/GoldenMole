import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/bill/bill_data.dart';
import 'package:mobile_stone_sand/calc/trips.dart';
import 'package:mobile_stone_sand/logic/format.dart';
import 'package:mobile_stone_sand/logic/wizard_state.dart';
import 'package:mobile_stone_sand/models/models.dart';

const products = [
  Product(
    id: 'small-stone',
    name: 'หินเล็กคละ เบอร์ 1-3',
    category: ProductCategory.stone,
    unit: 'คิว',
    pricePerUnit: 400,
    sortOrder: 1,
    active: true,
  ),
  Product(
    id: 'fill-sand',
    name: 'ทรายถม (ทรายขี้เป็ด)',
    category: ProductCategory.sand,
    unit: 'คิว',
    pricePerUnit: 220,
    sortOrder: 3,
    active: true,
  ),
];

const customer = Customer(id: 'cus-1', name: 'สมชาย', phone: '0931234567', address: 'บ้านทุ่งฮั้ว');

final sourceStep = stepIndex(StepKey.source);
final productsStep = stepIndex(StepKey.products);
final customerStep = stepIndex(StepKey.customer);
final fulfillmentStep = stepIndex(StepKey.fulfillment);

void main() {
  group('validateStep', () {
    test('asks for the order source first, then products, then the customer', () {
      expect(steps.map((s) => s.name).toList(),
          ['source', 'products', 'customer', 'fulfillment', 'summary', 'confirm']);
      expect(validateStep(sourceStep, const WizardState()), contains('ประเภท'));
      expect(validateStep(sourceStep, const WizardState(source: OrderSource.pit)), '');
      expect(
        validateStep(productsStep, const WizardState(loads: {'small-stone': Load(perTrip: 3, trips: 0)})),
        contains('สินค้า'),
      );
      expect(validateStep(productsStep, const WizardState(loads: {'small-stone': Load(perTrip: 3, trips: 1)})), '');
      expect(validateStep(customerStep, const WizardState()), contains('ลูกค้า'));
      expect(validateStep(customerStep, const WizardState(customer: customer)), '');
    });

    test('pickup needs nothing else; delivery needs location, tambon and driver', () {
      expect(validateStep(fulfillmentStep, const WizardState(fulfillment: Fulfillment.pickup)), '');
      expect(validateStep(fulfillmentStep, const WizardState(fulfillment: Fulfillment.delivery)), contains('ปักหมุด'));
      expect(
        validateStep(fulfillmentStep,
            const WizardState(fulfillment: Fulfillment.delivery, pinLat: 19.2, pinLng: 99.6)),
        contains('ตำบล'),
      );
      expect(
        validateStep(
          fulfillmentStep,
          const WizardState(fulfillment: Fulfillment.delivery, pinLat: 19.2, pinLng: 99.6, zoneId: 'thung-hua'),
        ),
        'เลือกคนขับ',
      );
    });

    test('asks to confirm the driver is available', () {
      const s = WizardState(
        fulfillment: Fulfillment.delivery,
        deliveryAddress: 'x',
        zoneId: 'thung-hua',
        driverId: 'drv-ko',
      );
      expect(validateStep(fulfillmentStep, s), contains('คิวว่าง'));
      expect(validateStep(fulfillmentStep, s.copyWith(driverConfirmed: true)), '');
    });
  });

  group('toDraft', () {
    test('builds items and driver wage from the wizard', () {
      const s = WizardState(
        source: OrderSource.shop,
        customer: customer,
        loads: {'small-stone': Load(perTrip: 5, trips: 1), 'fill-sand': Load(perTrip: 5, trips: 1)},
        fulfillment: Fulfillment.delivery,
        zoneId: 'thung-hua',
        trips: 2,
        truckSize: 5,
        feePerTrip: 350,
        driverId: 'drv-ko',
        driverConfirmed: true,
        paymentMethod: PaymentMethod.cash,
        paidNow: true,
        deliveryDiscount: 100,
      );
      final d = toDraft(s, products, 500);
      expect(d.source, OrderSource.shop);
      expect(d.items.map((i) => i.amount).toList(), [2000, 1100]);
      expect(d.driverWage, 1000);
      expect(d.deliveryDiscount, 100);
      expect(d.paidNow, true);
    });

    test('credit orders are never paid now and pickup drops delivery fields', () {
      final d = toDraft(
        const WizardState(
          source: OrderSource.pit,
          customer: customer,
          loads: {'fill-sand': Load(perTrip: 3, trips: 1)},
          fulfillment: Fulfillment.pickup,
          paymentMethod: PaymentMethod.credit,
          paidNow: true,
          deliveryDiscount: 200,
        ),
        products,
        500,
      );
      expect(d.source, OrderSource.pit);
      expect(d.paidNow, false);
      expect(d.trips, 0);
      expect(d.driverWage, 0);
      expect(d.deliveryDiscount, 0);
    });

    test('sends the chosen order date, or null so the database uses today', () {
      const base = WizardState(
        source: OrderSource.shop,
        customer: customer,
        loads: {'fill-sand': Load(perTrip: 3, trips: 1)},
        fulfillment: Fulfillment.pickup,
        paymentMethod: PaymentMethod.cash,
      );
      expect(toDraft(base, products, 0).orderDate, isNull);
      expect(toDraft(base.copyWith(orderDate: '2026-10-01'), products, 0).orderDate, '2026-10-01');
    });

    test('refuses to build an order without a source', () {
      expect(
        () => toDraft(
          const WizardState(
            customer: customer,
            loads: {'fill-sand': Load(perTrip: 3, trips: 1)},
            fulfillment: Fulfillment.pickup,
            paymentMethod: PaymentMethod.cash,
          ),
          products,
          0,
        ),
        throwsStateError,
      );
    });

    test('skips products with zero quantity', () {
      expect(buildItems(products, {'small-stone': 0, 'fill-sand': 1}), hasLength(1));
    });
  });

  group('withDeliveryPlan', () {
    test('takes trips from the products and the smallest truck that fits', () {
      final s = withDeliveryPlan(const WizardState(
        loads: {'small-stone': Load(perTrip: 3, trips: 2), 'fill-sand': Load(perTrip: 2, trips: 1)},
      ));
      expect(s.trips, 3);
      expect(s.truckSize, 3);
    });

    test('keeps a bigger truck the user chose, but never one that is too small', () {
      const loads = {'small-stone': Load(perTrip: 3, trips: 2)};
      expect(withDeliveryPlan(const WizardState(loads: loads, truckSize: 5, truckTouched: true)).truckSize, 5);
      final grown = withDeliveryPlan(const WizardState(
        loads: {'small-stone': Load(perTrip: 5, trips: 2)},
        truckSize: 3,
        truckTouched: true,
      ));
      expect(grown.truckSize, 5);
      expect(grown.truckTouched, false);
    });

    test('drops a driver whose truck no longer carries the load', () {
      const picked = WizardState(
        driverId: 'drv-ko',
        driverTruckSize: 3,
        driverConfirmed: true,
        truckSize: 3,
        truckTouched: true,
      );
      final fits = withDeliveryPlan(picked.copyWith(loads: {'small-stone': const Load(perTrip: 3, trips: 1)}));
      expect(fits.driverId, 'drv-ko');
      final tooBig = withDeliveryPlan(picked.copyWith(loads: {'small-stone': const Load(perTrip: 5, trips: 1)}));
      expect(tooBig.driverId, isNull);
      expect(tooBig.driverConfirmed, false);
      expect(tooBig.truckSize, 5);
    });

    test('returns the same object when nothing changes', () {
      final s = withDeliveryPlan(const WizardState(loads: {'small-stone': Load(perTrip: 3, trips: 1)}));
      expect(identical(withDeliveryPlan(s), s), true);
    });

    test('quantitiesOf multiplies คิวต่อเที่ยว by trips', () {
      expect(
        quantitiesOf({'small-stone': const Load(perTrip: 3, trips: 2), 'fill-sand': const Load(perTrip: 5, trips: 0)}),
        {'small-stone': 6, 'fill-sand': 0},
      );
    });

    test('round-trips through JSON', () {
      const s = WizardState(
        source: OrderSource.pit,
        customer: customer,
        loads: {'small-stone': Load(perTrip: 3, trips: 2)},
        fulfillment: Fulfillment.delivery,
        pinLat: 19.1,
        pinLng: 99.6,
        paymentMethod: PaymentMethod.cod,
        unitDiscounts: {'small-stone': 20},
      );
      final back = WizardState.fromJson(s.toJson());
      expect(back.source, OrderSource.pit);
      expect(back.customer?.name, 'สมชาย');
      expect(back.loads['small-stone']?.trips, 2);
      expect(back.pinLat, 19.1);
      expect(back.paymentMethod, PaymentMethod.cod);
      expect(back.unitDiscounts['small-stone'], 20);
    });
  });

  group('billFromOrder', () {
    const order = Order(
      id: 'o1',
      orderNo: 'DO6910-0001',
      receiptNo: 'RE6910-0001',
      orderDate: '2026-10-08',
      customerId: 'c1',
      customer: CustomerSnapshot(name: 'สมชาย', phone: '0931234567', address: 'ทุ่งฮั้ว'),
      fulfillment: Fulfillment.delivery,
      deliveryAddress: 'หมู่ 3',
      zoneId: 'thung-hua',
      truckSize: 5,
      trips: 2,
      feePerTrip: 350,
      remoteSurcharge: 100,
      discountType: DiscountType.percent,
      discountValue: 10,
      subtotal: 2000,
      deliveryTotal: 800,
      discountAmount: 200,
      total: 2600,
      paymentMethod: PaymentMethod.cash,
      paymentStatus: PaymentStatus.paid,
      paidAt: '2026-10-08T03:00:00Z',
      cleared: true,
      verifyToken: 'tok',
      createdBy: 'admin',
      items: [
        OrderItem(productId: 'small-stone', name: 'หินเล็กคละ', unit: 'คิว', unitPrice: 400, quantity: 5, amount: 2000),
      ],
    );

    const thungHua = Zone(id: 'thung-hua', name: 'ทุ่งฮั้ว', feePerCubic: 40, sortOrder: 1);

    test('adds delivery and surcharge lines that sum to the gross amount', () {
      final bill = billFromOrder(order, DocKind.delivery, zone: thungHua);
      expect(bill.lines.map((l) => l.amount).toList(), [2000, 700, 100]);
      expect(bill.lines.fold<double>(0, (s, l) => s + l.amount), bill.gross);
      expect(bill.gross - bill.discountAmount, bill.total);
      expect(bill.lines[1].description, 'ค่าขนส่ง ต.ทุ่งฮั้ว');
      expect(bill.docNo, 'DO6910-0001');
      expect(bill.discountLabel, contains('10%'));
    });

    test('charges the tambon fee per คิว and the distance surcharge per trip', () {
      // 5 คิว × 40 + 2 เที่ยว × 50 + 100 remote
      final perCubic =
          order.copyWith(feePerCubic: 40, feePerTrip: 50, deliveryTotal: 400, discountAmount: 0, total: 2400);
      final bill = billFromOrder(perCubic, DocKind.delivery, zone: thungHua);
      final delivery = bill.lines.skip(1).toList();
      expect(delivery.map((l) => l.description).toList(),
          ['ค่าขนส่ง ต.ทุ่งฮั้ว', 'ค่าขนส่งเพิ่มตามระยะทาง', 'ค่าขนส่งเพิ่ม (พื้นที่ห่างไกล)']);
      expect(delivery.map((l) => l.amount).toList(), [200, 100, 100]);
      expect((delivery[0].quantity, delivery[0].unit, delivery[0].unitPrice), (5, 'คิว', 40));
      expect((delivery[1].quantity, delivery[1].unit, delivery[1].unitPrice), (2, 'เที่ยว', 50));
      expect(bill.lines.fold<double>(0, (s, l) => s + l.amount), bill.gross);

      final near = billFromOrder(perCubic.copyWith(feePerTrip: 0, deliveryTotal: 300, total: 2300), DocKind.delivery,
          zone: thungHua);
      expect(near.lines.map((l) => l.description).toList(),
          ['หินเล็กคละ', 'ค่าขนส่ง ต.ทุ่งฮั้ว', 'ค่าขนส่งเพิ่ม (พื้นที่ห่างไกล)']);
    });

    test('names ส่วนลดค่าส่ง alongside the bill discount', () {
      final bill = billFromOrder(
        order.copyWith(deliveryDiscount: 100, discountAmount: 300, total: 2500),
        DocKind.delivery,
      );
      expect(bill.discountLabel, 'ส่วนลดค่าส่ง + ส่วนลด 10% (ค่าสินค้า)');
      expect(
        billFromOrder(order.copyWith(deliveryDiscount: 100, discountAmount: 100, total: 2700), DocKind.delivery)
            .discountLabel,
        'ส่วนลดค่าส่ง',
      );
    });

    test('a receipt uses the receipt number and references the delivery note', () {
      final bill = billFromOrder(order, DocKind.receipt);
      expect(bill.docNo, 'RE6910-0001');
      expect(bill.refs, [(label: 'อ้างอิงใบส่งของ', value: 'DO6910-0001')]);
    });

    test('pickup orders have no delivery line', () {
      final bill = billFromOrder(
        order.copyWith(fulfillment: Fulfillment.pickup, trips: 0, deliveryTotal: 0),
        DocKind.delivery,
      );
      expect(bill.lines, hasLength(1));
      expect(bill.delivery, isNull);
    });

    test('billFromStatement lists one line per order', () {
      const s = Statement(
        id: 's1',
        statementNo: 'BL6910-0001',
        source: OrderSource.shop,
        customerId: 'c1',
        customer: CustomerSnapshot(name: 'สมชาย'),
        periodFrom: '2026-10-01',
        periodTo: '2026-10-31',
        total: 5200,
        status: 'open',
        verifyToken: 'st',
        createdAt: '2026-10-31T10:00:00Z',
        orderIds: ['o1', 'o2'],
      );
      final bill = billFromStatement(s, [order, order.copyWith(id: 'o2', orderNo: 'DO6910-0002')]);
      expect(bill.lines, hasLength(2));
      expect(bill.lines[0].date, '2026-10-08');
      expect(bill.total, 5200);
      expect(bill.paid, false);
      expect(bill.period, (from: '2026-10-01', to: '2026-10-31'));
    });
  });
}
