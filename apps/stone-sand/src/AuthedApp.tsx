import { lazy, Suspense, useEffect, type ReactNode } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import AppShell from './components/AppShell';
import { Loading } from './components/ui/States';
import { CatalogProvider } from './context/CatalogProvider';
import { retryImport } from './lib/chunkReload';
import CustomersPage from './pages/CustomersPage';
import DashboardPage from './pages/DashboardPage';
import DriverPayPage from './pages/DriverPayPage';
import DriversPage from './pages/DriversPage';
import MenuPage from './pages/MenuPage';
import OrdersPage from './pages/OrdersPage';
import SettingsPage from './pages/SettingsPage';
import StatementsPage from './pages/StatementsPage';
import TourProvider from './tour/TourProvider';

const loadNewOrder = () => import('./pages/new-order/NewOrderPage');
const loadOrderDetail = () => import('./pages/OrderDetailPage');
const loadBill = () => import('./pages/BillPage');

const NewOrderPage = lazy(retryImport(loadNewOrder));
const OrderDetailPage = lazy(retryImport(loadOrderDetail));
const BillPage = lazy(retryImport(loadBill));
const BillSummaryPage = lazy(retryImport(() => import('./pages/bill-summary/BillSummaryPage')));

const lazyPage = (node: ReactNode) => <Suspense fallback={<Loading page />}>{node}</Suspense>;

/** Fetches the code-split pages once the app is idle, so opening them later is instant. */
function usePrefetchPages() {
  useEffect(() => {
    const prefetch = () => {
      for (const load of [loadNewOrder, loadOrderDetail, loadBill]) load().catch(() => undefined);
    };
    if ('requestIdleCallback' in window) {
      const id = window.requestIdleCallback(prefetch, { timeout: 4000 });
      return () => window.cancelIdleCallback(id);
    }
    const id = setTimeout(prefetch, 1500);
    return () => clearTimeout(id);
  }, []);
}

/** index.html only references neutral icons; the company logo is swapped in for signed-in users. */
const BRAND_HEAD: [selector: string, href: string][] = [
  ['link[rel="icon"]', '/app-icons/favicon-32.png?v=2'],
  ['link[rel="apple-touch-icon"]', '/app-icons/apple-touch-icon.png?v=2'],
  ['link[rel="manifest"]', '/app.webmanifest?v=1'],
];

function useBrandHead() {
  useEffect(() => {
    const restore: (() => void)[] = [];
    for (const [selector, href] of BRAND_HEAD) {
      const link = document.head.querySelector<HTMLLinkElement>(selector);
      if (!link) continue;
      const previous = link.getAttribute('href');
      link.setAttribute('href', href);
      restore.push(() => previous && link.setAttribute('href', previous));
    }
    return () => restore.forEach((fn) => fn());
  }, []);
}

export default function AuthedApp() {
  usePrefetchPages();
  useBrandHead();
  return (
    <CatalogProvider>
      <TourProvider>
        <Routes>
          <Route element={<AppShell />}>
            <Route index element={<DashboardPage />} />
            <Route path="orders" element={<OrdersPage />} />
            <Route path="orders/:id" element={lazyPage(<OrderDetailPage />)} />
            <Route path="customers" element={<CustomersPage />} />
            <Route path="statements" element={<StatementsPage />} />
            <Route path="driver-pay" element={<DriverPayPage />} />
            <Route path="bill-summary" element={lazyPage(<BillSummaryPage />)} />
            <Route path="drivers" element={<DriversPage />} />
            <Route path="settings" element={<SettingsPage />} />
            <Route path="menu" element={<MenuPage />} />
            <Route path="new" element={lazyPage(<NewOrderPage />)} />
            <Route path="bill/order/:id" element={lazyPage(<BillPage mode="order" />)} />
            <Route path="bill/statement/:id" element={lazyPage(<BillPage mode="statement" />)} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </TourProvider>
    </CatalogProvider>
  );
}
