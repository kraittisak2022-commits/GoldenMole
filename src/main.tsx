import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.tsx'
import './index.css'
import DebugErrorBoundary from './components/DebugErrorBoundary'
import { SessionDialogProvider } from './context/SessionDialogContext'

ReactDOM.createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
        <DebugErrorBoundary>
            <SessionDialogProvider>
                <App />
            </SessionDialogProvider>
        </DebugErrorBoundary>
    </React.StrictMode>,
)
