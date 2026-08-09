import 'dart:async';

import 'package:flutter/material.dart';

import '../services/count_record_tutorial_store.dart';

class _TutorialStep {
  const _TutorialStep({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.body,
    this.bullets = const [],
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String body;
  final List<String> bullets;
}

const _kCountRecordTutorialSteps = <_TutorialStep>[
    _TutorialStep(
      icon: Icons.timer_outlined,
      iconColor: Color(0xFF1565C0),
      iconBg: Color(0xFFE3F2FD),
      title: 'ยินดีต้อนรับ',
      body:
          'หน้านี้ใช้บันทึกเที่ยวรถและนับรอบร่อนทรายแบบกดเดียว '
          'ข้อมูลจะไปแสดงในเมนูอื่นของวันนั้นโดยอัตโนมัติ',
      bullets: [
        'การ์ดบน = จำนวนเที่ยวรถ',
        'การ์ดล่าง = การร่อนทราย',
      ],
    ),
    _TutorialStep(
      icon: Icons.fire_truck_outlined,
      iconColor: Color(0xFF1565C0),
      iconBg: Color(0xFFE3F2FD),
      title: 'บันทึกเที่ยวรถ',
      body: 'เริ่มจากเลือกรถและคนขับ แล้วแตะการ์ดรถเพื่อบันทึก +1 เที่ยว',
      bullets: [
        'แตะการ์ด «เพิ่มรถและคนขับ» เพื่อเลือกรถครั้งแรก',
        'แตะการ์ดรถอีกครั้งทุกครั้งที่วิ่งครบ 1 เที่ยว',
        'รอ 3 วินาทีก่อนกดบันทึกเที่ยวถัดไป (กันบันทึกซ้ำ)',
      ],
    ),
    _TutorialStep(
      icon: Icons.swipe_rounded,
      iconColor: Color(0xFF00695C),
      iconBg: Color(0xFFE0F2F1),
      title: 'ท่าทางบนการ์ดรถ',
      body: 'ใช้ปัดนิ้วและกดค้างเพื่อจัดการข้อมูลได้เร็ว',
      bullets: [
        'ปัดซ้าย = ลบรถออกจากรายการวันนี้',
        'ปัดขวา = แก้ไขคนขับ / แจ้งรถเสีย / ปรับสถานะ',
        'กดค้าง 3 วินาที = ลบเที่ยวล่าสุด',
      ],
    ),
    _TutorialStep(
      icon: Icons.add_circle_outline_rounded,
      iconColor: Color(0xFF1565C0),
      iconBg: Color(0xFFE3F2FD),
      title: 'เพิ่มรถหลายคัน',
      body: 'เมื่อมีรถอยู่แล้ว สามารถเพิ่มคันอื่นได้จากแถบด้านล่าง',
      bullets: [
        'แตะแถบ «บันทึกล่าสุด»',
        'กด «เพิ่มรถ» เพื่อเลือกรถและคนขับเพิ่ม',
      ],
    ),
    _TutorialStep(
      icon: Icons.water_drop_outlined,
      iconColor: Color(0xFFAD1457),
      iconBg: Color(0xFFFCE4EC),
      title: 'นับรอบร่อนทราย',
      body: 'แตะการ์ดการร่อนทรายทุกครั้งที่จบ 1 รอบ',
      bullets: [
        '1 แตะ = 1 รอบ (แยกเช้า/บ่ายตามเวลาบันทึก)',
        'ค่าจะไปช่วยเติมในเมนู «บันทึกการร่อนทราย»',
        'กดค้างเพื่อลบรอบล่าสุด',
      ],
    ),
    _TutorialStep(
      icon: Icons.cloud_sync_outlined,
      iconColor: Color(0xFFE65100),
      iconBg: Color(0xFFFFF3E0),
      title: 'ออฟไลน์และซิงก์',
      body: 'บันทึกได้แม้ไม่มีเน็ต ระบบเก็บในเครื่องแล้วอัปโหลดเมื่อกลับมาออนไลน์',
      bullets: [
        'บันทึกได้แม้ไม่มีเน็ต — ระบบจะอัปโหลดเมื่อกลับมาออนไลน์เอง',
        'ข้อมูลจะซิงก์อัตโนมัติเมื่อมีสัญญาณ',
      ],
    ),
    _TutorialStep(
      icon: Icons.battery_saver_rounded,
      iconColor: Color(0xFF00897B),
      iconBg: Color(0xFFE0F2F1),
      title: 'ประหยัดแบตเตอรี่',
      body: 'หน้านี้เปิดหน้าจอค้างไว้เพื่อกดบันทึกสะดวก '
          'แต่จะลดความสว่างเมื่อไม่ได้ใช้งาน',
      bullets: [
        'ไม่ได้ใช้งาน 1 นาที → หน้าจอมืดลง (แตะเพื่อกลับ)',
        'ไม่ได้ใช้งาน 10 นาที → หน้าจอพัก (แตะเพื่อตื่น)',
    ],
  ),
];

/// คู่มือสอนใช้งานหน้า «บันทึกและนับจำนวน»
class CountRecordTutorial {
  CountRecordTutorial._();

  /// เปิดคู่มือ — [markCompleteOnFinish] บันทึกว่าดูแล้วเมื่อกด «เข้าใจแล้ว»
  static Future<void> show(
    BuildContext context, {
    bool markCompleteOnFinish = true,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _CountRecordTutorialDialog(
        markCompleteOnFinish: markCompleteOnFinish,
      ),
    );
  }

  /// แสดงครั้งแรกเมื่อเปิดเมนู (ข้ามถ้าดูแล้ว)
  /// บันทึกทันทีที่เปิดครั้งแรก — กันโผล่ซ้ำทุกครั้งแม้กดปิดโดยไม่จบคู่มือ
  static Future<void> showIfFirstTime(BuildContext context) async {
    if (await CountRecordTutorialStore.hasCompleted()) return;
    if (!context.mounted) return;
    await CountRecordTutorialStore.markCompleted();
    if (!context.mounted) return;
    await show(context, markCompleteOnFinish: false);
  }
}

class _CountRecordTutorialDialog extends StatefulWidget {
  const _CountRecordTutorialDialog({required this.markCompleteOnFinish});

  final bool markCompleteOnFinish;

  @override
  State<_CountRecordTutorialDialog> createState() =>
      _CountRecordTutorialDialogState();
}

class _CountRecordTutorialDialogState extends State<_CountRecordTutorialDialog> {
  final _pageController = PageController();
  int _index = 0;

  static const _steps = _kCountRecordTutorialSteps;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool markComplete}) async {
    if (markComplete && widget.markCompleteOnFinish) {
      await CountRecordTutorialStore.markCompleted();
    }
    if (mounted) Navigator.pop(context);
  }

