import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { AuthProvider } from './auth/AuthProvider';
import { RequireAuth } from './auth/RequireAuth';
import AppShell from './components/AppShell';
import CategoriesPage from './pages/CategoriesPage';
import DashboardPage from './pages/DashboardPage';
import FleetPage from './pages/FleetPage';
import FleetStatementPage from './pages/FleetStatementPage';
import LedgerPage from './pages/LedgerPage';
import LoginPage from './pages/LoginPage';
import MastersPage from './pages/MastersPage';
import PayrollPage from './pages/PayrollPage';
import PayslipPage from './pages/PayslipPage';
import ReimbursementsPage from './pages/ReimbursementsPage';

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route
            path="/"
            element={
              <RequireAuth>
                <AppShell />
              </RequireAuth>
            }
          >
            <Route index element={<DashboardPage />} />
            <Route path="ledger" element={<LedgerPage />} />
            <Route path="categories" element={<CategoriesPage />} />
            <Route path="reimbursements" element={<ReimbursementsPage />} />
            <Route path="payroll" element={<PayrollPage />} />
            <Route path="payroll/:id/payslip" element={<PayslipPage />} />
            <Route path="fleet" element={<FleetPage />} />
            <Route path="fleet/:id/statement" element={<FleetStatementPage />} />
            <Route path="masters" element={<MastersPage />} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}
