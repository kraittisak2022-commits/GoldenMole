import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/app_haptics.dart';

/// เปิด dialog เลือกเวลา 24 ชม. แบบสองคอลัมน์ (ชั่วโมง | นาที)
Future<TimeOfDay?> showFuelTimePickerDialog(
  BuildContext context, {
  TimeOfDay? initial,
}) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (ctx) => _FuelTimePickerDialog(
      initial: initial ?? TimeOfDay.now(),
    ),
  );
}

class _FuelTimePickerDialog extends StatefulWidget {
  const _FuelTimePickerDialog({required this.initial});

  final TimeOfDay initial;

  @override
  State<_FuelTimePickerDialog> createState() => _FuelTimePickerDialogState();
}

class _FuelTimePickerDialogState extends State<_FuelTimePickerDialog> {
  static const _accent = Color(0xFF1565C0);
  static const _ink = Color(0xFF1A2433);
  static const _muted = Color(0xFF64748B);

  static const _hourPeriod = 24;
  static const _minutePeriod = 60;
  static const _loopCopies = 40;

  static const _hourLoopSize = _hourPeriod * _loopCopies;
  static const _minuteLoopSize = _minutePeriod * _loopCopies;

  late int _hour;
  late int _minute;
  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;

  /// ตำแหน่งเริ่มกลางลูป + ค่าตั้งต้น (หาร period ลงตัว)
  static int _loopInitialItem(int loopSize, int period, int value) {
    final mid = (loopSize ~/ 2) ~/ period * period;
    return mid + value.clamp(0, period - 1);
  }

  @override
  void initState() {
    super.initState();
    _hour = widget.initial.hour.clamp(0, 23);
    _minute = widget.initial.minute.clamp(0, 59);
    _hourCtrl = FixedExtentScrollController(
      initialItem: _loopInitialItem(_hourLoopSize, _hourPeriod, _hour),
    );
    _minuteCtrl = FixedExtentScrollController(
      initialItem: _loopInitialItem(_minuteLoopSize, _minutePeriod, _minute),
    );
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  String get _preview {
    final hh = _hour.toString().padLeft(2, '0');
    final mm = _minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Widget _columnLabel(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: GoogleFonts.kanit(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: _muted,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required int period,
    required int selectedValue,
    required ValueChanged<int> onSelectedValue,
  }) {
    return CupertinoPicker.builder(
      scrollController: controller,
      itemExtent: 68,
      magnification: 1.08,
      squeeze: 1.05,
      useMagnifier: true,
      selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
        background: _accent.withValues(alpha: 0.10),
      ),
      onSelectedItemChanged: (i) {
        AppHaptics.tap();
        onSelectedValue(i % period);
      },
      childCount: itemCount,
      itemBuilder: (context, index) {
        final value = index % period;
        final selected = value == selectedValue;
        final label = value.toString().padLeft(2, '0');
        return Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 120),
            style: GoogleFonts.kanit(
              fontSize: selected ? 42 : 32,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? _ink : _muted.withValues(alpha: 0.5),
              height: 1,
            ),
            child: Text(label),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final dialogW = (screenW - 32).clamp(320.0, 440.0);

    return AlertDialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        'เลือกเวลา',
        textAlign: TextAlign.center,
        style: GoogleFonts.kanit(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: _ink,
        ),
      ),
      content: SizedBox(
        width: dialogW,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE3F2FD), Color(0xFFF5FAFF)],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFBBDEFB)),
              ),
              child: Column(
                children: [
                  Text(
                    'เวลาที่เลือก',
                    style: GoogleFonts.kanit(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _preview,
                    style: GoogleFonts.kanit(
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      color: _accent,
                      height: 1.05,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _columnLabel('ชั่วโมง')),
                const SizedBox(width: 28),
                Expanded(child: _columnLabel('นาที')),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  Expanded(
                    child: ColoredBox(
                      color: _accent.withValues(alpha: 0.04),
                      child: _wheel(
                        controller: _hourCtrl,
                        itemCount: _hourLoopSize,
                        period: _hourPeriod,
                        selectedValue: _hour,
                        onSelectedValue: (v) => setState(() => _hour = v),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    child: Center(
                      child: Text(
                        ':',
                        style: GoogleFonts.kanit(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: _accent,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _wheel(
                      controller: _minuteCtrl,
                      itemCount: _minuteLoopSize,
                      period: _minutePeriod,
                      selectedValue: _minute,
                      onSelectedValue: (v) => setState(() => _minute = v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'เลื่อนเลือกชั่วโมงและนาที (24 ชม.)',
              style: GoogleFonts.kanit(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _muted,
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(120, 52),
          ),
          onPressed: () => Navigator.pop(context),
          child: Text(
            'ยกเลิก',
            style: GoogleFonts.kanit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _muted,
            ),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            minimumSize: const Size(140, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () {
            AppHaptics.confirm();
            Navigator.pop(
              context,
              TimeOfDay(hour: _hour, minute: _minute),
            );
          },
          child: Text(
            'ยืนยัน',
            style: GoogleFonts.kanit(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
