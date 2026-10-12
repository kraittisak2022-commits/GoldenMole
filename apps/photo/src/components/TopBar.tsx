import { ReactNode, useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { LogOut, Settings } from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import IconButton from './ui/IconButton';
import Logo from './Logo';

/** Sticky app bar: logo (or a back button), an optional centre slot (search), and the account menu. */
export default function TopBar({ leading, center }: { leading?: ReactNode; center?: ReactNode }) {
  const { user, signOut } = useAuth();
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!menuOpen) return;
    const close = (e: MouseEvent | KeyboardEvent) => {
      if (e instanceof KeyboardEvent ? e.key === 'Escape' : !menuRef.current?.contains(e.target as Node)) setMenuOpen(false);
    };
    document.addEventListener('mousedown', close);
    document.addEventListener('keydown', close);
    return () => {
      document.removeEventListener('mousedown', close);
      document.removeEventListener('keydown', close);
    };
  }, [menuOpen]);

  const initial = (user?.displayName || user?.username || '?').trim().charAt(0).toUpperCase();

  return (
    <header className="sticky top-0 z-30 border-b border-border/60 bg-page/95 pt-[env(safe-area-inset-top)] backdrop-blur">
      <div className="mx-auto flex h-16 max-w-[1600px] items-center gap-2 px-2 sm:px-4">
        <div className="flex min-w-0 items-center gap-1">{leading ?? <Logo />}</div>
        <div className="flex min-w-0 flex-1 justify-center">{center}</div>
        {user ? (
          <div className="flex items-center gap-1">
            <Link
              to="/settings"
              aria-label="ตั้งค่า"
              title="ตั้งค่า"
              className="inline-flex h-11 w-11 items-center justify-center rounded-full text-muted transition hover:bg-ink/[0.08] hover:text-ink"
            >
              <Settings size={22} aria-hidden />
            </Link>
            <div className="relative" ref={menuRef}>
              <IconButton label={`บัญชี ${user.displayName}`} aria-expanded={menuOpen} aria-haspopup="menu" onClick={() => setMenuOpen((v) => !v)}>
                <span className="flex h-8 w-8 items-center justify-center rounded-full bg-primary text-sm font-medium text-primary-foreground">{initial}</span>
              </IconButton>
              {menuOpen ? (
                <div role="menu" className="fade-in absolute right-0 top-12 z-40 w-64 rounded-2xl bg-container p-2 shadow-e2">
                  <div className="px-3 py-2">
                    <p className="truncate text-sm font-medium text-ink">{user.displayName}</p>
                    <p className="truncate text-xs text-muted">
                      {user.username} · {user.role}
                    </p>
                  </div>
                  <button
                    type="button"
                    role="menuitem"
                    onClick={signOut}
                    className="flex min-h-11 w-full cursor-pointer items-center gap-3 rounded-full px-3 text-sm text-ink hover:bg-ink/[0.08]"
                  >
                    <LogOut size={18} aria-hidden /> ออกจากระบบ
                  </button>
                </div>
              ) : null}
            </div>
          </div>
        ) : null}
      </div>
    </header>
  );
}
