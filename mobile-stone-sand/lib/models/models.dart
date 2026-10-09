import '../calc/delivery_fee.dart';
import '../calc/pricing.dart';
import '../logic/customer_search.dart';

export '../calc/delivery_fee.dart' show DeliverySettings;
export '../calc/pricing.dart' show DiscountType;

double _num(Object? v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
double? _numOrNull(Object? v) => v == null ? null : _num(v);
int _int(Object? v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
String _str(Object? v) => v == null ? '' : '$v';

enum RouteGroup {
  north('สายเหนือ'),
  south('สายใต้'),
  thungpao('ทุ่งเป้า-บ้านใหม่');

  const RouteGroup(this.label);
  final String label;

  static RouteGroup parse(Object? v) =>
      RouteGroup.values.firstWhere((e) => e.name == v, orElse: () => RouteGroup.north);
}

enum Fulfillment {
  pickup,
  delivery;

  static Fulfillment parse(Object? v) => v == 'delivery' ? delivery : pickup;
}

enum PaymentMethod {
  cash('เงินสด'),
  transfer('โอนเงิน'),
  cod('จ่ายปลายทาง'),
  credit('เครดิตรายเดือน');

  const PaymentMethod(this.label);
  final String label;

  static PaymentMethod parse(Object? v) =>
      PaymentMethod.values.firstWhere((e) => e.name == v, orElse: () => PaymentMethod.cash);
}

enum PaymentStatus {
  unpaid('ยังไม่จ่าย'),
  paid('จ่ายแล้ว'),
  credit('ค้างเครดิต');

  const PaymentStatus(this.label);
  final String label;

  static PaymentStatus parse(Object? v) =>
      PaymentStatus.values.firstWhere((e) => e.name == v, orElse: () => PaymentStatus.unpaid);
}

enum DeliveryStatus {
  pickup('มารับเอง'),
  waiting('รอจัดส่ง'),
  dispatched('กำลังส่ง'),
  delivered('ส่งแล้ว');

  const DeliveryStatus(this.label);
  final String label;

  static DeliveryStatus parse(Object? v) =>
      DeliveryStatus.values.firstWhere((e) => e.name == v, orElse: () => DeliveryStatus.waiting);
}

enum ProductCategory {
  stone('หิน'),
  sand('ทราย');

  const ProductCategory(this.label);
  final String label;

  static ProductCategory parse(Object? v) => v == 'sand' ? sand : stone;
}

/// shop = ออเดอร์จากร้านวัสดุก่อสร้าง, pit = สั่งจากท่าทรายโดยตรง (เลขที่ TS).
enum OrderSource {
  shop('ร้านวัสดุก่อสร้าง', 'ร้านวัสดุ'),
  pit('ท่าทราย', 'ท่าทราย');

  const OrderSource(this.label, this.short);
  final String label;
  final String short;

  static OrderSource parse(Object? v) => v == 'pit' ? pit : shop;

  static OrderSource? tryParse(Object? v) => v == 'pit' ? pit : (v == 'shop' ? shop : null);
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.pricePerUnit,
    required this.sortOrder,
    required this.active,
  });

  final String id;
  final String name;
  final ProductCategory category;
  final String unit;
  final double pricePerUnit;
  final int sortOrder;
  final bool active;

  factory Product.fromRow(Map<String, dynamic> r) => Product(
        id: _str(r['id']),
        name: _str(r['name']),
        category: ProductCategory.parse(r['category']),
        unit: _str(r['unit']),
        pricePerUnit: _num(r['price_per_unit']),
        sortOrder: _int(r['sort_order']),
        active: r['active'] == true,
      );
}

