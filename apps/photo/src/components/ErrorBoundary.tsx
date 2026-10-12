import { Component, type ErrorInfo, type ReactNode } from 'react';

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
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div className="flex min-h-[100dvh] items-center justify-center bg-page px-6">
        <div className="w-full max-w-sm text-center">
          <h1 className="text-xl font-medium">หน้านี้โหลดไม่สำเร็จ</h1>
          <p className="mt-2 text-sm text-muted">ลองโหลดหน้าใหม่อีกครั้ง</p>
          <button
            type="button"
            onClick={() => window.location.reload()}
            className="mt-6 min-h-11 cursor-pointer rounded-full bg-primary px-6 text-sm font-medium text-primary-foreground"
          >
            โหลดใหม่
          </button>
        </div>
      </div>
    );
  }
}
