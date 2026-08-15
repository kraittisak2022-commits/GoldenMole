import { NavLink, Outlet, useLocation } from 'react-router-dom';
import {
  BookOpen,
  LayoutDashboard,
  LogOut,
  Tags,
  Truck,
  Users,
  Wallet,
  ClipboardList,
} from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import Button from './ui/Button';

const navItems = [
  { to: '/', label: 'แดชบอร์ด', icon: LayoutDashboard, end: true },
  { to: '/ledger', label: 'รายรับ-รายจ่าย', icon: BookOpen },
  { to: '/categories', label: 'จัดการหมวดหมู่', icon: Tags },
  { to: '/reimbursements', label: 'เบิกสำรองจ่าย', icon: ClipboardList },
  { to: '/payroll', label: 'เงินเดือน', icon: Wallet },
  { to: '/fleet', label: 'ต้นทุนรถ', icon: Truck },
  { to: '/masters', label: 'ข้อมูลหลัก', icon: Users },
];

export default function AppShell() {
  const { user, signOut } = useAuth();
  const location = useLocation();
  const isPrint = location.pathname.includes('/payslip') || location.pathname.includes('/statement');

  if (isPrint) {
    return (
      <div className="min-h-screen bg-white text-ink">
        <Outlet />
      </div>
    );
  }

  return (
    <div className="min-h-screen min-h-[100dvh] bg-page text-ink print:bg-white">
      <div className="flex min-h-screen min-h-[100dvh]">
        <aside className="hidden w-60 shrink-0 border-r border-border bg-surface md:flex md:flex-col print:hidden">
          <div className="border-b border-border px-5 py-5">
            <p className="text-xs font-medium uppercase tracking-wider text-muted">GoldenMole</p>
            <h1 className="mt-1 text-lg font-semibold text-ink">FlowAccount</h1>
          </div>
          <nav className="flex flex-1 flex-col gap-1 p-3" aria-label="เมนูหลัก">
            {navItems.map((item) => {
              const Icon = item.icon;
              return (
                <NavLink
                  key={item.to}
                  to={item.to}
                  end={item.end}
                  className={({ isActive }) =>
                    [
                      'flex min-h-11 items-center gap-3 rounded-DEFAULT px-3 text-sm transition-colors duration-200',
                      isActive
                        ? 'bg-slate-100 font-medium text-ink'
                        : 'text-muted hover:bg-slate-50 hover:text-ink',
                    ].join(' ')
                  }
                >
                  <Icon size={18} aria-hidden />
                  {item.label}
                </NavLink>
              );
            })}
          </nav>
        </aside>

        <div className="flex min-w-0 flex-1 flex-col">
          <header className="flex min-h-14 items-center justify-between gap-4 border-b border-border bg-surface px-4 py-3 sm:px-6 print:hidden">
            <div className="md:hidden">
              <p className="text-sm font-semibold">FlowAccount</p>
            </div>
            <nav className="flex flex-1 gap-1 overflow-x-auto md:hidden" aria-label="เมนูมือถือ">
              {navItems.map((item) => (
                <NavLink
                  key={item.to}
                  to={item.to}
                  end={item.end}
                  className={({ isActive }) =>
                    [
                      'whitespace-nowrap rounded-DEFAULT px-2 py-2 text-xs',
                      isActive ? 'bg-slate-100 font-medium text-ink' : 'text-muted',
                    ].join(' ')
                  }
                >
                  {item.label}
                </NavLink>
              ))}
            </nav>
            <div className="ml-auto flex items-center gap-3">
              <div className="hidden text-right sm:block">
                <p className="text-sm font-medium text-ink">{user?.displayName}</p>
                <p className="text-xs text-muted">{user?.role}</p>
              </div>
              <Button variant="secondary" onClick={signOut} aria-label="ออกจากระบบ">
                <LogOut size={16} aria-hidden />
                <span className="hidden sm:inline">ออกจากระบบ</span>
              </Button>
            </div>
          </header>
          <main className="flex-1 p-4 sm:p-6 print:p-0">
            <Outlet />
          </main>
        </div>
      </div>
    </div>
  );
}
