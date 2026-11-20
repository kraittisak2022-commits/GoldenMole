import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_transaction.dart';
import '../models/employee.dart';
import '../theme/daily_palette.dart';
import '../utils/app_haptics.dart';
import '../utils/count_record_vehicle_defaults.dart';
import '../utils/daily_module_transactions.dart';
import '../utils/drum_trip_summary.dart';

/// ชุดสีประจำคันสำหรับรถดรัม — แยกคันได้ชัดเจนทั้ง Light และ Dark mode
@immutable
class VehicleTripAccent {
  const VehicleTripAccent({
    required this.name,
    required this.primary,
    required this.darkPrimary,
    required this.softLight,
    required this.softDark,
    required this.borderLight,
    required this.borderDark,
  });

  final String name;
  final Color primary;
  final Color darkPrimary;
  final Color softLight;
  final Color softDark;
  final Color borderLight;
  final Color borderDark;

  Color resolvePrimary(bool isDark) => isDark ? darkPrimary : primary;
  Color resolveSoft(bool isDark) => isDark ? softDark : softLight;
  Color resolveBorder(bool isDark) => isDark ? borderDark : borderLight;
}

/// 8 โทนสีชัดเจนสำหรับรถดรัมแต่ละคัน (ไม่ซ้ำกันในกองรถปกติ)
const List<VehicleTripAccent> kVehicleTripAccentPalette = [
  VehicleTripAccent(
    name: 'sky',
    primary: Color(0xFF0284C7),
    darkPrimary: Color(0xFF38BDF8),
    softLight: Color(0xFFF0F9FF),
    softDark: Color(0xFF0C2536),
    borderLight: Color(0xFFBAE6FD),
    borderDark: Color(0xFF1A4B66),
  ),
  VehicleTripAccent(
    name: 'emerald',
    primary: Color(0xFF059669),
    darkPrimary: Color(0xFF34D399),
    softLight: Color(0xFFECFDF5),
    softDark: Color(0xFF0A2A22),
    borderLight: Color(0xFFA7F3D0),
    borderDark: Color(0xFF165645),
  ),
  VehicleTripAccent(
    name: 'amber',
    primary: Color(0xFFD97706),
    darkPrimary: Color(0xFFFBBF24),
    softLight: Color(0xFFFFFBEB),
    softDark: Color(0xFF2E200B),
    borderLight: Color(0xFFFDE68A),
    borderDark: Color(0xFF634414),
  ),
  VehicleTripAccent(
    name: 'violet',
    primary: Color(0xFF7C3AED),
    darkPrimary: Color(0xFFA78BFA),
    softLight: Color(0xFFF5F3FF),
    softDark: Color(0xFF1E1538),
    borderLight: Color(0xFFDDD6FE),
    borderDark: Color(0xFF45317A),
  ),
  VehicleTripAccent(
    name: 'rose',
    primary: Color(0xFFE11D48),
    darkPrimary: Color(0xFFFB7185),
    softLight: Color(0xFFFFF1F2),
    softDark: Color(0xFF33101B),
    borderLight: Color(0xFFFECDD3),
    borderDark: Color(0xFF6B2138),
  ),
  VehicleTripAccent(
    name: 'teal',
    primary: Color(0xFF0D9488),
    darkPrimary: Color(0xFF2DD4BF),
    softLight: Color(0xFFF0FDFA),
    softDark: Color(0xFF0A2928),
    borderLight: Color(0xFF99F6E4),
    borderDark: Color(0xFF185452),
  ),
  VehicleTripAccent(
    name: 'orange',
    primary: Color(0xFFEA580C),
    darkPrimary: Color(0xFFFB923C),
    softLight: Color(0xFFFFF7ED),
    softDark: Color(0xFF33180A),
    borderLight: Color(0xFFFED7AA),
    borderDark: Color(0xFF6B3215),
  ),
  VehicleTripAccent(
    name: 'indigo',
    primary: Color(0xFF4F46E5),
    darkPrimary: Color(0xFF818CF8),
    softLight: Color(0xFFEEF2FF),
    softDark: Color(0xFF171B3D),
    borderLight: Color(0xFFC7D2FE),
    borderDark: Color(0xFF343C7D),
  ),
];

/// คืนสีประจำคันแบบคงที่ตามลำดับรถในกองรถ (หรือแฮชชื่อรถหากไม่อยู่ในรายการ)
VehicleTripAccent vehicleTripAccentForCar(
  String carName,
  List<String> allCars,
) {
  final trimmed = carName.trim();
  if (trimmed.isEmpty) return kVehicleTripAccentPalette.first;
  for (var i = 0; i < allCars.length; i++) {
    if (vehicleIdsLikelyMatch(allCars[i], trimmed)) {
      return kVehicleTripAccentPalette[i % kVehicleTripAccentPalette.length];
    }
  }
  var hash = 0;
  for (final code in trimmed.codeUnits) {
    hash = (hash * 31 + code) & 0x7FFFFFFF;
  }
  return kVehicleTripAccentPalette[hash % kVehicleTripAccentPalette.length];
}

