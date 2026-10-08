import { useEffect } from 'react';
import { Link, NavLink, Outlet, useLocation, useNavigationType } from 'react-router-dom';
import { LayoutGrid, LogOut, Plus } from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import InstallApp from './InstallApp';
import { NAV_ITEMS } from './navItems';
import SourceBadge from './SourceBadge';
import logoUrl from '../assets/pirasit-logo.png';

const mobileTabs = [NAV_ITEMS[0], NAV_ITEMS[1], null, NAV_ITEMS[3]];

const mobileTabClass = ({ isActive }: { isActive: boolean }) =>
  [
    'flex min-h-14 flex-col items-center justify-center gap-0.5 text-xs transition duration-150 select-none active:scale-95 short:min-h-11 short:flex-row short:gap-1.5',
    isActive ? 'font-medium text-primary' : 'text-muted',
  ].join(' ');

export default function AppShell() {
  const { user, signOut, lockedSource } = useAuth();
  const location = useLocation();
  const navigationType = useNavigationType();
  const isFullscreen = location.pathname.startsWith('/bill') || location.pathname.startsWith('/new');
  const onMenu = location.pathname === '/menu';

  useEffect(() => {
    if (navigationType !== 'POP') window.scrollTo(0, 0);
  }, [location.pathname, navigationType]);

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
              {lockedSource ? (
                <p className="mt-1" title="บัญชีนี้เห็นเฉพาะออเดอร์ประเภทนี้">
                  <SourceBadge source={lockedSource} long />
                </p>
              ) : null}
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
            {NAV_ITEMS.map((item) => {
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
            {lockedSource ? <SourceBadge source={lockedSource} long /> : null}
          </header>
          <main className="mx-auto w-full max-w-6xl flex-1 p-4 pb-28 sm:p-6 md:pb-6 short:pb-20">
            <div key={location.pathname} className="page-enter">
              <Outlet />
            </div>
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
                    className="-mt-6 flex h-14 w-14 short:-mt-3 short:h-11 short:w-11 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg shadow-primary/30 ring-4 ring-surface transition duration-150 active:scale-90"
                  >
                    <Plus size={26} aria-hidden />
                  </Link>
                </div>
              );
            }
            const Icon = item.icon;
            return (
              <NavLink key={item.to} to={item.to} end={item.end} className={mobileTabClass}>
                <Icon size={20} aria-hidden />
                {item.label}
              </NavLink>
            );
          })}
          <NavLink
            to="/menu"
            state={onMenu ? location.state : { from: location.pathname }}
            replace={onMenu}
            className={mobileTabClass}
          >
            <LayoutGrid size={20} aria-hidden />
            เมนู
          </NavLink>
        </div>
      </nav>
    </div>
  );
}
