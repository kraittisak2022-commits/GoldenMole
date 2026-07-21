import React, { Suspense, lazy } from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.tsx'
import './index.css'
import DebugErrorBoundary from './components/DebugErrorBoundary'
import { SessionDialogProvider } from './context/SessionDialogContext'
import E2EHarness from './e2e/E2EHarness'
import ShareDashboardPage from './modules/Share/ShareDashboardPage'
import { setupChunkReloadRecovery } from './utils/chunkReload'
import { setupServiceWorkerUpdates } from './utils/serviceWorkerUpdate'

setupChunkReloadRecovery()

const KnowledgePage = lazy(() => import('./modules/Knowledge/KnowledgePage'))

const search = new URLSearchParams(window.location.search)
const isE2EHarness = search.get('e2e') === 'harness'
const shareToken = search.get('share')
const isShareView = !!shareToken
const isKnowledgeView = search.get('knowledge') === '1'

if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
        setupServiceWorkerUpdates()
    })
}

const knowledgeFallback = (
    <div className="min-h-screen flex items-center justify-center bg-slate-100 text-slate-600 text-sm">
        กำลังโหลดแบบจำลอง 3D…
    </div>
)

ReactDOM.createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
        <DebugErrorBoundary>
            <SessionDialogProvider>
                {isE2EHarness ? (
                    <E2EHarness />
                ) : isKnowledgeView ? (
                    <Suspense fallback={knowledgeFallback}>
                        <KnowledgePage />
                    </Suspense>
                ) : isShareView ? (
                    <ShareDashboardPage token={shareToken!} />
                ) : (
                    <App />
                )}
            </SessionDialogProvider>
        </DebugErrorBoundary>
    </React.StrictMode>,
)
