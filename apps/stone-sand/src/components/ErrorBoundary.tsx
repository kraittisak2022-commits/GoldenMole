import { Component, type ErrorInfo, type ReactNode } from 'react';
import { RefreshCw } from 'lucide-react';
import { isChunkLoadError, reloadOnce } from '../lib/chunkReload';

interface State {
  error: Error | null;
}

export default class ErrorBoundary extends Component<{ children: ReactNode }, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('App crashed', error, info.componentStack);
    if (isChunkLoadError(error)) reloadOnce();
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    const stale = isChunkLoadError(error);
    return (
      <div className="flex min-h-[100dvh] items-center justify-center bg-page px-6">
        <div className="w-full max-w-sm text-center">
          <h1 className="text-xl font-semibold">{stale ? 'มีเวอร์ชันใหม่ของระบบ' : 'หน้านี้โหลดไม่สำเร็จ'}</h1>
          <p className="mt-2 text-sm text-muted">
            {stale ? 'กดโหลดใหม่เพื่อใช้งานเวอร์ชันล่าสุด' : 'ลองโหลดหน้าใหม่ ถ้ายังไม่ได้ให้กลับไปหน้าหลัก'}
          </p>
          <div className="mt-6 flex flex-col gap-3">
            <button
              type="button"
              onClick={() => window.location.reload()}
              className="inline-flex min-h-12 items-center justify-center gap-2 rounded bg-primary px-5 font-medium text-primary-foreground hover:bg-primary-hover cursor-pointer"
            >
              <RefreshCw size={18} aria-hidden /> โหลดใหม่
            </button>
            <a href="/" className="inline-flex min-h-12 items-center justify-center rounded border border-border px-5 font-medium hover:bg-subtle">
              กลับหน้าหลัก
            </a>
          </div>
          {!stale ? <p className="mt-6 break-words text-xs text-muted">{error.message}</p> : null}
        </div>
      </div>
    );
  }
}
