import 'app_locale.dart';

/// แปลข้อความสถานะการ์ดเมนู (สร้างจาก logic ภาษาไทย) เป็น จีนตัวย่อ
String translateDailyCardStatus(String? thLabel, AppLocale locale) {
  if (thLabel == null || thLabel.trim().isEmpty) return '';
  if (locale == AppLocale.th) return thLabel;

  var s = thLabel.trim();

  const exact = <String, String>{
    'ยังไม่มีรายการลา': '暂无请假',
    'ยังไม่มีบันทึกล้างทราย': '暂无筛沙记录',
    'ยังไม่มีบันทึกรถ/เที่ยว': '暂无车辆/趟数记录',
    'ยังไม่มีบันทึกแม็คโคร': '暂无 macro 车辆记录',
    'ยังไม่มีบันทึกน้ำมัน': '暂无油料记录',
    'ยังไม่มีบันทึกล้างที่บ้าน': '暂无家中洗沙记录',
    'ยังไม่มีบันทึกค่าแรง': '暂无工作记录',
    'ยังไม่มีบันทึก OT': '暂无加班记录',
    'ครบแล้ว': '已完成',
    'ยังไม่ครบ': '未完成',
  };
  if (exact.containsKey(s)) return exact[s]!;

  s = s.replaceAll(' · ', ' · ');
  s = s.replaceAllMapped(RegExp(r'ลา (\d+) คน'), (m) => '请假 ${m[1]} 人');
  s = s.replaceAll('เช้า', '上午');
  s = s.replaceAll('บ่าย', '下午');
  s = s.replaceAll('คิว', '方');
  s = s.replaceAll('ถัง', '桶');
  s = s.replaceAll('คัน', '辆');
  s = s.replaceAll('เที่ยว', '趟');
  s = s.replaceAll('ลิตร', '升');
  s = s.replaceAll('ใช้งาน', '使用');
  s = s.replaceAll('แจ้ง', '已报');
  s = s.replaceAll('ครบแล้ว', '已完成');
  s = s.replaceAll('ยังไม่ครบ', '未完成');
  s = s.replaceAll('ยังไม่มีคิว', '暂无方量');
  s = s.replaceAll('ใช้แม็คโคร', '使用 macro');
  s = s.replaceAll('มาทำงาน', '出勤');
  s = s.replaceAll(' คน', ' 人');
  s = s.replaceAll('ชม.', '小时');
  s = s.replaceAll('ล้าง', '清洗');
  s = s.replaceAll('คงเหลือ', '剩余');
  s = s.replaceAll('บันทึกแล้ว · ยังไม่ระบุถัง', '已记录 · 未填桶数');

  return s;
}
