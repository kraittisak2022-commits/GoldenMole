import { Component, ErrorInfo, ReactNode } from 'react';
import { isChunkLoadError, reloadOnceForStaleChunk } from '../utils/chunkReload';

interface Props {
    children: ReactNode;
}

interface State {
    hasError: boolean;
    error: Error | null;
    errorInfo: ErrorInfo | null;
}

class DebugErrorBoundary extends Component<Props, State> {
    public state: State = {
        hasError: false,
        error: null,
        errorInfo: null,
    };

    public static getDerivedStateFromError(error: Error): State {
        return { hasError: true, error, errorInfo: null };
    }

    public componentDidCatch(error: Error, errorInfo: ErrorInfo) {
        console.error('Uncaught error:', error, errorInfo);
        if (isChunkLoadError(error) && reloadOnceForStaleChunk(error)) {
            return;
        }
        this.setState({ error, errorInfo });
    }

    private handleReload = () => {
        window.location.reload();
    };

    public render() {
        if (this.state.hasError) {
            const chunkError = isChunkLoadError(this.state.error);
            return (
                <div
                    style={{
                        padding: '2rem',
                        backgroundColor: '#FEF2F2',
                        color: '#991B1B',
                        fontFamily: 'system-ui, sans-serif',
                        minHeight: '100vh',
                        overflow: 'auto',
                    }}
                >
                    <h1 style={{ fontSize: '1.5rem', fontWeight: 'bold', marginBottom: '1rem' }}>
                        {chunkError ? 'มีเวอร์ชันใหม่ — กรุณารีเฟรช' : 'Something went wrong'}
                    </h1>
                    <div
                        style={{
                            marginBottom: '1rem',
                            padding: '1rem',
                            backgroundColor: '#FCA5A5',
                            borderRadius: '0.5rem',
                            border: '1px solid #F87171',
                        }}
                    >
                        {chunkError ? (
                            <p style={{ margin: 0, lineHeight: 1.5 }}>
                                แอปอัปเดตแล้ว แต่เบราว์เซอร์ยังใช้ไฟล์เก่าอยู่ กดปุ่มด้านล่างเพื่อโหลดเวอร์ชันล่าสุด
                            </p>
                        ) : (
                            <>
                                <strong>Error:</strong> {this.state.error?.toString()}
                            </>
                        )}
                    </div>
                    {chunkError && (
                        <button
                            type="button"
                            onClick={this.handleReload}
                            style={{
                                marginBottom: '1rem',
                                padding: '0.75rem 1.25rem',
                                borderRadius: '0.5rem',
                                border: 'none',
                                background: '#991B1B',
                                color: 'white',
                                fontWeight: 600,
                                cursor: 'pointer',
                            }}
                        >
                            รีเฟรชหน้า
                        </button>
                    )}
                    {!chunkError && (
                        <details style={{ whiteSpace: 'pre-wrap', fontFamily: 'monospace' }}>
                            <summary style={{ cursor: 'pointer', marginBottom: '0.5rem' }}>Component Stack Trace</summary>
                            {this.state.errorInfo?.componentStack}
                        </details>
                    )}
                </div>
            );
        }

        return this.props.children;
    }
}

export default DebugErrorBoundary;
