import 'dart:math' as math;

import '../calc/pricing.dart';
import '../calc/trips.dart';
import '../models/models.dart';
import 'order_draft.dart';

/// SharedPreferences key of the in-progress wizard.
const draftKey = 'stone_sand_new_order_v6';

enum StepKey {
  source('ประเภท'),
  products('สินค้า'),
  customer('ลูกค้า'),
  fulfillment('รับสินค้า'),
  summary('สรุป'),
  confirm('ยืนยัน');

  const StepKey(this.label);
  final String label;
}

const steps = StepKey.values;

int stepIndex(StepKey key) => steps.indexOf(key);

const _unset = Object();

class WizardState {
  const WizardState({
    this.source,
    this.orderDate = '',
    this.customer,
    this.loads = const {},
    this.fulfillment,
    this.deliveryAddress = '',
    this.pinLat,
    this.pinLng,
    this.zoneId,
    this.tambonMethod,
    this.outsideDistrict = false,
    this.roadDistanceKm,
    this.roadLabel = '',
    this.truckSize = 5,
    this.truckTouched = false,
    this.trips = 0,
    this.feePerCubic = 0,
    this.feePerTrip = 0,
    this.feeTouched = false,
    this.remoteSurcharge = 0,
    this.deliveryDiscount = 0,
    this.driverId,
    this.driverTruckSize,
    this.driverConfirmed = false,
    this.unitDiscounts = const {},
    this.discountType = DiscountType.baht,
    this.discountValue = 0,
    this.paymentMethod,
    this.paidNow = false,
    this.note = '',
  });

  final OrderSource? source;

  /// YYYY-MM-DD; '' means today.
  final String orderDate;
  final Customer? customer;
  final Map<String, Load> loads;
  final Fulfillment? fulfillment;
  final String deliveryAddress;
  final double? pinLat;
  final double? pinLng;
  final String? zoneId;

  /// 'exact' | 'nearest' | 'manual'
  final String? tambonMethod;
  final bool outsideDistrict;
  final double? roadDistanceKm;
  final String roadLabel;
  final int truckSize;
  final bool truckTouched;
  final int trips;

  /// Tambon delivery fee per คิว ordered.
  final double feePerCubic;

  /// Distance surcharge per trip.
  final double feePerTrip;

  /// Either fee was typed in, so the suggestion no longer overwrites them.
  final bool feeTouched;
  final double remoteSurcharge;

  /// ส่วนลดค่าส่ง in baht.
  final double deliveryDiscount;
  final String? driverId;
  final int? driverTruckSize;
  final bool driverConfirmed;

  /// ส่วนลดบาทต่อคิว by product id.
  final Map<String, double> unitDiscounts;
  final DiscountType discountType;
  final double discountValue;
  final PaymentMethod? paymentMethod;
  final bool paidNow;
  final String note;

  bool get hasPin => pinLat != null && pinLng != null;

