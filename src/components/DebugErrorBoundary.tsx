import React, { Component, ErrorInfo, ReactNode } from 'react';

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
        errorInfo: null
    };

    public static getDerivedStateFromError(error: Error): State {
        return { hasError: true, error, errorInfo: null };
    }

    public componentDidCatch(error: Error, errorInfo: ErrorInfo) {
        console.error("Uncaught error:", error, errorInfo);
        this.setState({ error, errorInfo });
    }

    public render() {
        if (this.state.hasError) {
            return (
                <div style={{ padding: '2rem', backgroundColor: '#FEF2F2', color: '#991B1B', fontFamily: 'monospace', height: '100vh', overflow: 'auto' }}>
                    <h1 style={{ fontSize: '1.5rem', fontWeight: 'bold', marginBottom: '1rem' }}>Something went wrong</h1>
                    <div style={{ marginBottom: '1rem', padding: '1rem', backgroundColor: '#FCA5A5', borderRadius: '0.5rem', border: '1px solid #F87171' }}>
                        <strong>Error:</strong> {this.state.error?.toString()}
                    </div>
                    <details style={{ whiteSpace: 'pre-wrap' }}>
                        <summary style={{ cursor: 'pointer', marginBottom: '0.5rem' }}>Component Stack Trace</summary>
                        {this.state.errorInfo?.componentStack}
                    </details>
                </div>
            );
        }

        return this.props.children;
    }
}

export default DebugErrorBoundary;
