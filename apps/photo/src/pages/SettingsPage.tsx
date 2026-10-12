import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { ArrowLeft, CheckCircle2, CloudOff, FolderTree, HardDrive } from 'lucide-react';
import { ROOT_FOLDER_NAME } from '../../shared/folderPath';
import type { GoogleStatus } from '../../shared/types';
import { useAuth } from '../auth/AuthProvider';
import TopBar from '../components/TopBar';
import Button from '../components/ui/Button';
import { ErrorState, Spinner } from '../components/ui/States';
import { useToast } from '../components/ui/Toast';
import { api } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { drivePathLabel } from '../lib/drivePath';
import { formatDateTime } from '../lib/format';

const CALLBACK_MESSAGES: Record<string, string> = {
  connected: 'เชื่อมต่อ Google Drive แล้ว',
  denied: 'ยกเลิกการเชื่อมต่อ Google Drive',
  error: 'เชื่อมต่อ Google Drive ไม่สำเร็จ ลองใหม่อีกครั้ง',
};

export default function SettingsPage() {
  const { user } = useAuth();
  const toast = useToast();
  const [params, setParams] = useSearchParams();
  const [status, setStatus] = useState<GoogleStatus | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const isSuperAdmin = user?.role === 'SuperAdmin';

  const load = () => {
    setError(null);
    api<GoogleStatus>('/api/google/status')
      .then(setStatus)
      .catch((err) => setError(errorMessage(err)));
  };

  useEffect(() => {
    load();
    const result = params.get('google');
    if (result && CALLBACK_MESSAGES[result]) {
      toast(CALLBACK_MESSAGES[result]);
      params.delete('google');
      setParams(params, { replace: true });
    }
  }, []);

  const connect = async () => {
    setBusy(true);
    try {
      const { url } = await api<{ url: string }>('/api/google/connect', { method: 'POST' });
      window.location.assign(url);
    } catch (err) {
      toast(errorMessage(err));
      setBusy(false);
    }
  };

  return (
    <div className="min-h-[100dvh] pb-16">
      <TopBar
        leading={
          <Link to="/" aria-label="กลับไปหน้าอัลบั้ม" className="inline-flex h-11 w-11 items-center justify-center rounded-full text-muted hover:bg-ink/[0.08]">
            <ArrowLeft size={22} aria-hidden />
          </Link>
        }
      />
      <main className="mx-auto max-w-2xl px-4 sm:px-6">
        <h1 className="py-5 text-2xl font-normal text-ink">ตั้งค่า</h1>

        <section className="rounded-2xl border border-border/70 bg-surface p-5 sm:p-6" aria-labelledby="drive-heading">
          <div className="flex items-start gap-4">
            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-primary-soft text-primary-soft-foreground">
              <HardDrive size={24} aria-hidden />
            </div>
            <div className="min-w-0 flex-1">
              <h2 id="drive-heading" className="text-lg font-medium text-ink">
                Google Drive
              </h2>
              <p className="mt-1 text-sm text-muted">ทุกรูปและวิดีโอเก็บในบัญชี Google Drive นี้ หนึ่งอัลบั้มเป็นหนึ่งโฟลเดอร์</p>

              <div className="mt-4">
                {error ? (
                  <ErrorState message={error} onRetry={load} />
                ) : !status ? (
                  <Spinner />
                ) : status.connected ? (
                  <p className="flex items-start gap-2 text-sm text-ink">
                    <CheckCircle2 size={20} className="mt-0.5 shrink-0 text-success" aria-hidden />
                    <span>
                      เชื่อมต่อกับ <span className="font-medium break-all">{status.email ?? 'บัญชี Google'}</span>
                      {status.connectedAt ? <span className="block text-muted">ตั้งแต่ {formatDateTime(status.connectedAt)}</span> : null}
                    </span>
                  </p>
                ) : (
                  <p className="flex items-start gap-2 text-sm text-ink">
                    <CloudOff size={20} className="mt-0.5 shrink-0 text-destructive" aria-hidden />
                    ยังไม่ได้เชื่อมต่อ สร้างอัลบั้มและอัปโหลดไม่ได้จนกว่าจะเชื่อมต่อ
                  </p>
                )}
              </div>

              {isSuperAdmin ? (
                <Button onClick={connect} disabled={busy || !status} variant={status?.connected ? 'outlined' : 'filled'} className="mt-5">
                  {busy ? 'กำลังไปที่ Google…' : status?.connected ? 'เชื่อมต่อบัญชีใหม่' : 'เชื่อมต่อ Google Drive'}
                </Button>
              ) : (
                <p className="mt-5 text-sm text-muted">เฉพาะ SuperAdmin เชื่อมต่อหรือเปลี่ยนบัญชีได้</p>
              )}
            </div>
          </div>
        </section>

        <section className="mt-4 rounded-2xl border border-border/70 bg-surface p-5 sm:p-6" aria-labelledby="folders-heading">
          <div className="flex items-start gap-4">
            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-container text-muted">
              <FolderTree size={24} aria-hidden />
            </div>
            <div className="min-w-0">
              <h2 id="folders-heading" className="text-lg font-medium text-ink">
                โครงสร้างโฟลเดอร์
              </h2>
              <p className="mt-1 text-sm text-muted">แยกตามปีและเดือนของวันที่รายงาน</p>
              <p className="mt-3 break-words rounded-xl bg-container px-4 py-3 font-mono text-[13px] text-ink">
                {drivePathLabel('2026-10-12')} / เทปูนชั้น 2
              </p>
              <p className="mt-3 text-sm text-muted">
                แอปเห็นเฉพาะไฟล์ที่สร้างผ่านแอปนี้ในโฟลเดอร์ “{ROOT_FOLDER_NAME}” ถ้าลบหรือย้ายโฟลเดอร์ใน Drive เอง รูปในอัลบั้มจะหายไปด้วย
              </p>
            </div>
          </div>
        </section>
      </main>
    </div>
  );
}
