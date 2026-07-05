/// สถานะเครือข่าย / เซิร์ฟเวอร์ / กิจกรรมซิงค์ — ใช้ร่วมทั้งแอป
enum NetworkLinkState { unknown, linked, unlink }

enum ServerReachState { unknown, online, offline }

enum SyncActivity { idle, syncing, syncedFlash }

enum SyncFailureReason { retryExhausted, conflict, serverError }

class AppSyncSnapshot {
  const AppSyncSnapshot({
    this.network = NetworkLinkState.unknown,
    this.server = ServerReachState.unknown,
    this.activity = SyncActivity.idle,
    this.pendingCount = 0,
    this.failedCount = 0,
  });

  final NetworkLinkState network;
  final ServerReachState server;
  final SyncActivity activity;
  final int pendingCount;
  final int failedCount;

  bool get isNetworkLinked =>
      network == NetworkLinkState.linked || network == NetworkLinkState.unknown;

  bool get isServerOnline =>
      server == ServerReachState.online || server == ServerReachState.unknown;

  /// พร้อมใช้งานออนไลน์ (มีเน็ต + เซิร์ฟเวอร์ตอบ)
  bool get isEffectivelyOnline =>
      network != NetworkLinkState.unlink && server != ServerReachState.offline;

  bool get isSyncing => activity == SyncActivity.syncing || uploadInFlightHint;

  /// ใช้ร่วมกับ uploadInFlight จาก service
  static bool uploadInFlightHint = false;

  bool get showBanner => bannerMessage.isNotEmpty;

  String get bannerMessage {
    if (activity == SyncActivity.syncedFlash) {
      return 'ซิงก์สำเร็จแล้ว';
    }
    if (activity == SyncActivity.syncing || uploadInFlightHint) {
      if (pendingCount > 0) {
        return 'กำลังอัปโหลด $pendingCount รายการ…';
      }
      return 'กำลังตรวจสอบการเชื่อมต่อ…';
    }
    if (failedCount > 0) {
      return 'มี $failedCount รายการซิงก์ไม่สำเร็จ — แตะเพื่อจัดการ';
    }
    if (network == NetworkLinkState.unlink) {
      return 'ไม่มีสัญญาณอินเทอร์เน็ต — ทำงานออฟไลน์';
    }
    if (server == ServerReachState.offline) {
      return 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ — กำลังลองใหม่';
    }
    if (pendingCount > 0) {
      return 'รออัปโหลด $pendingCount รายการ';
    }
    return '';
  }

  String get headerStatusLabel {
    if (activity == SyncActivity.syncing || uploadInFlightHint) {
      return 'กำลังซิงก์…';
    }
    if (network == NetworkLinkState.unlink) {
      return 'ไม่มีเน็ต';
    }
    if (server == ServerReachState.offline) {
      return 'เซิร์ฟเวอร์ไม่ตอบ';
    }
    if (pendingCount > 0) {
      return 'รออัปโหลด $pendingCount';
    }
    return 'ออนไลน์';
  }

  AppSyncSnapshot copyWith({
    NetworkLinkState? network,
    ServerReachState? server,
    SyncActivity? activity,
    int? pendingCount,
    int? failedCount,
  }) {
    return AppSyncSnapshot(
      network: network ?? this.network,
      server: server ?? this.server,
      activity: activity ?? this.activity,
      pendingCount: pendingCount ?? this.pendingCount,
      failedCount: failedCount ?? this.failedCount,
    );
  }
}

/// รายการที่ซิงก์ล้มเหลว — แสดงใน bottom sheet
class FailedSyncItem {
  const FailedSyncItem({
    required this.key,
    required this.label,
    required this.date,
    required this.reason,
    required this.failedAtMs,
    required this.isDelete,
  });

  final String key;
  final String label;
  final String date;
  final SyncFailureReason reason;
  final int failedAtMs;
  final bool isDelete;

  String get reasonLabel => switch (reason) {
        SyncFailureReason.conflict => 'ข้อมูลชนกับเซิร์ฟเวอร์',
        SyncFailureReason.retryExhausted => 'ลองซ้ำครบแล้ว',
        SyncFailureReason.serverError => 'เซิร์ฟเวอร์ตอบผิดพลาด',
      };
}
