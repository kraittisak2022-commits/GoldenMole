import 'package:flutter/material.dart';

import 'app_locale.dart';
import '../widgets/app_locale_scope.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final AppLocale locale;

  static AppLocalizations of(BuildContext context) {
    return AppLocaleScope.of(context).localizations;
  }

  bool get isChinese => locale == AppLocale.zh;

  String get dailyLogTitle => _pick('บันทึกประจำวัน', '每日记录');

  String get languageLabel => _pick('ภาษา', '语言');

  String get statusComplete => _pick('ครบแล้ว', '已完成');

  String get statusIncomplete => _pick('ยังไม่ครบ', '未完成');

  String get statusTapToRecord => _pick('แตะเพื่อบันทึก', '点击记录');

  String get serverOnline => _pick('เซิร์ฟเวอร์: ออนไลน์', '服务器：在线');

  String get serverOffline => _pick('เซิร์ฟเวอร์: ออฟไลน์', '服务器：离线');

  String get latestPrefix => _pick('ล่าสุด', '最新');

  String get timePrefix => _pick('เวลา', '时间');

  String get timeSuffix => _pick('น.', '');

  String get loadingDashboard => _pick('กำลังโหลดแดชบอร์ด', '正在加载每日记录');

  String get loadingData => _pick('กำลังโหลดข้อมูล', '正在加载数据');

  String get retry => _pick('ลองอีกครั้ง', '重试');

  String get loadFailed => _pick('โหลดข้อมูลไม่สำเร็จ', '加载失败');

  String get navHome => _pick('หน้าแรก', '首页');

  String get navCalendar => _pick('ปฏิทิน', '日历');

  String get navSettings => _pick('ตั้งค่า', '设置');

  String get navHideMenu => _pick('ซ่อนเมนู', '隐藏菜单');

  String get navLogout => _pick('ออกจากระบบ', '退出登录');

  String headerMenusComplete(int total) =>
      _pick('วันนี้บันทึกครบทุกเมนูแล้ว ($total เมนู)', '今日已全部完成 ($total 项)');

  String headerMenusProgress(int done, int incomplete, int total) => _pick(
    'วันนี้ครบ $done · ไม่ครบ $incomplete · รวม $total เมนู',
    '今日完成 $done · 未完成 $incomplete · 共 $total 项',
  );

  String headerMenusSimple(int done, int total) =>
      _pick('วันนี้บันทึกครบ $done/$total เมนู', '今日完成 $done/$total 项');

  String moduleTitle(String category) {
    const thToZh = <String, String>{
      'บันทึกการร่อนทราย': '筛沙记录',
      'จำนวนเที่ยวรถ': '车辆与趟数',
      'การใช้รถแม็คโคร': '使用 macro 车辆',
      'น้ำมัน': '油料',
      'ทรายที่ล้างที่บ้าน': '家中洗沙',
      'เหตุการณ์': '事件',
      'ค่าแรง': '工作记录',
      'OT': '加班 (OT)',
      'ลางาน': '请假',
      'เบิกเงิน': '预支',
      'รายจ่ายรายรับ': '收支',
    };
    if (locale == AppLocale.th) {
      return _moduleTitlesTh[category] ?? category;
    }
    return thToZh[category] ?? category;
  }

  String formatSelectedDate(DateTime d) {
    if (locale == AppLocale.zh) {
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return '${weekdays[d.weekday - 1]} ${d.year}年${d.month}月${d.day}日';
    }
    const weekdays = [
      'วันจันทร์',
      'วันอังคาร',
      'วันพุธ',
      'วันพฤหัสบดี',
      'วันศุกร์',
      'วันเสาร์',
      'วันอาทิตย์',
    ];
    const months = [
      'มกราคม',
      'กุมภาพันธ์',
      'มีนาคม',
      'เมษายน',
      'พฤษภาคม',
      'มิถุนายน',
      'กรกฎาคม',
      'สิงหาคม',
      'กันยายน',
      'ตุลาคม',
      'พฤศจิกายน',
      'ธันวาคม',
    ];
    final be = d.year + 543;
    return '${weekdays[d.weekday - 1]} ที่ ${d.day} เดือน${months[d.month - 1]} พ.ศ.$be';
  }

  String formatShortDateFromYmd(String ymd) {
    if (locale == AppLocale.zh) {
      try {
        final p = ymd.split('-');
        if (p.length != 3) return ymd;
        return '${p[0]}年${int.parse(p[1])}月${int.parse(p[2])}日';
      } catch (_) {
        return ymd;
      }
    }
    try {
      final p = ymd.split('-');
      if (p.length != 3) return ymd;
      final d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      const months = [
        'ม.ค.',
        'ก.พ.',
        'มี.ค.',
        'เม.ย.',
        'พ.ค.',
        'มิ.ย.',
        'ก.ค.',
        'ส.ค.',
        'ก.ย.',
        'ต.ค.',
        'พ.ย.',
        'ธ.ค.',
      ];
      final be = d.year + 543;
      return '${d.day} ${months[d.month - 1]} $be';
    } catch (_) {
      return ymd;
    }
  }

  String _pick(String th, String zh) => locale == AppLocale.zh ? zh : th;

  static const _moduleTitlesTh = <String, String>{
    'บันทึกการร่อนทราย': 'บันทึกการร่อนทราย',
    'จำนวนเที่ยวรถ': 'บันทึกรถดรัมและจำนวนเที่ยว',
    'การใช้รถแม็คโคร': 'การใช้รถแม็คโคร',
    'น้ำมัน': 'น้ำมัน',
    'ทรายที่ล้างที่บ้าน': 'ทรายที่ล้างที่บ้าน',
    'เหตุการณ์': 'เหตุการณ์',
    'ค่าแรง': 'บันทึกการทำงาน',
    'OT': 'การทำงานล่วงเวลา (OT)',
    'ลางาน': 'ลางาน',
    'เบิกเงิน': 'เบิกเงิน',
    'รายจ่ายรายรับ': 'รายรับ-รายจ่าย',
  };
}