/// ป้ายเลขประจำคันแบบสั้น (เช่น เบอร์ 1 / #1 หรืออักษรย่อคัน)
String vehicleTripDisplayNumber(String carName, List<String> allCars) {
  final trimmed = carName.trim();
  if (trimmed.isEmpty) return '?';
  final digitMatch = RegExp(r'(\d+)').firstMatch(trimmed);
  if (digitMatch != null) return '#${digitMatch.group(1)}';
  for (var i = 0; i < allCars.length; i++) {
    if (vehicleIdsLikelyMatch(allCars[i], trimmed)) {
      return '#${i + 1}';
    }
  }
  return trimmed.characters.first;
}

/// แผง KPI สรุปภาพรวมประจำวันของรถดรัมและจำนวนเที่ยว
class VehicleTripOverviewHeader extends StatelessWidget {
  const VehicleTripOverviewHeader({
    super.key,
    required this.overview,
    required this.dateLabel,
  });

  final VehicleTripDayOverview overview;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ratio = overview.completionRatio;
    final complete =
        overview.fleetTotal > 0 && overview.savedVehicles >= overview.fleetTotal;

    final accentStart =
        isDark ? const Color(0xFF0C2A3A) : const Color(0xFF0A4D68);
    final accentEnd =
        isDark ? const Color(0xFF0E3C4D) : const Color(0xFF0D98A5);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentStart, accentEnd],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFF0A4D68))
                .withValues(alpha: isDark ? 0.35 : 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'สรุปรถดรัมประจำวัน',
                      style: GoogleFonts.kanit(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    Text(
                      dateLabel,
                      style: GoogleFonts.kanit(
                        color: Colors.white.withValues(alpha: 0.80),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: complete
                      ? const Color(0xFF10B981).withValues(alpha: 0.28)
                      : Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: complete
                        ? const Color(0xFF6EE7B7).withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  overview.fleetTotal > 0
                      ? 'บันทึก ${overview.savedVehicles}/${overview.fleetTotal} คัน'
                      : 'บันทึก ${overview.savedVehicles} คัน',
                  style: GoogleFonts.kanit(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _KpiTile(
                  label: 'รถที่วิ่ง',
                  value: '${overview.savedVehicles}',
                  unit: 'คัน',
                  sub: overview.countRecordSyncedVehicles > 0
                      ? 'นับสด ${overview.countRecordSyncedVehicles}'
                      : (overview.lumpSumVehicles > 0
                          ? 'เหมา ${overview.lumpSumVehicles}'
                          : 'บันทึกแล้ว'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiTile(
                  label: 'รวมเที่ยว',
                  value: formatVehicleTripNumber(overview.totalTrips),
                  unit: 'เที่ยว',
                  sub:
                      'เช้า ${formatVehicleTripNumber(overview.totalMorningTrips)} · บ่าย ${formatVehicleTripNumber(overview.totalAfternoonTrips)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiTile(
                  label: 'รวมปริมาณ',
                  value: formatVehicleTripNumber(overview.totalCubic),
                  unit: 'คิว',
                  sub: overview.totalTrips > 0
                      ? 'เฉลี่ย ${formatVehicleTripNumber(overview.totalCubic / overview.totalTrips)}/เที่ยว'
                      : 'รอข้อมูล',
                ),
              ),
            ],
          ),
          if (overview.fleetTotal > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 6,
                color: Colors.white.withValues(alpha: 0.18),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: ratio,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: complete
                          ? const Color(0xFF6EE7B7)
                          : const Color(0xFF7DD3FC),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.sub,
  });

  final String label;
  final String value;
  final String unit;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.kanit(
              color: Colors.white.withValues(alpha: 0.80),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: GoogleFonts.kanit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: GoogleFonts.kanit(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: GoogleFonts.kanit(
              color: Colors.white.withValues(alpha: 0.74),
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// การ์ดฟอร์มกรอกข้อมูลรถดรัม 1 คัน — ออกแบบให้กดไว 1-Tap ลดพิมพ์และไม่สับสนคัน
class VehicleTripEditorCard extends StatefulWidget {
  const VehicleTripEditorCard({
    super.key,
    required this.index,
    required this.totalRows,
    required this.vehicleId,
    required this.driverId,
    required this.billingMode,
    required this.morningText,
    required this.afternoonText,
    required this.cubicPerTripText,
    required this.lumpSumCubicText,
    required this.workType,
    required this.hourlyHoursText,
    required this.workDetailsController,
    required this.allCars,
    required this.savedCarNames,
    required this.otherDraftCarNames,
    required this.drivers,
    required this.defaultDriverId,
    required this.status,
    required this.isEditingSaved,
    required this.isCountRecordSynced,
    required this.workDetailSuggestions,
    required this.onSelectVehicle,
    required this.onSelectDriver,
    required this.onSelectBillingMode,
    required this.onStepMorning,
    required this.onTapMorningPad,
    required this.onStepAfternoon,
    required this.onTapAfternoonPad,
    required this.onSelectCubicPreset,
    required this.onTapCubicPad,
    required this.onTapLumpSumPad,
    required this.onSelectWorkType,
    required this.onSelectHourlyPreset,
    required this.onTapHourlyPad,
    required this.onToggleQuickPhrase,
    required this.onWorkDetailsChanged,
    this.onRemoveRow,
    this.onDeleteSavedRecord,
  });

  final int index;
  final int totalRows;
  final String vehicleId;
  final String driverId;
  final String billingMode;
  final String morningText;
  final String afternoonText;
  final String cubicPerTripText;
  final String lumpSumCubicText;
  final String workType;
  final String hourlyHoursText;
  final TextEditingController workDetailsController;
  final List<String> allCars;
  final Set<String> savedCarNames;
  final Set<String> otherDraftCarNames;
  final List<Employee> drivers;
  final String? defaultDriverId;
  final VehicleTripRowStatus status;
  final bool isEditingSaved;
  final bool isCountRecordSynced;
  final List<String> workDetailSuggestions;

  final ValueChanged<String> onSelectVehicle;
  final ValueChanged<String> onSelectDriver;
  final ValueChanged<String> onSelectBillingMode;
  final ValueChanged<double> onStepMorning;
  final VoidCallback onTapMorningPad;
  final ValueChanged<double> onStepAfternoon;
  final VoidCallback onTapAfternoonPad;
  final ValueChanged<String> onSelectCubicPreset;
  final VoidCallback onTapCubicPad;
  final VoidCallback onTapLumpSumPad;
  final ValueChanged<String> onSelectWorkType;
  final ValueChanged<String> onSelectHourlyPreset;
  final VoidCallback onTapHourlyPad;
  final ValueChanged<String> onToggleQuickPhrase;
  final ValueChanged<String> onWorkDetailsChanged;
  final VoidCallback? onRemoveRow;
  final VoidCallback? onDeleteSavedRecord;

  @override
  State<VehicleTripEditorCard> createState() => _VehicleTripEditorCardState();
}

class _VehicleTripEditorCardState extends State<VehicleTripEditorCard> {
  static const List<String> _cubicPresets = ['3', '4', '5', '7', '10'];
  static const List<String> _hourlyPresets = ['2', '4', '6', '8'];
  static const List<String> _quickPhrases = [
    'ขนทรายล้าง',
    'ขนทรายถม',
    'ขนดิน',
    'ขนหิน',
  ];

  bool _cardExpanded = true;
  late bool _driverPickerExpanded;

  @override
  void initState() {
    super.initState();
    _driverPickerExpanded = widget.driverId.trim().isEmpty;
  }

  @override
  void didUpdateWidget(covariant VehicleTripEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // เมื่อเพิ่งเติมคนขับอัตโนมัติ (เช่น เลือกรถแล้วได้คนขับประจำคัน) ให้พับรายการคนขับอัตโนมัติ
    if (oldWidget.driverId.trim().isEmpty &&
        widget.driverId.trim().isNotEmpty) {
      _driverPickerExpanded = false;
    }
  }

  Employee? get _selectedDriver {
    final target = widget.driverId.trim();
    if (target.isEmpty) return null;
    for (final e in widget.drivers) {
      if (e.id == target) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = vehicleTripAccentForCar(widget.vehicleId, widget.allCars);
    final accentPrimary = accent.resolvePrimary(isDark);
    final accentSoft = accent.resolveSoft(isDark);
    final accentBorder = accent.resolveBorder(isDark);

    final morning = parseVehicleTripNumber(widget.morningText);
    final afternoon = parseVehicleTripNumber(widget.afternoonText);
    final totalTrips = morning + afternoon;
    final cubicPerTrip = parseVehicleTripNumber(widget.cubicPerTripText);
    final lumpSumCubic = parseVehicleTripNumber(widget.lumpSumCubicText);
    final isLumpSum = widget.billingMode == 'LumpSum';
    final totalCubic = isLumpSum ? lumpSumCubic : (totalTrips * cubicPerTrip);

    final selectedDriver = _selectedDriver;
    // ยึดตามสถานะ _driverPickerExpanded โดยตรง เพื่อให้ปุ่ม แสดง/ซ่อน ทำงานได้เสมอ
    final showDriverChips = _driverPickerExpanded;

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.vehicleId.trim().isNotEmpty ? accentBorder : c.hairline,
          width: widget.vehicleId.trim().isNotEmpty ? 1.3 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: c.shadowCard,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                  // ── ส่วนหัวการ์ด (แตะหรือกดปุ่ม ซ่อน/ขยาย ได้) ───────────────
                  InkWell(
                    onTap: () {
                      AppHaptics.tap();
                      setState(() => _cardExpanded = !_cardExpanded);
                    },
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
                      decoration: BoxDecoration(
                        color: widget.vehicleId.trim().isNotEmpty
                            ? accentSoft
                            : c.chipSurface,
                        border: Border(
                          bottom: BorderSide(
                            color: _cardExpanded
                                ? (widget.vehicleId.trim().isNotEmpty
                                    ? accentBorder.withValues(alpha: 0.7)
                                    : c.hairline)
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: widget.vehicleId.trim().isNotEmpty
                                  ? accentPrimary
                                  : c.inkMuted.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              widget.vehicleId.trim().isNotEmpty
                                  ? vehicleTripDisplayNumber(
                                      widget.vehicleId,
                                      widget.allCars,
                                    )
                                  : '${widget.index + 1}',
                              style: GoogleFonts.kanit(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.vehicleId.trim().isNotEmpty
                                      ? widget.vehicleId.trim()
                                      : 'รายการรถคันที่ ${widget.index + 1}',
                                  style: GoogleFonts.kanit(
                                    color: c.ink,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    height: 1.15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.isCountRecordSynced)
                                  Text(
                                    'เชื่อมข้อมูลจากแผงนับเที่ยวสด',
                                    style: GoogleFonts.kanit(
                                      color: accentPrimary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                else if (!_cardExpanded)
                                  Text(
                                    selectedDriver != null || totalTrips > 0 || totalCubic > 0
                                        ? '${selectedDriver != null ? driverDisplayLabel(selectedDriver) : 'ยังไม่เลือกคนขับ'} · ${formatVehicleTripNumber(totalTrips)} เที่ยว · ${formatVehicleTripNumber(totalCubic)} คิว'
                                        : 'ซ่อนอยู่ — แตะ "ขยาย" เพื่อกรอกข้อมูล',
                                    style: GoogleFonts.kanit(
                                      color: c.inkMuted,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          _StatusBadge(status: widget.status),
                          const SizedBox(width: 6),
                          // ปุ่ม ซ่อน / ขยาย การ์ดรายการรถ
                          InkWell(
                            key: ValueKey('drum_card_toggle_${widget.index}'),
                            borderRadius: BorderRadius.circular(9),
                            onTap: () {
                              AppHaptics.tap();
                              setState(() => _cardExpanded = !_cardExpanded);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: c.card.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: widget.vehicleId.trim().isNotEmpty
                                      ? accentBorder
                                      : c.hairline,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _cardExpanded ? 'ซ่อน' : 'ขยาย',
                                    style: GoogleFonts.kanit(
                                      color: widget.vehicleId.trim().isNotEmpty
                                          ? accentPrimary
                                          : c.inkSubtle,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 1),
                                  Icon(
                                    _cardExpanded
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                    size: 16,
                                    color: widget.vehicleId.trim().isNotEmpty
                                        ? accentPrimary
                                        : c.inkSubtle,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (widget.isEditingSaved &&
                              widget.onDeleteSavedRecord != null) ...[
                            const SizedBox(width: 2),
                            IconButton(
                              onPressed: widget.onDeleteSavedRecord,
                              tooltip: 'ลบรายการวันนี้',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: isDark
                                    ? const Color(0xFFFB7185)
                                    : const Color(0xFFE11D48),
                              ),
                            ),
                          ] else if (widget.totalRows > 1 &&
                              widget.onRemoveRow != null) ...[
                            const SizedBox(width: 2),
                            IconButton(
                              onPressed: widget.onRemoveRow,
                              tooltip: 'ลบการ์ดนี้',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.close_rounded,
                                size: 19,
                                color: c.inkMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // ── เนื้อหาฟอร์ม (ซ่อน/ขยายได้) ───────────────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _cardExpanded
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                        // 1) เลือกรถดรัมแบบ 1-Tap Chips
                        _SectionLabel(
                          icon: Icons.local_shipping_outlined,
                          title: 'เลือกรถดรัม',
                          trailing: widget.savedCarNames.isNotEmpty
                              ? '✓ = บันทึกแล้ววันนี้'
                              : null,
                        ),
                        const SizedBox(height: 8),
                        if (widget.allCars.isEmpty)
                          Text(
                            'ยังไม่มีรายชื่อรถดรัมในระบบ',
                            style: GoogleFonts.kanit(
                              color: c.inkMuted,
                              fontSize: 12.5,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: widget.allCars.map((car) {
                              final selected = vehicleIdsLikelyMatch(
                                widget.vehicleId,
                                car,
                              );
                              final carAccent = vehicleTripAccentForCar(
                                car,
                                widget.allCars,
                              );
                              final carColor = carAccent.resolvePrimary(isDark);
                              final isSaved = widget.savedCarNames.any(
                                (s) => vehicleIdsLikelyMatch(s, car),
                              );
                              final inOtherDraft = !selected &&
                                  widget.otherDraftCarNames.any(
                                    (s) => vehicleIdsLikelyMatch(s, car),
                                  );

                              return InkWell(
                                borderRadius: BorderRadius.circular(11),
                                onTap: inOtherDraft
                                    ? null
                                    : () {
                                        AppHaptics.tap();
                                        widget.onSelectVehicle(car);
                                      },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? carColor
                                        : (inOtherDraft
                                            ? c.chipSurface
                                                .withValues(alpha: 0.5)
                                            : c.chipSurface),
                                    borderRadius: BorderRadius.circular(11),
                                    border: Border.all(
                                      color: selected
                                          ? carColor
                                          : (isSaved
                                              ? c.statusComplete
                                                  .withValues(alpha: 0.45)
                                              : c.hairline),
                                      width: selected ? 1.4 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? Colors.white
                                              : carColor.withValues(
                                                  alpha:
                                                      inOtherDraft ? 0.35 : 1.0,
                                                ),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        car,
                                        style: GoogleFonts.kanit(
                                          color: selected
                                              ? Colors.white
                                              : (inOtherDraft
                                                  ? c.inkMuted
                                                      .withValues(alpha: 0.55)
                                                  : c.ink),
                                          fontSize: 12.5,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        ),
                                      ),
                                      if (isSaved) ...[
                                        const SizedBox(width: 5),
                                        Icon(
                                          Icons.check_circle_rounded,
                                          size: 14,
                                          color: selected
                                              ? Colors.white
                                              : c.statusComplete,
                                        ),
                                      ] else if (inOtherDraft) ...[
                                        const SizedBox(width: 4),
                                        Text(
                                          '(เลือกแล้ว)',
                                          style: GoogleFonts.kanit(
                                            color: c.inkMuted
                                                .withValues(alpha: 0.7),
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),

                        const SizedBox(height: 14),

                        // 2) คนขับรถดั๊ม — แถบสรุป 1-Tap + ปุ่ม แสดง/ซ่อน รายชื่อ
                        _SectionLabel(
                          icon: Icons.person_outline_rounded,
                          title: 'คนขับรถดั๊ม',
                          trailing: selectedDriver != null &&
                                  selectedDriver.id == widget.defaultDriverId
                              ? '★ ประจำคัน'
                              : null,
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          key: ValueKey('drum_driver_toggle_${widget.index}'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            AppHaptics.tap();
                            setState(() {
                              _driverPickerExpanded = !_driverPickerExpanded;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: selectedDriver != null
                                  ? accentSoft.withValues(alpha: 0.65)
                                  : c.chipSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selectedDriver != null
                                    ? accentBorder
                                    : c.hairline,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  selectedDriver != null
                                      ? Icons.badge_rounded
                                      : Icons.person_add_alt_1_rounded,
                                  size: 18,
                                  color: selectedDriver != null
                                      ? accentPrimary
                                      : c.inkMuted,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    selectedDriver != null
                                        ? driverDisplayLabel(selectedDriver)
                                        : 'แตะเพื่อเลือกคนขับรถดั๊ม',
                                    style: GoogleFonts.kanit(
                                      color: selectedDriver != null
                                          ? c.ink
                                          : c.inkMuted,
                                      fontSize: 14,
                                      fontWeight: selectedDriver != null
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  showDriverChips ? 'ซ่อน' : 'แสดง',
                                  style: GoogleFonts.kanit(
                                    color: accentPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  showDriverChips
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  size: 18,
                                  color: accentPrimary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: showDriverChips
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: widget.drivers.isEmpty
                                      ? Text(
                                          'ยังไม่พบพนักงานตำแหน่ง "คนขับรถ" — ตั้งค่าในเมนูพนักงาน',
                                          style: GoogleFonts.kanit(
                                            color: c.statusIncomplete,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        )
                                      : Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: widget.drivers.map((emp) {
                                            final selected =
                                                emp.id == widget.driverId;
                                            final isDefault =
                                                widget.defaultDriverId !=
                                                        null &&
                                                    emp.id ==
                                                        widget.defaultDriverId;
                                            return InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              onTap: () {
                                                AppHaptics.tap();
                                                widget.onSelectDriver(emp.id);
                                                setState(
                                                  () => _driverPickerExpanded =
                                                      false,
                                                );
                                              },
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: selected
                                                      ? accentPrimary
                                                      : c.chipSurface,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: selected
                                                        ? accentPrimary
                                                        : (isDefault
                                                            ? accentBorder
                                                            : c.hairline),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if (isDefault) ...[
                                                      Icon(
                                                        Icons.star_rounded,
                                                        size: 13,
                                                        color: selected
                                                            ? Colors
                                                                .amber.shade200
                                                            : const Color(
                                                                0xFFF59E0B,
                                                              ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                    ],
                                                    Text(
                                                      driverDisplayLabel(emp),
                                                      style: GoogleFonts.kanit(
                                                        color: selected
                                                            ? Colors.white
                                                            : c.ink,
                                                        fontSize: 12.5,
                                                        fontWeight: selected
                                                            ? FontWeight.w700
                                                            : FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                )
                              : const SizedBox.shrink(),
                        ),

                        const SizedBox(height: 15),

                        // 3) โซนจำนวนเที่ยว & คิดคิว
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: c.hairline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'จำนวนเที่ยวและปริมาณ',
                                      style: GoogleFonts.kanit(
                                        color: c.ink,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  _SegmentedMiniToggle(
                                    leftLabel: 'คิดเป็นเที่ยว',
                                    rightLabel: 'เหมา',
                                    isRightSelected: isLumpSum,
                                    accentColor: accentPrimary,
                                    onChanged: (right) {
                                      AppHaptics.tap();
                                      widget.onSelectBillingMode(
                                        right ? 'LumpSum' : 'PerTrip',
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _TripPeriodStepper(
                                      label: 'ช่วงเช้า',
                                      icon: Icons.wb_sunny_rounded,
                                      iconColor: const Color(0xFFF59E0B),
                                      valueText: morning > 0
                                          ? formatVehicleTripNumber(morning)
                                          : '0',
                                      hasValue: morning > 0,
                                      accentColor: accentPrimary,
                                      onDecrement: () {
                                        AppHaptics.tap();
                                        widget.onStepMorning(-1);
                                      },
                                      onIncrement: () {
                                        AppHaptics.confirm();
                                        widget.onStepMorning(1);
                                      },
                                      onTapValue: () {
                                        AppHaptics.tap();
                                        widget.onTapMorningPad();
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _TripPeriodStepper(
                                      label: 'ช่วงบ่าย',
                                      icon: Icons.wb_twilight_rounded,
                                      iconColor: const Color(0xFFEA580C),
                                      valueText: afternoon > 0
                                          ? formatVehicleTripNumber(afternoon)
                                          : '0',
                                      hasValue: afternoon > 0,
                                      accentColor: accentPrimary,
                                      onDecrement: () {
                                        AppHaptics.tap();
                                        widget.onStepAfternoon(-1);
                                      },
                                      onIncrement: () {
                                        AppHaptics.confirm();
                                        widget.onStepAfternoon(1);
                                      },
                                      onTapValue: () {
                                        AppHaptics.tap();
                                        widget.onTapAfternoonPad();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 11),
                              if (!isLumpSum) ...[
                                Row(
                                  children: [
                                    Text(
                                      'คิวต่อเที่ยว',
                                      style: GoogleFonts.kanit(
                                        color: c.inkSubtle,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () {
                                        AppHaptics.tap();
                                        widget.onTapCubicPad();
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        child: Text(
                                          cubicPerTrip > 0
                                              ? '${formatVehicleTripNumber(cubicPerTrip)} คิว/เที่ยว ✎'
                                              : 'พิมพ์เอง ✎',
                                          style: GoogleFonts.kanit(
                                            color: accentPrimary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 7),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _cubicPresets.map((preset) {
                                    final presetVal =
                                        double.tryParse(preset) ?? 0;
                                    final selected =
                                        (cubicPerTrip - presetVal).abs() < 1e-6;
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        AppHaptics.tap();
                                        widget.onSelectCubicPreset(preset);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? accentPrimary
                                              : c.card,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: selected
                                                ? accentPrimary
                                                : c.hairline,
                                          ),
                                        ),
                                        child: Text(
                                          '$preset คิว',
                                          style: GoogleFonts.kanit(
                                            color: selected
                                                ? Colors.white
                                                : c.ink,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ] else ...[
                                InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    AppHaptics.tap();
                                    widget.onTapLumpSumPad();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: c.card,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: lumpSumCubic > 0
                                            ? accentPrimary
                                            : c.hairline,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.inventory_2_outlined,
                                          size: 18,
                                          color: accentPrimary,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'รวมปริมาณเหมา',
                                          style: GoogleFonts.kanit(
                                            color: c.inkSubtle,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          lumpSumCubic > 0
                                              ? '${formatVehicleTripNumber(lumpSumCubic)} คิว'
                                              : 'แตะเพื่อกรอกคิว',
                                          style: GoogleFonts.kanit(
                                            color: lumpSumCubic > 0
                                                ? accentPrimary
                                                : c.inkMuted,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 11),
                              // แถบสูตรคำนวณคิวแบบ Real-time
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: accentSoft,
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(color: accentBorder),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        isLumpSum
                                            ? 'เหมา · รวม ${formatVehicleTripNumber(totalTrips)} เที่ยว'
                                            : '${formatVehicleTripNumber(totalTrips)} เที่ยว × ${formatVehicleTripNumber(cubicPerTrip)} คิว',
                                        style: GoogleFonts.kanit(
                                          color: c.inkSubtle,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '= ${formatVehicleTripNumber(totalCubic)} คิว',
                                      style: GoogleFonts.kanit(
                                        color: accentPrimary,
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // 4) กะการทำงาน
                        const _SectionLabel(
                          icon: Icons.schedule_rounded,
                          title: 'ประเภทวันทำงาน',
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _ShiftSegmentButton(
                                label: 'เต็มวัน',
                                selected: widget.workType == 'FullDay' ||
                                    (widget.workType != 'HalfDay' &&
                                        widget.workType != 'Hourly'),
                                accentColor: accentPrimary,
                                onTap: () {
                                  AppHaptics.tap();
                                  widget.onSelectWorkType('FullDay');
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _ShiftSegmentButton(
                                label: 'ครึ่งวัน',
                                selected: widget.workType == 'HalfDay',
                                accentColor: accentPrimary,
                                onTap: () {
                                  AppHaptics.tap();
                                  widget.onSelectWorkType('HalfDay');
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _ShiftSegmentButton(
                                label: 'รายชั่วโมง',
                                selected: widget.workType == 'Hourly',
                                accentColor: accentPrimary,
                                onTap: () {
                                  AppHaptics.tap();
                                  widget.onSelectWorkType('Hourly');
                                },
                              ),
                            ),
                          ],
                        ),
                        if (widget.workType == 'Hourly') ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _hourlyPresets.map((h) {
                                    final currentH = parseVehicleTripNumber(
                                      widget.hourlyHoursText,
                                    );
                                    final targetH = double.tryParse(h) ?? 0;
                                    final selected =
                                        (currentH - targetH).abs() < 1e-6;
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(9),
                                      onTap: () {
                                        AppHaptics.tap();
                                        widget.onSelectHourlyPreset(h);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 11,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? accentPrimary
                                              : c.chipSurface,
                                          borderRadius:
                                              BorderRadius.circular(9),
                                          border: Border.all(
                                            color: selected
                                                ? accentPrimary
                                                : c.hairline,
                                          ),
                                        ),
                                        child: Text(
                                          '$h ชม.',
                                          style: GoogleFonts.kanit(
                                            color: selected
                                                ? Colors.white
                                                : c.ink,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                borderRadius: BorderRadius.circular(9),
                                onTap: () {
                                  AppHaptics.tap();
                                  widget.onTapHourlyPad();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentSoft,
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(color: accentBorder),
                                  ),
                                  child: Text(
                                    widget.hourlyHoursText.trim().isNotEmpty
                                        ? '${widget.hourlyHoursText.trim()} ชม. ✎'
                                        : 'ระบุ ชม. ✎',
                                    style: GoogleFonts.kanit(
                                      color: accentPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 14),

                        // 5) รายละเอียดงาน + วลีด่วน
                        const _SectionLabel(
                          icon: Icons.notes_rounded,
                          title: 'รายละเอียดงาน / จุดลงของ (ถ้ามี)',
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ..._quickPhrases,
                            ...widget.workDetailSuggestions
                                .where((s) => !_quickPhrases.contains(s))
                                .take(4),
                          ].map((phrase) {
                            final active = containsVehicleTripWorkPhrase(
                              widget.workDetailsController.text,
                              phrase,
                            );
                            return InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () {
                                AppHaptics.tap();
                                widget.onToggleQuickPhrase(phrase);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: active ? accentSoft : c.chipSurface,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: active ? accentPrimary : c.hairline,
                                  ),
                                ),
                                child: Text(
                                  active ? '✓ $phrase' : '+ $phrase',
                                  style: GoogleFonts.kanit(
                                    color: active ? accentPrimary : c.inkSubtle,
                                    fontSize: 11.5,
                                    fontWeight: active
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: widget.workDetailsController,
                          onChanged: widget.onWorkDetailsChanged,
                          minLines: 1,
                          maxLines: 2,
                          style: GoogleFonts.kanit(
                            color: c.ink,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: 'เช่น ขนทรายล้างลงบ่อ 2, วิ่งหน้างาน A',
                            hintStyle: GoogleFonts.kanit(
                              color: c.inkMuted,
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: c.surface,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: c.hairline),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: accentPrimary,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          // แถบสีประจำคันด้านซ้าย 6px (ใช้ Positioned เพื่อไม่ชนกับ AnimatedSize)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 6,
            child: ColoredBox(
              color: widget.vehicleId.trim().isNotEmpty
                  ? accentPrimary
                  : c.hairline,
            ),
          ),
        ],
      ),
    );
  }
}

/// การ์ดสรุปรายการรถดรัมที่บันทึกแล้วของวัน — แยกสีประจำคัน กดแก้ไข/ลบได้ทันที
class VehicleTripSavedCard extends StatelessWidget {
  const VehicleTripSavedCard({
    super.key,
    required this.transaction,
    required this.driverName,
    required this.allCars,
    required this.isBeingEdited,
    required this.onEdit,
    required this.onDelete,
  });

  final AppTransaction transaction;
  final String driverName;
  final List<String> allCars;
  final bool isBeingEdited;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vehicleLabel = transactionVehicleLabel(transaction);
    final accent = vehicleTripAccentForCar(vehicleLabel, allCars);
    final accentPrimary = accent.resolvePrimary(isDark);
    final accentSoft = accent.resolveSoft(isDark);
    final accentBorder = accent.resolveBorder(isDark);

    final split = vehicleTripPeriodSplit(transaction);
    final totalTrips = (split.morning + split.afternoon) > 0
        ? (split.morning + split.afternoon)
        : (transaction.tripCount ?? transaction.perCarTrips ?? 0);
    final isLumpSum = (transaction.tripBillingMode ?? '').trim() == 'LumpSum';
    final totalCubic = transaction.totalCubic ??
        transaction.perCarCubic ??
        (totalTrips * (transaction.cubicPerTrip ?? 0));
    final syncedFromCount = isCountRecordVehicleTrip(transaction);

    final shiftLabel = switch (transaction.workType) {
      'HalfDay' => 'ครึ่งวัน',
      'Hourly' => 'รายชั่วโมง',
      _ => 'เต็มวัน',
    };

    final details = (transaction.workDetails ?? '').trim();

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBeingEdited ? accentPrimary : c.hairline,
          width: isBeingEdited ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: c.shadowCard,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: accentPrimary),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accentSoft,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: accentBorder),
                          ),
                          child: Text(
                            vehicleTripDisplayNumber(vehicleLabel, allCars),
                            style: GoogleFonts.kanit(
                              color: accentPrimary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vehicleLabel.isEmpty ? 'ไม่ระบุรถ' : vehicleLabel,
                                style: GoogleFonts.kanit(
                                  color: c.ink,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${driverName.isEmpty ? 'ไม่ระบุคนขับ' : driverName} · $shiftLabel${isLumpSum ? ' · เหมา' : ''}',
                                style: GoogleFonts.kanit(
                                  color: c.inkMuted,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            AppHaptics.tap();
                            onEdit();
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: accentSoft,
                            foregroundColor: accentPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                          icon: const Icon(Icons.edit_rounded, size: 14),
                          label: Text(
                            isBeingEdited ? 'กำลังแก้' : 'แก้ไข',
                            style: GoogleFonts.kanit(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            AppHaptics.warn();
                            onDelete();
                          },
                          tooltip: 'ลบรายการ',
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: c.inkMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MetricPill(
                          label: 'เช้า',
                          value: formatVehicleTripNumber(split.morning),
                          color: const Color(0xFFF59E0B),
                        ),
                        _MetricPill(
                          label: 'บ่าย',
                          value: formatVehicleTripNumber(split.afternoon),
                          color: const Color(0xFFEA580C),
                        ),
                        _MetricPill(
                          label: 'รวม',
                          value: '${formatVehicleTripNumber(totalTrips)} เที่ยว',
                          color: accentPrimary,
                          emphasized: true,
                        ),
                        _MetricPill(
                          label: 'ปริมาณ',
                          value: '${formatVehicleTripNumber(totalCubic)} คิว',
                          color: c.statusComplete,
                          emphasized: true,
                        ),
                        if (syncedFromCount)
                          _MetricPill(
                            label: 'นับสด',
                            value: 'ซิงก์',
                            color: c.brand,
                          ),
                      ],
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        details,
                        style: GoogleFonts.kanit(
                          color: c.inkSubtle,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = DailyPalette.of(context);
    return Row(
      children: [
        Icon(icon, size: 15, color: c.inkMuted),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.kanit(
              color: c.inkSubtle,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: GoogleFonts.kanit(
              color: c.inkMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final VehicleTripRowStatus status;

  @override
  Widget build(BuildContext context) {
    final c = DailyPalette.of(context);
    final (label, color) = switch (status) {
      VehicleTripRowStatus.empty => ('รอเลือก', c.statusPending),
      VehicleTripRowStatus.incomplete => ('กรอกไม่ครบ', c.statusIncomplete),
      VehicleTripRowStatus.ready => ('พร้อมบันทึก', c.statusComplete),
      VehicleTripRowStatus.editing => ('แก้ไข', c.brand),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.kanit(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SegmentedMiniToggle extends StatelessWidget {
  const _SegmentedMiniToggle({
    required this.leftLabel,
    required this.rightLabel,
    required this.isRightSelected,
    required this.accentColor,
    required this.onChanged,
  });

  final String leftLabel;
  final String rightLabel;
  final bool isRightSelected;
  final Color accentColor;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = DailyPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: c.chipSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _miniTab(
            label: leftLabel,
            selected: !isRightSelected,
            accentColor: accentColor,
            inkMuted: c.inkMuted,
            onTap: () => onChanged(false),
          ),
          _miniTab(
            label: rightLabel,
            selected: isRightSelected,
            accentColor: accentColor,
            inkMuted: c.inkMuted,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _miniTab({
    required String label,
    required bool selected,
    required Color accentColor,
    required Color inkMuted,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.kanit(
            color: selected ? Colors.white : inkMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _TripPeriodStepper extends StatelessWidget {
  const _TripPeriodStepper({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.valueText,
    required this.hasValue,
    required this.accentColor,
    required this.onDecrement,
    required this.onIncrement,
    required this.onTapValue,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final String valueText;
  final bool hasValue;
  final Color accentColor;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onTapValue;

  @override
  Widget build(BuildContext context) {
    final c = DailyPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: hasValue ? accentColor.withValues(alpha: 0.45) : c.hairline,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.kanit(
                  color: c.inkSubtle,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StepperCircleBtn(
                icon: Icons.remove_rounded,
                backgroundColor: c.chipSurface,
                foregroundColor: c.ink,
                onTap: onDecrement,
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onTapValue,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        valueText,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.kanit(
                          color: hasValue ? accentColor : c.inkMuted,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _StepperCircleBtn(
                icon: Icons.add_rounded,
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                onTap: onIncrement,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperCircleBtn extends StatelessWidget {
  const _StepperCircleBtn({
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 18, color: foregroundColor),
        ),
      ),
    );
  }
}

class _ShiftSegmentButton extends StatelessWidget {
  const _ShiftSegmentButton({
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = DailyPalette.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accentColor : c.chipSurface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? accentColor : c.hairline,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.kanit(
            color: selected ? Colors.white : c.inkSubtle,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.color,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final c = DailyPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: emphasized ? color.withValues(alpha: 0.13) : c.chipSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: emphasized ? color.withValues(alpha: 0.35) : c.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: GoogleFonts.kanit(
              color: c.inkMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.kanit(
              color: emphasized ? color : c.ink,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
