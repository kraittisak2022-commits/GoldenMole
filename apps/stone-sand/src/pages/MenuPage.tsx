import { Link, useLocation } from 'react-router-dom';
import { LogOut, Plus } from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import InstallApp from '../components/InstallApp';
import { NAV_ITEMS, navItemFor, type NavItem } from '../components/navItems';
import SourceBadge from '../components/SourceBadge';
import Card from '../components/ui/Card';
import PageHeader from '../components/ui/PageHeader';
import { useCatalog } from '../context/CatalogProvider';
import { listCustomers } from '../data/customers';
import { listDriverUnpaidOrders, listOrders } from '../data/orders';
import { listStatements } from '../data/statements';
import { useAsync } from '../hooks/useAsync';
import { toIsoDate } from '../lib/format';
import { menuHints, type MenuCounts } from '../lib/menuHints';

const MENU_ITEMS: NavItem[] = [...NAV_ITEMS, { to: '/new', label: 'สร้างออเดอร์', icon: Plus }];

function value<T>(r: PromiseSettledResult<T>): T | undefined {
  return r.status === 'fulfilled' ? r.value : undefined;
}

/** Each count loads on its own; one failing only drops that card's number. */
function useMenuCounts(): MenuCounts {
  const { data } = useAsync(async (): Promise<MenuCounts> => {
    const today = toIsoDate();
    const [todayOrders, waiting, customers, statements, driverUnpaid] = await Promise.allSettled([
      listOrders({ from: today, to: today }),
      listOrders({ deliveryStatuses: ['waiting', 'dispatched'], limit: 200 }),
      listCustomers(),
      listStatements(),
      listDriverUnpaidOrders(),
    ]);
    return {
      ordersToday: value(todayOrders)?.filter((o) => !o.cancelled).length,
      waitingDelivery: value(waiting)?.length,
      customers: value(customers)?.length,
      openStatements: value(statements)?.filter((s) => s.status === 'open').length,
      driverUnpaid: value(driverUnpaid)?.length,
    };
  }, []);
  return data ?? {};
}

export default function MenuPage() {
  const { user, signOut, lockedSource } = useAuth();
  const { drivers, products, loading: catalogLoading } = useCatalog();
  const location = useLocation();
  const from = (location.state as { from?: string } | null)?.from;
  const current = from ? navItemFor(from)?.to : undefined;
  const counts = useMenuCounts();
  const hints = menuHints({
    ...counts,
    drivers: catalogLoading ? undefined : drivers.length,
    products: catalogLoading ? undefined : products.length,
  });

  return (
    <div>
      <PageHeader title="เมนู" subtitle="เลือกส่วนที่ต้องการใช้งาน" />

      <nav aria-label="เมนูทั้งหมด" className="mb-6">
        <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
          {MENU_ITEMS.map((item) => (
            <li key={item.to}>
              <MenuCard item={item} hint={hints[item.to]} active={item.to === current} />
            </li>
          ))}
        </ul>
      </nav>

      <Card className="flex flex-col gap-1 p-3">
        <div className="flex flex-wrap items-center justify-between gap-2 px-3 py-2">
          <div className="min-w-0">
            <p className="truncate font-medium">{user?.displayName}</p>
            <p className="text-xs text-muted">{user?.role}</p>
          </div>
          {lockedSource ? <SourceBadge source={lockedSource} long /> : null}
        </div>
        <InstallApp className="flex min-h-12 items-center gap-3 rounded px-3 text-sm hover:bg-subtle cursor-pointer" />
        <button
          type="button"
          onClick={signOut}
          className="flex min-h-12 items-center gap-3 rounded px-3 text-sm text-destructive hover:bg-destructive-soft cursor-pointer"
        >
          <LogOut size={18} aria-hidden />
          ออกจากระบบ
        </button>
      </Card>
    </div>
  );
}

function MenuCard({ item, hint, active }: { item: NavItem; hint: string; active: boolean }) {
  const Icon = item.icon;
  return (
    <Link
      to={item.to}
      aria-current={active ? 'page' : undefined}
      className={[
        'flex min-h-36 flex-col items-center justify-center gap-3 rounded border p-4 text-center transition-colors duration-200',
        active
          ? 'border-primary bg-primary text-primary-foreground shadow-lg'
          : 'border-border bg-surface text-ink hover:border-primary/40 hover:bg-subtle',
      ].join(' ')}
    >
      <Icon size={40} strokeWidth={1.5} className={active ? '' : 'text-primary'} aria-hidden />
      <span className="flex flex-col gap-0.5">
        <span className="font-semibold">{item.label}</span>
        <span className={['text-xs tabular-nums', active ? 'opacity-80' : 'text-muted'].join(' ')}>{hint}</span>
      </span>
    </Link>
  );
}
