import { lazy, Suspense, type ReactNode } from 'react';
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { AuthProvider } from './auth/AuthProvider';
import { RequireAuth } from './auth/RequireAuth';
import AppShell from './components/AppShell';
import { Loading } from './components/ui/States';
import { CatalogProvider } from './context/CatalogProvider';
import CustomersPage from './pages/CustomersPage';
import DashboardPage from './pages/DashboardPage';
import DriversPage from './pages/DriversPage';
import LoginPage from './pages/LoginPage';
import OrdersPage from './pages/OrdersPage';
import SettingsPage from './pages/SettingsPage';
import StatementsPage from './pages/StatementsPage';
import VerifyPage from './pages/VerifyPage';

const NewOrderPage = lazy(() => import('./pages/new-order/NewOrderPage'));
const OrderDetailPage = lazy(() => import('./pages/OrderDetailPage'));
const BillPage = lazy(() => import('./pages/BillPage'));

const lazyPage = (node: ReactNode) => <Suspense fallback={<Loading />}>{node}</Suspense>;

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
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
            <Route path="drivers" element={<DriversPage />} />
            <Route path="settings" element={<SettingsPage />} />
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
