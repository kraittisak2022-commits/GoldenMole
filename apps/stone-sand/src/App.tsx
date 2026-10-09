import { lazy, Suspense } from 'react';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import { AuthProvider } from './auth/AuthProvider';
import { RequireAuth } from './auth/RequireAuth';
import { Loading } from './components/ui/States';
import VersionWatcher from './components/VersionWatcher';
import { retryImport } from './lib/chunkReload';
import LoginPage from './pages/LoginPage';

// Signed-out visitors only download the login page; company details live in these chunks.
const AuthedApp = lazy(retryImport(() => import('./AuthedApp')));
const VerifyPage = lazy(retryImport(() => import('./pages/VerifyPage')));
const DriverJobPage = lazy(retryImport(() => import('./pages/DriverJobPage')));

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <VersionWatcher />
        <Suspense fallback={<Loading page />}>
          <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route path="/v/:token" element={<VerifyPage />} />
            <Route path="/d/:token" element={<DriverJobPage />} />
            <Route
              path="/*"
              element={
                <RequireAuth>
                  <AuthedApp />
                </RequireAuth>
              }
            />
          </Routes>
        </Suspense>
      </BrowserRouter>
    </AuthProvider>
  );
}
