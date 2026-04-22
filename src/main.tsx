import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.tsx'
import './index.css'
import DebugErrorBoundary from './components/DebugErrorBoundary'
import { SessionDialogProvider } from './context/SessionDialogContext'
import E2EHarness from './e2e/E2EHarness'

const search = new URLSearchParams(window.location.search)
const isE2EHarness = search.get('e2e') === 'harness'

if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js').catch((err) => {
            console.error('Service worker registration failed', err)
        })
    })
}

ReactDOM.createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
        <DebugErrorBoundary>
            <SessionDialogProvider>
                {isE2EHarness ? <E2EHarness /> : <App />}
            </SessionDialogProvider>
        </DebugErrorBoundary>
    </React.StrictMode>,
)
