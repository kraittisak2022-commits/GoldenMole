import { NavLink, Outlet } from 'react-router-dom';
import { BookOpen, LayoutDashboard, LogOut, Receipt } from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import Button from './ui/Button';

const navItems = [
  { to: '/', label: 'แดชบอร์ด', icon: LayoutDashboard, enabled: true },
  { to: '#', label: 'สมุดรายวัน', icon: BookOpen, enabled: false },
  { to: '#', label: 'ใบแจ้งหนี้', icon: Receipt, enabled: false },
];

export default function AppShell() {
  const { user, signOut } = useAuth();

  return (
    <div className="min-h-screen min-h-[100dvh] bg-page text-ink">
      <div className="flex min-h-screen min-h-[100dvh]">
        <aside className="hidden w-60 shrink-0 border-r border-border bg-surface md:flex md:flex-col">
          <div className="border-b border-border px-5 py-5">
            <p className="text-xs font-medium uppercase tracking-wider text-muted">GoldenMole</p>
            <h1 className="mt-1 text-lg font-semibold text-ink">FlowAccount</h1>
          </div>
          <nav className="flex flex-1 flex-col gap-1 p-3" aria-label="เมนูหลัก">
            {navItems.map((item) => {
              const Icon = item.icon;
              if (!item.enabled) {
                return (
                  <div
                    key={item.label}
                    className="flex min-h-11 items-center gap-3 rounded-DEFAULT px-3 text-sm text-muted/70"
                    aria-disabled="true"
                  >
                    <Icon size={18} aria-hidden />
                    <span className="flex-1">{item.label}</span>
                    <span className="text-[10px] uppercase tracking-wide">เร็วๆ นี้</span>
                  </div>
                );
              }
              return (
                <NavLink
                  key={item.to}
                  to={item.to}
                  end
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
          <header className="flex min-h-14 items-center justify-between gap-4 border-b border-border bg-surface px-4 py-3 sm:px-6">
            <div className="md:hidden">
              <p className="text-sm font-semibold">FlowAccount</p>
            </div>
            <div className="ml-auto flex items-center gap-3">
              <div className="text-right">
                <p className="text-sm font-medium text-ink">{user?.displayName}</p>
                <p className="text-xs text-muted">{user?.role}</p>
              </div>
              <Button variant="secondary" onClick={signOut} aria-label="ออกจากระบบ">
                <LogOut size={16} aria-hidden />
                <span className="hidden sm:inline">ออกจากระบบ</span>
              </Button>
            </div>
          </header>
          <main className="flex-1 p-4 sm:p-6">
            <Outlet />
          </main>
        </div>
      </div>
    </div>
  );
}