  void _goNext() {
    if (_index >= _steps.length - 1) {
      unawaited(_finish(markComplete: true));
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _goBack() {
    if (_index <= 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_index];
    final last = _index >= _steps.length - 1;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 8, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.school_outlined,
                          size: 16,
                          color: Color(0xFF1565C0),
                        ),
                        SizedBox(width: 5),
                        Text(
                          'สอนใช้งาน',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'ปิด',
                    onPressed: () =>
                        _finish(markComplete: widget.markCompleteOnFinish),
                    icon: const Icon(Icons.close_rounded),
                    color: const Color(0xFF78909C),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final s = _steps[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: s.iconBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(s.icon, size: 36, color: s.iconColor),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A2433),
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          s.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF4A5A70),
                            height: 1.45,
                          ),
                        ),
                        if (s.bullets.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ...s.bullets.map(
                            (b) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 7),
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: s.iconColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      b,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF37474F),
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF1565C0)
                          : const Color(0xFFDCE6F2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Row(
                children: [
                  if (_index > 0)
                    TextButton(
                      onPressed: _goBack,
                      child: const Text('ย้อนกลับ'),
                    )
                  else if (widget.markCompleteOnFinish)
                    TextButton(
                      onPressed: () => _finish(markComplete: true),
                      child: const Text('ข้าม'),
                    )
                  else
                    const SizedBox(width: 8),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: step.iconColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                    ),
                    onPressed: _goNext,
                    child: Text(
                      last ? 'เข้าใจแล้ว' : 'ถัดไป',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