class Zone {
  const Zone({
    required this.id,
    required this.name,
    required this.feeMin,
    required this.feeMax,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final double feeMin;
  final double feeMax;
  final int sortOrder;

  factory Zone.fromRow(Map<String, dynamic> r) => Zone(
        id: _str(r['id']),
        name: _str(r['name']),
        feeMin: _num(r['fee_min']),
        feeMax: _num(r['fee_max']),
        sortOrder: _int(r['sort_order']),
      );
}

class DriverContact {
  const DriverContact({required this.label, required this.phone});
  final String label;
  final String phone;

  factory DriverContact.fromJson(Map<String, dynamic> j) =>
      DriverContact(label: _str(j['label']), phone: _str(j['phone']));

  Map<String, dynamic> toJson() => {'label': label, 'phone': phone};
}

class Driver {
  const Driver({
    required this.id,
    required this.name,
    required this.village,
    required this.routeGroup,
    required this.truckSize,
    required this.truckCount,
    required this.contacts,
    required this.contactNote,
    required this.wagePerTrip,
    required this.active,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String village;
  final RouteGroup routeGroup;
  final int truckSize;
  final int truckCount;
  final List<DriverContact> contacts;
  final String contactNote;
  final double wagePerTrip;
  final bool active;
  final int sortOrder;

  factory Driver.fromRow(Map<String, dynamic> r) => Driver(
        id: _str(r['id']),
        name: _str(r['name']),
        village: _str(r['village']),
        routeGroup: RouteGroup.parse(r['route_group']),
        truckSize: _int(r['truck_size']) == 3 ? 3 : 5,
        truckCount: _int(r['truck_count']),
        contacts: (r['contacts'] is List)
            ? (r['contacts'] as List)
                .whereType<Map>()
                .map((m) => DriverContact.fromJson(Map<String, dynamic>.from(m)))
                .toList()
            : const [],
        contactNote: _str(r['contact_note']),
        wagePerTrip: _num(r['wage_per_trip']),
        active: r['active'] == true,
        sortOrder: _int(r['sort_order']),
      );
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.aliases = const [],
    this.phone = '',
    this.address = '',
    this.zoneId,
    this.taxId = '',
    this.lat,
    this.lng,
    this.isCredit = false,
    this.note = '',
    this.createdAt = '',
  });

  final String id;
  final String name;

  /// Other names the customer is called by (e.g. เสี่ยบาส for ร้านสินทวีวังเหนือ); searchable.
  final List<String> aliases;
  final String phone;
  final String address;
  final String? zoneId;
  final String taxId;
  final double? lat;
  final double? lng;
  final bool isCredit;
  final String note;
  final String createdAt;

  factory Customer.fromRow(Map<String, dynamic> r) => Customer(
        id: _str(r['id']),
        name: _str(r['name']),
        aliases: parseAliases(_str(r['aliases'])),
        phone: _str(r['phone']),
        address: _str(r['address']),
        zoneId: r['zone_id'] as String?,
        taxId: _str(r['tax_id']),
        lat: _numOrNull(r['lat']),
        lng: _numOrNull(r['lng']),
        isCredit: r['is_credit'] == true,
        note: _str(r['note']),
        createdAt: _str(r['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'aliases': aliases,
        'phone': phone,
        'address': address,
        'zoneId': zoneId,
        'taxId': taxId,
        'lat': lat,
        'lng': lng,
        'isCredit': isCredit,
        'note': note,
        'createdAt': createdAt,
      };

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: _str(j['id']),
        name: _str(j['name']),
        aliases: (j['aliases'] as List?)?.map((e) => '$e').toList() ?? const [],
        phone: _str(j['phone']),
        address: _str(j['address']),
        zoneId: j['zoneId'] as String?,
        taxId: _str(j['taxId']),
        lat: _numOrNull(j['lat']),
        lng: _numOrNull(j['lng']),
        isCredit: j['isCredit'] == true,
        note: _str(j['note']),
        createdAt: _str(j['createdAt']),
      );

  CustomerSnapshot toSnapshot() =>
      CustomerSnapshot(name: name, phone: phone, address: address, taxId: taxId);
}

class CustomerSnapshot {
  const CustomerSnapshot({this.name = '', this.phone = '', this.address = '', this.taxId = ''});
  final String name;
  final String phone;
  final String address;
  final String taxId;

  factory CustomerSnapshot.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return CustomerSnapshot(
      name: _str(m['name']),
      phone: _str(m['phone']),
      address: _str(m['address']),
      taxId: _str(m['taxId']),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone, 'address': address, 'taxId': taxId};
}

class OrderItem {
  const OrderItem({
    this.id,
    required this.productId,
    required this.name,
    required this.unit,
    required this.unitPrice,
    required this.quantity,
    required this.amount,
    this.discountPerUnit = 0,
  });

  final String? id;
  final String? productId;
  final String name;
  final String unit;
  final double unitPrice;
  final double quantity;

  /// List price × quantity; the per-คิว discount is counted in the order's discountAmount.
  final double amount;

  /// ส่วนลดบาทต่อคิว for this product.
  final double discountPerUnit;

  factory OrderItem.fromRow(Map<String, dynamic> r) => OrderItem(
        id: r['id'] as String?,
        productId: r['product_id'] as String?,
        name: _str(r['name']),
        unit: _str(r['unit']),
        unitPrice: _num(r['unit_price']),
        quantity: _num(r['quantity']),
        amount: _num(r['amount']),
        discountPerUnit: _num(r['discount_per_unit']),
      );

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        id: j['id'] as String?,
        productId: j['productId'] as String?,
        name: _str(j['name']),
        unit: _str(j['unit']),
        unitPrice: _num(j['unitPrice']),
        quantity: _num(j['quantity']),
        amount: _num(j['amount']),
        discountPerUnit: _num(j['discountPerUnit']),
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'productId': productId,
        'name': name,
        'unit': unit,
        'unitPrice': unitPrice,
        'quantity': quantity,
        'amount': amount,
        'discountPerUnit': discountPerUnit,
      };

  OrderItem copyWith({
    double? unitPrice,
    double? quantity,
    double? amount,
    double? discountPerUnit,
  }) =>
      OrderItem(
        id: id,
        productId: productId,
        name: name,
        unit: unit,
        unitPrice: unitPrice ?? this.unitPrice,
        quantity: quantity ?? this.quantity,
        amount: amount ?? this.amount,
        discountPerUnit: discountPerUnit ?? this.discountPerUnit,
      );

  PriceLine get priceLine =>
      PriceLine(unitPrice: unitPrice, quantity: quantity, discountPerUnit: discountPerUnit);
}

class StatusLogEntry {
  const StatusLogEntry({required this.at, required this.by, required this.event});
  final String at;
  final String by;
  final String event;

  factory StatusLogEntry.fromJson(Map<String, dynamic> j) =>
      StatusLogEntry(at: _str(j['at']), by: _str(j['by']), event: _str(j['event']));

  Map<String, dynamic> toJson() => {'at': at, 'by': by, 'event': event};
}

const _unset = Object();

class Order {
  const Order({
    required this.id,
    required this.orderNo,
    this.receiptNo,
    this.source = OrderSource.shop,
    required this.orderDate,
    required this.customerId,
    required this.customer,
    this.customerAliases = const [],
    this.fulfillment = Fulfillment.delivery,
    this.deliveryAddress = '',
    this.pinLat,
    this.pinLng,
    this.zoneId,
    this.roadDistanceKm,
    this.truckSize,
    this.trips = 0,
    this.driverId,
    this.feePerTrip = 0,
    this.remoteSurcharge = 0,
    this.discountType = DiscountType.baht,
    this.discountValue = 0,
    this.subtotal = 0,
    this.deliveryTotal = 0,
    this.deliveryDiscount = 0,
    this.discountAmount = 0,
    this.total = 0,
    this.paymentMethod = PaymentMethod.cash,
    this.paymentStatus = PaymentStatus.unpaid,
    this.paidAt,
    this.deliveryStatus = DeliveryStatus.waiting,
    this.deliveredAt,
    this.cleared = false,
    this.clearedAt,
    this.driverWage = 0,
    this.note = '',
    this.cancelled = false,
    this.verifyToken = '',
    this.statusLog = const [],
    this.createdBy,
    this.createdAt = '',
    this.items = const [],
    this.statementId,
    this.driverPayoutId,
    this.demo = false,
  });

  final String id;
  final String orderNo;
  final String? receiptNo;
  final OrderSource source;
  final String orderDate;
  final String customerId;
  final CustomerSnapshot customer;

  /// From the live customer record, for search only; never part of the bill snapshot.
  final List<String> customerAliases;
  final Fulfillment fulfillment;
  final String deliveryAddress;
  final double? pinLat;
  final double? pinLng;
  final String? zoneId;
  final double? roadDistanceKm;
  final int? truckSize;
  final int trips;
  final String? driverId;
  final double feePerTrip;
  final double remoteSurcharge;
  final DiscountType discountType;
  final double discountValue;
  final double subtotal;
  final double deliveryTotal;

  /// ส่วนลดค่าส่ง (baht); included in discountAmount.
  final double deliveryDiscount;
  final double discountAmount;
  final double total;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final String? paidAt;
  final DeliveryStatus deliveryStatus;
  final String? deliveredAt;
  final bool cleared;
  final String? clearedAt;
  final double driverWage;
  final String note;
  final bool cancelled;
  final String verifyToken;
  final List<StatusLogEntry> statusLog;
  final String? createdBy;
  final String createdAt;
  final List<OrderItem> items;
  final String? statementId;
  final String? driverPayoutId;

  /// Created during the guided tour; carries DEMO- document numbers and is deleted when the tour ends.
  final bool demo;

  factory Order.fromRow(Map<String, dynamic> r) {
    final stmtRaw = r['stmt'];
    final stmt = stmtRaw is List ? (stmtRaw.isEmpty ? null : stmtRaw.first) : stmtRaw;
    final cust = r['cust'];
    final rawItems = (r['items'] is List ? List<Map>.from(r['items'] as List) : <Map>[])
      ..sort((a, b) => _int(a['sort_order']).compareTo(_int(b['sort_order'])));
    final log = r['status_log'];
    final truck = r['truck_size'];
    return Order(
      id: _str(r['id']),
      orderNo: _str(r['order_no']),
      receiptNo: r['receipt_no'] as String?,
      source: OrderSource.parse(r['source']),
      orderDate: _str(r['order_date']),
      customerId: _str(r['customer_id']),
      customer: CustomerSnapshot.fromJson(r['customer_snapshot']),
      customerAliases: parseAliases(cust is Map ? _str(cust['aliases']) : ''),
      fulfillment: Fulfillment.parse(r['fulfillment']),
      deliveryAddress: _str(r['delivery_address']),
      pinLat: _numOrNull(r['pin_lat']),
      pinLng: _numOrNull(r['pin_lng']),
      zoneId: r['zone_id'] as String?,
      roadDistanceKm: _numOrNull(r['road_distance_km']),
      truckSize: truck == null ? null : _int(truck),
      trips: _int(r['trips']),
      driverId: r['driver_id'] as String?,
      feePerTrip: _num(r['fee_per_trip']),
      remoteSurcharge: _num(r['remote_surcharge']),
      discountType: DiscountType.parse(r['discount_type']),
      discountValue: _num(r['discount_value']),
      subtotal: _num(r['subtotal']),
      deliveryTotal: _num(r['delivery_total']),
      deliveryDiscount: _num(r['delivery_discount']),
      discountAmount: _num(r['discount_amount']),
      total: _num(r['total']),
      paymentMethod: PaymentMethod.parse(r['payment_method']),
      paymentStatus: PaymentStatus.parse(r['payment_status']),
      paidAt: r['paid_at'] as String?,
      deliveryStatus: DeliveryStatus.parse(r['delivery_status']),
      deliveredAt: r['delivered_at'] as String?,
      cleared: r['cleared'] == true,
      clearedAt: r['cleared_at'] as String?,
      driverWage: _num(r['driver_wage']),
      note: _str(r['note']),
      cancelled: r['cancelled'] == true,
      verifyToken: _str(r['verify_token']),
      statusLog: log is List
          ? log.whereType<Map>().map((m) => StatusLogEntry.fromJson(Map<String, dynamic>.from(m))).toList()
          : const [],
      createdBy: r['created_by'] as String?,
      createdAt: _str(r['created_at']),
      items: rawItems.map((m) => OrderItem.fromRow(Map<String, dynamic>.from(m))).toList(),
      statementId: stmt is Map ? stmt['statement_id'] as String? : null,
      driverPayoutId: r['driver_payout_id'] as String?,
      demo: r['demo_session'] != null,
    );
  }

  Order copyWith({
    String? id,
    String? orderNo,
    OrderSource? source,
    String? orderDate,
    String? customerId,
    CustomerSnapshot? customer,
    List<String>? customerAliases,
    Fulfillment? fulfillment,
    String? deliveryAddress,
    Object? pinLat = _unset,
    Object? pinLng = _unset,
    Object? truckSize = _unset,
    int? trips,
    Object? driverId = _unset,
    double? feePerTrip,
    double? remoteSurcharge,
    DiscountType? discountType,
    double? discountValue,
    double? deliveryDiscount,
    double? subtotal,
    double? deliveryTotal,
    double? discountAmount,
    double? total,
    PaymentMethod? paymentMethod,
    PaymentStatus? paymentStatus,
    DeliveryStatus? deliveryStatus,
    bool? cleared,
    double? driverWage,
    String? note,
    bool? cancelled,
    List<OrderItem>? items,
    Object? statementId = _unset,
    bool? demo,
  }) =>
      Order(
        id: id ?? this.id,
        orderNo: orderNo ?? this.orderNo,
        receiptNo: receiptNo,
        source: source ?? this.source,
        orderDate: orderDate ?? this.orderDate,
        customerId: customerId ?? this.customerId,
        customer: customer ?? this.customer,
        customerAliases: customerAliases ?? this.customerAliases,
        fulfillment: fulfillment ?? this.fulfillment,
        deliveryAddress: deliveryAddress ?? this.deliveryAddress,
        pinLat: identical(pinLat, _unset) ? this.pinLat : pinLat as double?,
        pinLng: identical(pinLng, _unset) ? this.pinLng : pinLng as double?,
        zoneId: zoneId,
        roadDistanceKm: roadDistanceKm,
        truckSize: identical(truckSize, _unset) ? this.truckSize : truckSize as int?,
        trips: trips ?? this.trips,
        driverId: identical(driverId, _unset) ? this.driverId : driverId as String?,
        feePerTrip: feePerTrip ?? this.feePerTrip,
        remoteSurcharge: remoteSurcharge ?? this.remoteSurcharge,
        discountType: discountType ?? this.discountType,
        discountValue: discountValue ?? this.discountValue,
        subtotal: subtotal ?? this.subtotal,
        deliveryTotal: deliveryTotal ?? this.deliveryTotal,
        deliveryDiscount: deliveryDiscount ?? this.deliveryDiscount,
        discountAmount: discountAmount ?? this.discountAmount,
        total: total ?? this.total,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        paidAt: paidAt,
        deliveryStatus: deliveryStatus ?? this.deliveryStatus,
        deliveredAt: deliveredAt,
        cleared: cleared ?? this.cleared,
        clearedAt: clearedAt,
        driverWage: driverWage ?? this.driverWage,
        note: note ?? this.note,
        cancelled: cancelled ?? this.cancelled,
        verifyToken: verifyToken,
        statusLog: statusLog,
        createdBy: createdBy,
        createdAt: createdAt,
        items: items ?? this.items,
        statementId: identical(statementId, _unset) ? this.statementId : statementId as String?,
        driverPayoutId: driverPayoutId,
        demo: demo ?? this.demo,
      );
}

class DriverPayoutOrder {
  const DriverPayoutOrder({
    required this.id,
    required this.orderNo,
    required this.orderDate,
    required this.customerName,
    required this.trips,
    required this.amount,
  });
  final String id;
  final String orderNo;
  final String orderDate;
  final String customerName;
  final int trips;
  final double amount;
}

class DriverPayout {
  const DriverPayout({
    required this.id,
    required this.payoutNo,
    required this.driverId,
    required this.driverName,
    required this.total,
    required this.cashCollected,
    required this.method,
    required this.note,
    required this.createdBy,
    required this.createdAt,
    required this.orders,
  });
  final String id;
  final String payoutNo;
  final String driverId;
  final String driverName;

  /// ค่ารถ paid to the driver.
  final double total;

  /// COD money the driver handed over in this payout.
  final double cashCollected;

  /// 'cash' | 'transfer'
  final String method;
  final String note;
  final String? createdBy;
  final String createdAt;
  final List<DriverPayoutOrder> orders;
}

class Statement {
  const Statement({
    required this.id,
    required this.statementNo,
    required this.source,
    required this.customerId,
    required this.customer,
    required this.periodFrom,
    required this.periodTo,
    required this.total,
    required this.status,
    this.paymentMethod,
    this.clearedAt,
    this.verifyToken = '',
    this.note = '',
    this.createdBy,
    this.createdAt = '',
    this.orderIds = const [],
    this.demo = false,
  });

  final String id;
  final String statementNo;
  final OrderSource source;
  final String customerId;
  final CustomerSnapshot customer;
  final String periodFrom;
  final String periodTo;
  final double total;

  /// 'open' | 'cleared'
  final String status;

  /// 'cash' | 'transfer' | null
  final String? paymentMethod;
  final String? clearedAt;
  final String verifyToken;
  final String note;
  final String? createdBy;
  final String createdAt;
  final List<String> orderIds;
  final bool demo;

  bool get isCleared => status == 'cleared';

  factory Statement.fromRow(Map<String, dynamic> r) => Statement(
        id: _str(r['id']),
        statementNo: _str(r['statement_no']),
        source: OrderSource.parse(r['source']),
        customerId: _str(r['customer_id']),
        customer: CustomerSnapshot.fromJson(r['customer_snapshot']),
        periodFrom: _str(r['period_from']),
        periodTo: _str(r['period_to']),
        total: _num(r['total']),
        status: _str(r['status']),
        paymentMethod: r['payment_method'] as String?,
        clearedAt: r['cleared_at'] as String?,
        verifyToken: _str(r['verify_token']),
        note: _str(r['note']),
        createdBy: r['created_by'] as String?,
        createdAt: _str(r['created_at']),
        orderIds: (r['links'] is List)
            ? (r['links'] as List).whereType<Map>().map((l) => _str(l['order_id'])).toList()
            : const [],
        demo: r['demo_session'] != null,
      );
}

class CompanySettings {
  const CompanySettings({
    required this.nameTh,
    required this.nameEn,
    required this.address,
    required this.taxId,
    required this.phone,
  });
  final String nameTh;
  final String nameEn;
  final String address;
  final String taxId;
  final String phone;

  static const defaults = CompanySettings(
    nameTh: 'ห้างหุ้นส่วนจำกัด พีรสิทธิ์ วัสดุก่อสร้าง',
    nameEn: 'PIRASIT CONSTRUCTION MATERIALS LIMITED PARTNERSHIP',
    address: '132 หมู่ที่ 2 ตำบลวังแก้ว อำเภอวังเหนือ จังหวัดลำปาง 52140',
    taxId: '0523566002017',
    phone: '065-8124686',
  );

  factory CompanySettings.fromJson(Map<String, dynamic>? j) => CompanySettings(
        nameTh: (j?['nameTh'] as String?) ?? defaults.nameTh,
        nameEn: (j?['nameEn'] as String?) ?? defaults.nameEn,
        address: (j?['address'] as String?) ?? defaults.address,
        taxId: (j?['taxId'] as String?) ?? defaults.taxId,
        phone: (j?['phone'] as String?) ?? defaults.phone,
      );

  Map<String, dynamic> toJson() =>
      {'nameTh': nameTh, 'nameEn': nameEn, 'address': address, 'taxId': taxId, 'phone': phone};
}

class PaymentSettings {
  const PaymentSettings({
    this.promptPayId = '',
    this.bankText = '',
    this.bankName = '',
    this.bankAccountNo = '',
    this.bankAccountName = '',
    this.qrPayload = '',
  });
  final String promptPayId;

  /// Extra line printed in the payment part at the bottom of the bill.
  final String bankText;
  final String bankName;
  final String bankAccountNo;
  final String bankAccountName;

  /// Thai QR / PromptPay payload read from the shop's QR image (set on the web).
  final String qrPayload;

  factory PaymentSettings.fromJson(Map<String, dynamic>? j) => PaymentSettings(
        promptPayId: (j?['promptPayId'] as String?) ?? '',
        bankText: (j?['bankText'] as String?) ?? '',
        bankName: (j?['bankName'] as String?) ?? '',
        bankAccountNo: (j?['bankAccountNo'] as String?) ?? '',
        bankAccountName: (j?['bankAccountName'] as String?) ?? '',
        qrPayload: (j?['qrPayload'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'promptPayId': promptPayId,
        'bankText': bankText,
        'bankName': bankName,
        'bankAccountNo': bankAccountNo,
        'bankAccountName': bankAccountName,
        'qrPayload': qrPayload,
      };
}

class AppSettings {
  const AppSettings({
    this.company = CompanySettings.defaults,
    this.delivery = DeliverySettings.defaults,
    this.payment = const PaymentSettings(),
  });
  final CompanySettings company;
  final DeliverySettings delivery;
  final PaymentSettings payment;
}

/// Same "pay with" choice the web offers when marking an order paid.
enum PayNowMethod {
  cash('เงินสด'),
  transfer('โอนเงิน'),
  cod('เก็บปลายทาง');

  const PayNowMethod(this.label);
  final String label;
}