  WizardState copyWith({
    Object? source = _unset,
    String? orderDate,
    Object? customer = _unset,
    Map<String, Load>? loads,
    Object? fulfillment = _unset,
    String? deliveryAddress,
    Object? pinLat = _unset,
    Object? pinLng = _unset,
    Object? zoneId = _unset,
    Object? tambonMethod = _unset,
    bool? outsideDistrict,
    Object? roadDistanceKm = _unset,
    String? roadLabel,
    int? truckSize,
    bool? truckTouched,
    int? trips,
    double? feePerCubic,
    double? feePerTrip,
    bool? feeTouched,
    double? remoteSurcharge,
    double? deliveryDiscount,
    Object? driverId = _unset,
    Object? driverTruckSize = _unset,
    bool? driverConfirmed,
    Map<String, double>? unitDiscounts,
    DiscountType? discountType,
    double? discountValue,
    Object? paymentMethod = _unset,
    bool? paidNow,
    String? note,
  }) =>
      WizardState(
        source: identical(source, _unset) ? this.source : source as OrderSource?,
        orderDate: orderDate ?? this.orderDate,
        customer: identical(customer, _unset) ? this.customer : customer as Customer?,
        loads: loads ?? this.loads,
        fulfillment: identical(fulfillment, _unset) ? this.fulfillment : fulfillment as Fulfillment?,
        deliveryAddress: deliveryAddress ?? this.deliveryAddress,
        pinLat: identical(pinLat, _unset) ? this.pinLat : pinLat as double?,
        pinLng: identical(pinLng, _unset) ? this.pinLng : pinLng as double?,
        zoneId: identical(zoneId, _unset) ? this.zoneId : zoneId as String?,
        tambonMethod: identical(tambonMethod, _unset) ? this.tambonMethod : tambonMethod as String?,
        outsideDistrict: outsideDistrict ?? this.outsideDistrict,
        roadDistanceKm: identical(roadDistanceKm, _unset) ? this.roadDistanceKm : roadDistanceKm as double?,
        roadLabel: roadLabel ?? this.roadLabel,
        truckSize: truckSize ?? this.truckSize,
        truckTouched: truckTouched ?? this.truckTouched,
        trips: trips ?? this.trips,
        feePerCubic: feePerCubic ?? this.feePerCubic,
        feePerTrip: feePerTrip ?? this.feePerTrip,
        feeTouched: feeTouched ?? this.feeTouched,
        remoteSurcharge: remoteSurcharge ?? this.remoteSurcharge,
        deliveryDiscount: deliveryDiscount ?? this.deliveryDiscount,
        driverId: identical(driverId, _unset) ? this.driverId : driverId as String?,
        driverTruckSize: identical(driverTruckSize, _unset) ? this.driverTruckSize : driverTruckSize as int?,
        driverConfirmed: driverConfirmed ?? this.driverConfirmed,
        unitDiscounts: unitDiscounts ?? this.unitDiscounts,
        discountType: discountType ?? this.discountType,
        discountValue: discountValue ?? this.discountValue,
        paymentMethod: identical(paymentMethod, _unset) ? this.paymentMethod : paymentMethod as PaymentMethod?,
        paidNow: paidNow ?? this.paidNow,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'source': source?.name,
        'orderDate': orderDate,
        'customer': customer?.toJson(),
        'loads': loads.map((k, l) => MapEntry(k, {'perTrip': l.perTrip, 'trips': l.trips})),
        'fulfillment': fulfillment?.name,
        'deliveryAddress': deliveryAddress,
        'pinLat': pinLat,
        'pinLng': pinLng,
        'zoneId': zoneId,
        'tambonMethod': tambonMethod,
        'outsideDistrict': outsideDistrict,
        'roadDistanceKm': roadDistanceKm,
        'roadLabel': roadLabel,
        'truckSize': truckSize,
        'truckTouched': truckTouched,
        'trips': trips,
        'feePerCubic': feePerCubic,
        'feePerTrip': feePerTrip,
        'feeTouched': feeTouched,
        'remoteSurcharge': remoteSurcharge,
        'deliveryDiscount': deliveryDiscount,
        'driverId': driverId,
        'driverTruckSize': driverTruckSize,
        'driverConfirmed': driverConfirmed,
        'unitDiscounts': unitDiscounts,
        'discountType': discountType.name,
        'discountValue': discountValue,
        'paymentMethod': paymentMethod?.name,
        'paidNow': paidNow,
        'note': note,
      };

  factory WizardState.fromJson(Map<String, dynamic> j) {
    double? d(Object? v) => v is num ? v.toDouble() : null;
    final loads = <String, Load>{};
    (j['loads'] as Map?)?.forEach((k, v) {
      if (v is Map) {
        loads['$k'] = Load(perTrip: (v['perTrip'] as num?) ?? 0, trips: (v['trips'] as num?) ?? 0);
      }
    });
    final unit = <String, double>{};
    (j['unitDiscounts'] as Map?)?.forEach((k, v) {
      if (v is num) unit['$k'] = v.toDouble();
    });
    return WizardState(
      source: OrderSource.tryParse(j['source']),
      orderDate: (j['orderDate'] as String?) ?? '',
      customer: j['customer'] is Map ? Customer.fromJson(Map<String, dynamic>.from(j['customer'] as Map)) : null,
      loads: loads,
      fulfillment: j['fulfillment'] == null ? null : Fulfillment.parse(j['fulfillment']),
      deliveryAddress: (j['deliveryAddress'] as String?) ?? '',
      pinLat: d(j['pinLat']),
      pinLng: d(j['pinLng']),
      zoneId: j['zoneId'] as String?,
      tambonMethod: j['tambonMethod'] as String?,
      outsideDistrict: j['outsideDistrict'] == true,
      roadDistanceKm: d(j['roadDistanceKm']),
      roadLabel: (j['roadLabel'] as String?) ?? '',
      truckSize: (j['truckSize'] as num?)?.toInt() == 3 ? 3 : 5,
      truckTouched: j['truckTouched'] == true,
      trips: (j['trips'] as num?)?.toInt() ?? 0,
      feePerCubic: d(j['feePerCubic']) ?? 0,
      feePerTrip: d(j['feePerTrip']) ?? 0,
      feeTouched: j['feeTouched'] == true,
      remoteSurcharge: d(j['remoteSurcharge']) ?? 0,
      deliveryDiscount: d(j['deliveryDiscount']) ?? 0,
      driverId: j['driverId'] as String?,
      driverTruckSize: (j['driverTruckSize'] as num?)?.toInt(),
      driverConfirmed: j['driverConfirmed'] == true,
      unitDiscounts: unit,
      discountType: DiscountType.parse(j['discountType']),
      discountValue: d(j['discountValue']) ?? 0,
      paymentMethod: j['paymentMethod'] == null ? null : PaymentMethod.parse(j['paymentMethod']),
      paidNow: j['paidNow'] == true,
      note: (j['note'] as String?) ?? '',
    );
  }
}

const initialWizardState = WizardState();

