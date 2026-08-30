import '../models/app_transaction.dart';

/// หมวดเมนูบันทึกประจำวัน «บำรุงรักษา»
const String kMaintenanceModuleCategory = 'บำรุงรักษา';

/// ค่า `category` ในตาราง transactions (สอดคล้องเว็บ / รายงาน)
const String kMaintenanceTxCategory = 'Maintenance';

/// ประเภทงานบำรุงรักษา (`subCategory`)
const String kMaintenanceTypeOil = 'เปลี่ยนถ่ายน้ำมันเครื่อง';
const String kMaintenanceTypeRepair = 'ซ่อม/ดูแลรักษา';
const String kMaintenanceTypeParts = 'เปลี่ยนอะไหล่';

const List<String> kMaintenanceTypes = [
  kMaintenanceTypeRepair,
  kMaintenanceTypeOil,
  kMaintenanceTypeParts,
];

/// กลุ่มเครื่องจักร/ยานพาหนะในเมนูบำรุงรักษา
enum MaintenanceAssetGroup {
  macro,
  car,
  motorcycle,
  generator,
  sandSieve,
}

extension MaintenanceAssetGroupX on MaintenanceAssetGroup {
  String get code {
    switch (this) {
      case MaintenanceAssetGroup.macro:
        return 'macro';
      case MaintenanceAssetGroup.car:
        return 'car';
      case MaintenanceAssetGroup.motorcycle:
        return 'motorcycle';
      case MaintenanceAssetGroup.generator:
        return 'generator';
      case MaintenanceAssetGroup.sandSieve:
        return 'sand_sieve';
    }
  }

  String get label {
    switch (this) {
      case MaintenanceAssetGroup.macro:
        return 'รถแม็คโคร';
      case MaintenanceAssetGroup.car:
        return 'รถยนต์';
      case MaintenanceAssetGroup.motorcycle:
        return 'รถจักรยานยนต์';
      case MaintenanceAssetGroup.generator:
        return 'เครื่องปั่นไฟ';
      case MaintenanceAssetGroup.sandSieve:
        return 'เครื่องร่อนทราย';
    }
  }

  static MaintenanceAssetGroup? tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'macro':
        return MaintenanceAssetGroup.macro;
      case 'car':
        return MaintenanceAssetGroup.car;
      case 'motorcycle':
        return MaintenanceAssetGroup.motorcycle;
      case 'generator':
        return MaintenanceAssetGroup.generator;
      case 'sand_sieve':
      case 'sandsieve':
        return MaintenanceAssetGroup.sandSieve;
      default:
        return null;
    }
  }
}

/// รายการสินทรัพย์ต่อกลุ่ม — ใช้เป็น `vehicleId` เมื่อบันทึก
const Map<MaintenanceAssetGroup, List<String>> kMaintenanceAssetsByGroup = {
  MaintenanceAssetGroup.macro: [
    'รถแม็คโคร SK200-10 (พี่เดอะฮัก)',
    'รถแม็คโคร SK200-10 (พี่ยักษ์ใหญ่)',
    'รถแม็คโคร SK200-8 (น้องโกลเด้น)',
    'รถแม็คโคร SK200-10 (ไททัน)',
    'รถแม็คโคร พ่อหลวงพูล SDLG (E6210H)',
  ],
  MaintenanceAssetGroup.car: [
    'ไมตี้',
    'รถตาเปลื่ยน (ISUZU KB)',
  ],
  MaintenanceAssetGroup.motorcycle: [
    'Dream100 สีแดง',
    'Wave100 สีน้ำเงิน',
    'Dream110 สีดำ',
    'รถซาเล้งสีดำ',
    'รถซาเล้งสีน้ำเงิน',
  ],
  MaintenanceAssetGroup.generator: [
    'เครื่องปั่นไฟ 250KVA YC6MK',
    'เครื่องปั่นไฟดีเซล 7KW',
    'เครื่องปั่นไฟเบนซิน 5KW',
  ],
  MaintenanceAssetGroup.sandSieve: [
    'เครื่องร่อนทราย',
  ],
};

List<String> maintenanceAssetsFor(MaintenanceAssetGroup group) =>
    List<String>.unmodifiable(kMaintenanceAssetsByGroup[group] ?? const []);

List<String> get allMaintenanceAssets => [
      for (final g in MaintenanceAssetGroup.values)
        ...maintenanceAssetsFor(g),
    ];

MaintenanceAssetGroup? maintenanceGroupForAsset(String asset) {
  final name = asset.trim();
  if (name.isEmpty) return null;
  for (final g in MaintenanceAssetGroup.values) {
    if (maintenanceAssetsFor(g).contains(name)) return g;
  }
  return null;
}

bool isMaintenanceTransaction(AppTransaction t) =>
    t.category.trim() == kMaintenanceTxCategory;

String maintenanceDescription({
  required String type,
  required String detail,
}) {
  final d = detail.trim();
  if (d.isEmpty) return type.trim();
  return '${type.trim()}: $d';
}

/// ดึงรายละเอียดจาก description ที่บันทึกไว้ (ตัด prefix ประเภท)
String maintenanceDetailFromDescription(String description, String type) {
  var raw = description.trim();
  raw = raw.replaceAll(RegExp(r'\s*\(ผู้กรอก:[^)]+\)\s*$'), '').trim();
  final prefix = '${type.trim()}:';
  if (raw.startsWith(prefix)) {
    return raw.substring(prefix.length).trim();
  }
  if (raw == type.trim()) return '';
  return raw;
}
