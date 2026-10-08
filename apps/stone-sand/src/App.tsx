import { lazy, Suspense, useEffect, type ReactNode } from 'react';
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { AuthProvider } from './auth/AuthProvider';
import { RequireAuth } from './auth/RequireAuth';
import AppShell from './components/AppShell';
import { Loading } from './components/ui/States';
import VersionWatcher from './components/VersionWatcher';
import { CatalogProvider } from './context/CatalogProvider';
import { retryImport } from './lib/chunkReload';
import CustomersPage from './pages/CustomersPage';
import DashboardPage from './pages/DashboardPage';
import DriverPayPage from './pages/DriverPayPage';
import DriversPage from './pages/DriversPage';
import LoginPage from './pages/LoginPage';
import MenuPage from './pages/MenuPage';
import OrdersPage from './pages/OrdersPage';
import SettingsPage from './pages/SettingsPage';
import StatementsPage from './pages/StatementsPage';
import VerifyPage from './pages/VerifyPage';

const loadNewOrder = () => import('./pages/new-order/NewOrderPage');
const loadOrderDetail = () => import('./pages/OrderDetailPage');
const loadBill = () => import('./pages/BillPage');

const NewOrderPage = lazy(retryImport(loadNewOrder));
const OrderDetailPage = lazy(retryImport(loadOrderDetail));
const BillPage = lazy(retryImport(loadBill));

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

export default function App() {
  usePrefetchPages();
  return (
    <AuthProvider>
      <BrowserRouter>
        <VersionWatcher />
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/v/:token" element={<VerifyPage />} />
          <Route
            path="/"
            element={
              <RequireAuth>
                <CatalogProvider>
                  <AppShell />
                </CatalogProvider>
              </RequireAuth>
            }
          >
            <Route index element={<DashboardPage />} />
            <Route path="orders" element={<OrdersPage />} />
            <Route path="orders/:id" element={lazyPage(<OrderDetailPage />)} />
            <Route path="customers" element={<CustomersPage />} />
            <Route path="statements" element={<StatementsPage />} />
            <Route path="driver-pay" element={<DriverPayPage />} />
            <Route path="drivers" element={<DriversPage />} />
            <Route path="settings" element={<SettingsPage />} />
            <Route path="menu" element={<MenuPage />} />
            <Route path="new" element={lazyPage(<NewOrderPage />)} />
            <Route path="bill/order/:id" element={lazyPage(<BillPage mode="order" />)} />
            <Route path="bill/statement/:id" element={lazyPage(<BillPage mode="statement" />)} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}