List<OrderItem> buildItems(
  List<Product> products,
  Map<String, num> quantities, [
  Map<String, double> unitDiscounts = const {},
]) {
  return products.where((p) => (quantities[p.id] ?? 0) > 0).map((p) {
    final q = quantities[p.id]!.toDouble();
    return OrderItem(
      productId: p.id,
      name: p.name,
      unit: p.unit,
      unitPrice: p.pricePerUnit,
      quantity: q,
      amount: lineAmount(p.pricePerUnit, q),
      discountPerUnit: math.min(math.max(0, unitDiscounts[p.id] ?? 0), p.pricePerUnit).toDouble(),
    );
  }).toList();
}

double totalQuantity(Map<String, num> quantities) =>
    quantities.values.fold<double>(0, (s, q) => s + (q > 0 ? q : 0));

Map<String, double> quantitiesOf(Map<String, Load> loads) =>
    loads.map((id, l) => MapEntry(id, jsRound(l.perTrip * l.trips * 10) / 10));

/// Keeps the delivery step in line with the products step: trips are the trips entered per product,
/// and the truck (and selected driver's truck) must carry the largest คิวต่อเที่ยว.
WizardState withDeliveryPlan(WizardState s) {
  final loads = s.loads.values.toList();
  final trips = totalTrips(loads);
  final keepTruck = s.truckTouched && truckFits(s.truckSize, loads);
  final truckSize = keepTruck ? s.truckSize : truckForLoads(loads);
  final dropDriver = s.driverId != null && s.driverTruckSize != null && !truckFits(s.driverTruckSize!, loads);
  if (trips == s.trips && truckSize == s.truckSize && keepTruck == s.truckTouched && !dropDriver) return s;
  final next = s.copyWith(trips: trips, truckSize: truckSize, truckTouched: keepTruck);
  return dropDriver ? next.copyWith(driverId: null, driverTruckSize: null, driverConfirmed: false) : next;
}

/// Error message for the step, or '' when the step is complete.
String validateStep(int step, WizardState s) {
  if (step < 0 || step >= steps.length) return '';
  switch (steps[step]) {
    case StepKey.source:
      return s.source != null ? '' : 'เลือกประเภทออเดอร์';
    case StepKey.products:
      return totalQuantity(quantitiesOf(s.loads)) > 0 ? '' : 'เลือกสินค้าอย่างน้อย 1 รายการ';
    case StepKey.customer:
      return s.customer != null ? '' : 'เลือกหรือเพิ่มลูกค้าก่อน';
    case StepKey.fulfillment:
      if (s.fulfillment == null) return 'เลือกว่ามารับเองหรือจัดส่ง';
      if (s.fulfillment == Fulfillment.delivery) {
        if (!s.hasPin && s.deliveryAddress.trim().isEmpty) return 'ปักหมุดหรือใส่ที่อยู่จัดส่ง';
        if (s.zoneId == null) return 'เลือกตำบลที่จัดส่ง';
        if (s.driverId == null) return 'เลือกคนขับ';
        if (!s.driverConfirmed) return 'ยืนยันว่ารถเข้าหน้างานได้และมีคิวว่าง';
      }
      return '';
    case StepKey.summary:
      return s.paymentMethod != null ? '' : 'เลือกวิธีชำระเงิน';
    case StepKey.confirm:
      return '';
  }
}

bool defaultPaidNow(PaymentMethod method) => method == PaymentMethod.cash || method == PaymentMethod.transfer;

OrderDraft toDraft(WizardState s, List<Product> products, double driverWagePerTrip) {
  if (s.source == null || s.customer == null || s.fulfillment == null || s.paymentMethod == null) {
    throw StateError('ข้อมูลออเดอร์ยังไม่ครบ');
  }
  final delivery = s.fulfillment == Fulfillment.delivery;
  return OrderDraft(
    source: s.source!,
    orderDate: s.orderDate.isEmpty ? null : s.orderDate,
    customer: s.customer!,
    items: buildItems(products, quantitiesOf(s.loads), s.unitDiscounts),
    fulfillment: s.fulfillment!,
    deliveryAddress: s.deliveryAddress,
    pinLat: s.pinLat,
    pinLng: s.pinLng,
    zoneId: s.zoneId,
    roadDistanceKm: s.roadDistanceKm,
    truckSize: delivery ? s.truckSize : null,
    trips: delivery ? s.trips : 0,
    driverId: delivery ? s.driverId : null,
    feePerCubic: s.feePerCubic,
    feePerTrip: s.feePerTrip,
    remoteSurcharge: s.remoteSurcharge,
    deliveryDiscount: delivery ? s.deliveryDiscount : 0,
    discountType: s.discountType,
    discountValue: s.discountValue,
    paymentMethod: s.paymentMethod!,
    paidNow: s.paymentMethod == PaymentMethod.credit ? false : s.paidNow,
    driverWage: delivery && s.driverId != null ? driverWagePerTrip * s.trips : 0,
    note: s.note,
  );
}
