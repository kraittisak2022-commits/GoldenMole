/// รหัสหน้าและขั้นตอนในแอป — ใช้ติดตามตำแหน่งเมื่อเกิด error
abstract final class MobileScreenIds {
  // --- Page IDs (หน้า) ---
  static const pageLogin = 'page.login';
  static const pageDashboard = 'page.dashboard';
  static const pageQuickInput = 'page.quick_input';
  static const pageSettings = 'page.settings';
  static const pageCalendar = 'page.calendar';
  static const pageEmployees = 'page.employees';
  static const pageTransactions = 'page.transactions';
  static const pageProjects = 'page.projects';
  static const pageErrorHub = 'page.error_hub';
  static const pageFatalError = 'page.fatal_error';

  // --- Step IDs (ขั้นตอน/ย่อย) — แดชบอร์ด ---
  static const stepDashboardHome = 'step.dashboard.home';
  static const stepDashboardCountRecordMenu =
      'step.dashboard.count_record_menu';
  static const stepDashboardCountRecordTrip =
      'step.dashboard.count_record.trip';
  static const stepDashboardCountRecordSand =
      'step.dashboard.count_record.sand';

  // --- Step IDs — ตั้งค่า ---
  static const stepSettingsMain = 'step.settings.main';
  static const stepErrorHubList = 'step.error_hub.list';

  // --- Step IDs — อื่น ๆ ---
  static const stepCalendarMain = 'step.calendar.main';
  static const stepEmployeesList = 'step.employees.list';
  static const stepTransactionsList = 'step.transactions.list';
  static const stepProjectsList = 'step.projects.list';
  static const stepLoginForm = 'step.login.form';
  static const stepFatalErrorView = 'step.fatal_error.view';

  /// แมปชื่อเมนูบันทึกประจำวัน → step id
  static String quickInputStep(String? category) {
    switch ((category ?? '').trim()) {
      case 'บันทึกการร่อนทราย':
        return 'step.quick_input.sand_sift';
      case 'จำนวนเที่ยวรถ':
        return 'step.quick_input.vehicle_trips';
      case 'การใช้รถแม็คโคร':
        return 'step.quick_input.macro_vehicle';
      case 'น้ำมัน':
        return 'step.quick_input.fuel';
      case 'บำรุงรักษา':
        return 'step.quick_input.maintenance';
      case 'ทรายที่ล้างที่บ้าน':
        return 'step.quick_input.sand_wash_home';
      case 'เหตุการณ์':
        return 'step.quick_input.events';
      case 'ค่าแรง':
        return 'step.quick_input.labor';
      case 'เช็คชื่อ':
        return 'step.quick_input.attendance';
      case 'OT':
        return 'step.quick_input.ot';
      case 'ลางาน':
        return 'step.quick_input.leave';
      case 'เบิกเงิน':
        return 'step.quick_input.advance';
      case 'รายจ่ายรายรับ':
        return 'step.quick_input.income_utilities';
      default:
        return 'step.quick_input.generic';
    }
  }
}
