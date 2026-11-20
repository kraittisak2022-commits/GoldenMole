/// สถานะของรถแม็คโคร 1 คันในหน้าบันทึกประจำวัน
enum MacroVehicleRowStatus {
  /// บันทึกลงฐานข้อมูลแล้วและข้อมูลครบ (คนขับ + งาน)
  saved,

  /// กรอกคนขับ + งานครบแล้ว รอกดบันทึก
  readyToSave,

  /// เลือกงานแล้วแต่ยังไม่ได้เลือกคนขับ
  missingDriver,

  /// ยังไม่ได้เลือกงานวันนี้ (ถือว่าไม่ได้ทำงาน / ไม่บันทึก)
  idle,
}

/// ตัวกรองแสดงผลรถแม็คโครบนหน้าบันทึก
enum MacroFleetFilter { all, working, idle }

MacroVehicleRowStatus resolveMacroVehicleRowStatus({
  required bool isSaved,
  required bool hasDriver,
  required bool hasWorkTags,
}) {
  if (!hasWorkTags) return MacroVehicleRowStatus.idle;
  if (!hasDriver) return MacroVehicleRowStatus.missingDriver;
  return isSaved
      ? MacroVehicleRowStatus.saved
      : MacroVehicleRowStatus.readyToSave;
}

bool matchesMacroFleetFilter(
  MacroVehicleRowStatus status,
  MacroFleetFilter filter,
) {
  return switch (filter) {
    MacroFleetFilter.all => true,
    MacroFleetFilter.working => status != MacroVehicleRowStatus.idle,
    MacroFleetFilter.idle => status == MacroVehicleRowStatus.idle,
  };
}

/// ภาพรวมรถแม็คโครทั้งหมดในวันนั้น
class MacroFleetOverview {
  const MacroFleetOverview({
    required this.totalCount,
    required this.activeCount,
    required this.savedCount,
    required this.idleCount,
    this.missingDriverCount = 0,
    this.clearedSavedCount = 0,
  });

  final int totalCount;
  final int activeCount;
  final int savedCount;
  final int idleCount;
  final int missingDriverCount;
  final int clearedSavedCount;

  double get activeRatio =>
      totalCount <= 0 ? 0.0 : (activeCount / totalCount).clamp(0.0, 1.0);
}

/// ข้อความบนปุ่มบันทึกหลัก — สะท้อนจำนวนคันที่จะบันทึก/ลบแบบเรียลไทม์
String buildMacroSaveButtonLabel({
  required bool saving,
  required int completeCount,
  required int clearedSavedCount,
  required bool compact,
}) {
  if (saving) return 'กำลังบันทึก...';
  if (completeCount > 0 && clearedSavedCount > 0) {
    return compact
        ? 'บันทึก $completeCount · ลบที่ล้าง $clearedSavedCount'
        : 'บันทึก $completeCount คัน · ลบที่ล้าง $clearedSavedCount คัน';
  }
  if (completeCount > 0) {
    return 'บันทึกการใช้รถ · $completeCount คัน';
  }
  if (clearedSavedCount > 0) {
    return 'ลบรายการที่ล้าง ($clearedSavedCount คัน)';
  }
  return compact ? 'บันทึกแม็คโคร' : 'บันทึกการใช้รถแม็คโคร';
}
