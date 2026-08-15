import Card from '../components/ui/Card';
import { useAuth } from '../auth/AuthProvider';

export default function DashboardPage() {
  const { user } = useAuth();

  return (
    <div className="mx-auto max-w-3xl">
      <h2 className="text-2xl font-semibold tracking-tight text-ink">แดชบอร์ด</h2>
      <p className="mt-2 text-sm text-muted">
        ยินดีต้อนรับ {user?.displayName} — โมดูลบัญชีจะเพิ่มในเฟสถัดไป
      </p>

      <Card className="mt-6 p-6">
        <h3 className="text-base font-medium text-ink">สถานะระบบ</h3>
        <ul className="mt-4 space-y-2 text-sm text-muted">
          <li>ล็อกอิน: พร้อมใช้งาน (SuperAdmin)</li>
          <li>สมุดรายวัน: เร็วๆ นี้</li>
          <li>ใบแจ้งหนี้ / รายงาน: เร็วๆ นี้</li>
        </ul>
      </Card>
    </div>
  );
}
