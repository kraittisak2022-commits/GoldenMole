import { lazy, Suspense } from 'react';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import { AuthProvider } from './auth/AuthProvider';
import RequireAuth from './auth/RequireAuth';
import { ManualCopyProvider } from './components/ManualCopy';
import { Spinner } from './components/ui/States';
import { ToastProvider } from './components/ui/Toast';
import { UploadProvider } from './components/uploads/UploadProvider';
import UploadTray from './components/uploads/UploadTray';

const LoginPage = lazy(() => import('./pages/LoginPage'));
const AlbumsPage = lazy(() => import('./pages/AlbumsPage'));
const AlbumPage = lazy(() => import('./pages/AlbumPage'));
const SharedAlbumPage = lazy(() => import('./pages/SharedAlbumPage'));
const SettingsPage = lazy(() => import('./pages/SettingsPage'));
const NotFoundPage = lazy(() => import('./pages/NotFoundPage'));

const PageFallback = () => (
  <div className="flex min-h-[60dvh] items-center justify-center">
    <Spinner />
  </div>
);

export default function App() {
  return (
    <BrowserRouter>
      <ToastProvider>
        <ManualCopyProvider>
          <AuthProvider>
            <UploadProvider>
              <Suspense fallback={<PageFallback />}>
                <Routes>
                  <Route path="/login" element={<LoginPage />} />
                  <Route path="/a/:token" element={<SharedAlbumPage />} />
                  <Route path="/" element={<RequireAuth><AlbumsPage /></RequireAuth>} />
                  <Route path="/albums/:id" element={<RequireAuth><AlbumPage /></RequireAuth>} />
                  <Route path="/settings" element={<RequireAuth><SettingsPage /></RequireAuth>} />
                  <Route path="*" element={<NotFoundPage />} />
                </Routes>
              </Suspense>
              <UploadTray />
            </UploadProvider>
          </AuthProvider>
        </ManualCopyProvider>
      </ToastProvider>
    </BrowserRouter>
  );
}
