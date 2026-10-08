import { useState } from 'react';
import { Link, NavLink, Outlet, useLocation } from 'react-router-dom';
import {
  ClipboardList,
  Download,
  FileCheck2,
  LayoutDashboard,
  LogOut,
  Menu,
  Plus,
  Settings,
  Truck,
  Users,
} from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import { isIos, isStandalone, useInstallPrompt } from '../lib/installPrompt';
import Modal from './ui/Modal';
import logoUrl from '../assets/pirasit-logo.png';

const navItems = [
  { to: '/', label: 'หน้าหลัก', icon: LayoutDashboard, end: true },
  { to: '/orders', label: 'ออเดอร์', icon: ClipboardList },
  { to: '/customers', label: 'ลูกค้า', icon: Users },
  { to: '/statements', label: 'เคลียร์บิล', icon: FileCheck2 },
  { to: '/drivers', label: 'รถ / คนขับ', icon: Truck },
  { to: '/settings', label: 'ตั้งค่า', icon: Settings },
];

const mobileTabs = [navItems[0], navItems[1], null, navItems[3]];

export default function AppShell() {
  const { user, signOut } = useAuth();
  const location = useLocation();
  const [menuOpen, setMenuOpen] = useState(false);
  const isFullscreen = location.pathname.startsWith('/bill') || location.pathname.startsWith('/new');

  if (isFullscreen) {
    return (
      <div className="min-h-[100dvh] bg-page text-ink print:bg-white">
        <Outlet />
      </div>
    );
  }

  return (
    <div className="min-h-[100dvh] bg-page text-ink">
      <div className="flex min-h-[100dvh]">
        <aside className="hidden w-64 shrink-0 border-r border-border bg-surface md:sticky md:top-0 md:flex md:h-[100dvh] md:flex-col md:overflow-y-auto">
          <div className="flex items-center gap-3 border-b border-border px-5 py-4">
            <img src={logoUrl} alt="" className="h-12 w-auto shrink-0" />
            <div className="min-w-0">
              <p className="text-xs font-medium tracking-wide text-muted">หจก. พีรสิทธิ์ วัสดุก่อสร้าง</p>
              <h1 className="mt-0.5 text-lg font-semibold text-ink">ออเดอร์หิน-ทราย</h1>
            </div>
          </div>
          <div className="p-3">
            <Link
              to="/new"
              className="flex min-h-12 items-center justify-center gap-2 rounded bg-primary px-4 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary-hover"
            >
              <Plus size={18} aria-hidden />
              สร้างออเดอร์
            </Link>
          </div>
          <nav className="flex flex-1 flex-col gap-1 px-3" aria-label="เมนูหลัก">
            {navItems.map((item) => {
              const Icon = item.icon;
              return (
                <NavLink
                  key={item.to}
                  to={item.to}
                  end={item.end}
                  className={({ isActive }) =>
                    [
                      'flex min-h-11 items-center gap-3 rounded px-3 text-sm transition-colors duration-200',
                      isActive
                        ? 'bg-primary-soft font-medium text-primary'
                        : 'text-muted hover:bg-subtle hover:text-ink',
                    ].join(' ')
                  }
                >
                  <Icon size={18} aria-hidden />
                  {item.label}
                </NavLink>
              );
            })}
          </nav>
          <div className="border-t border-border p-3">
            <InstallApp className="flex min-h-11 w-full items-center gap-3 rounded px-3 text-sm text-muted hover:bg-subtle hover:text-ink cursor-pointer" />
            <div className="px-3 pb-2">
              <p className="text-sm font-medium text-ink">{user?.displayName}</p>
              <p className="text-xs text-muted">{user?.role}</p>
            </div>
            <button
              type="button"
              onClick={signOut}
              className="flex min-h-11 w-full items-center gap-3 rounded px-3 text-sm text-muted hover:bg-subtle hover:text-ink cursor-pointer"
            >
              <LogOut size={18} aria-hidden />
              ออกจากระบบ
            </button>
          </div>
        </aside>

        <div className="flex min-w-0 flex-1 flex-col">
          <header className="sticky top-0 z-30 flex min-h-14 items-center justify-between border-b border-border bg-surface/95 px-4 pt-safe-top backdrop-blur md:hidden short:hidden">
            <div className="flex items-center gap-2.5">
              <img src={logoUrl} alt="" className="h-9 w-auto shrink-0" />
              <div>
                <p className="text-xs text-muted">หจก. พีรสิทธิ์ วัสดุก่อสร้าง</p>
                <p className="text-sm font-semibold">ออเดอร์หิน-ทราย</p>
              </div>
            </div>
          </header>
          <main className="mx-auto w-full max-w-6xl flex-1 p-4 pb-28 sm:p-6 md:pb-6 short:pb-20">
            <Outlet />
          </main>
        </div>
      </div>

      <nav
        className="fixed inset-x-0 bottom-0 z-40 pad-x-safe border-t border-border bg-surface/95 pb-safe-bottom backdrop-blur md:hidden"
        aria-label="เมนูมือถือ"
      >
        <div className="grid grid-cols-5">
          {mobileTabs.map((item) => {
            if (!item) {
              return (
                <div key="new" className="flex items-center justify-center">
                  <Link
                    to="/new"
                    aria-label="สร้างออเดอร์"
                    className="-mt-6 flex h-14 w-14 short:-mt-3 short:h-11 short:w-11 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg"
                  >
                    <Plus size={26} aria-hidden />
                  </Link>
                </div>
              );
            }
            const Icon = item.icon;
            return (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.end}
                className={({ isActive }) =>
                  [
                    'flex min-h-14 flex-col items-center justify-center gap-0.5 text-xs short:min-h-11 short:flex-row short:gap-1.5',
                    isActive ? 'font-medium text-primary' : 'text-muted',
                  ].join(' ')
                }
              >
                <Icon size={20} aria-hidden />
                {item.label}
              </NavLink>
            );
          })}
          <button
            type="button"
            onClick={() => setMenuOpen(true)}
            className="flex min-h-14 flex-col items-center justify-center gap-0.5 text-xs text-muted cursor-pointer short:min-h-11 short:flex-row short:gap-1.5"
          >
            <Menu size={20} aria-hidden />
            เมนู
          </button>
        </div>
      </nav>

      <Modal open={menuOpen} title="เมนู" onClose={() => setMenuOpen(false)}>
        <div className="flex flex-col gap-1">
          {navItems.map((item) => {
            const Icon = item.icon;
            return (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.end}
                onClick={() => setMenuOpen(false)}
                className="flex min-h-12 items-center gap-3 rounded px-3 text-sm hover:bg-subtle"
              >
                <Icon size={18} className="text-muted" aria-hidden />
                {item.label}
              </NavLink>
            );
          })}
          <InstallApp className="flex min-h-12 items-center gap-3 rounded px-3 text-sm hover:bg-subtle cursor-pointer" />
          <div className="my-2 border-t border-border" />
          <p className="px-3 text-xs text-muted">
            {user?.displayName} · {user?.role}
          </p>
          <button
            type="button"
            onClick={signOut}
            className="flex min-h-12 items-center gap-3 rounded px-3 text-sm text-destructive hover:bg-destructive-soft cursor-pointer"
          >
            <LogOut size={18} aria-hidden />
            ออกจากระบบ
          </button>
        </div>
      </Modal>
    </div>
  );
}

function InstallApp({ className }: { className: string }) {
  const install = useInstallPrompt();
  if (isStandalone()) return null;
  if (install) {
    return (
      <button type="button" onClick={() => void install()} className={className}>
        <Download size={18} className="text-muted" aria-hidden />
        ติดตั้งเป็นแอปบนเครื่อง
      </button>
    );
  }
  if (isIos()) {
    return <p className="px-3 py-2 text-sm text-muted">ติดตั้งเป็นแอป: กดปุ่มแชร์ แล้วเลือก “เพิ่มไปยังหน้าจอโฮม”</p>;
  }
  return null;
}
