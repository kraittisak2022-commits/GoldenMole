import React from 'react';
import ReactDOM from 'react-dom/client';
import 'leaflet/dist/leaflet.css';
import App from './App';
import ErrorBoundary from './components/ErrorBoundary';
import { reloadOnce } from './lib/chunkReload';
import './styles/index.css';

window.addEventListener('vite:preloadError', (event) => {
  if (reloadOnce()) event.preventDefault();
});

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </React.StrictMode>,
);
