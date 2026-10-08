import { useEffect, useRef } from 'react';
import { useLocation } from 'react-router-dom';
import { fetchLatestBuildId, isOutdated } from '../lib/versionCheck';

const CHECK_EVERY_MS = 5 * 60 * 1000;

/**
 * Reloads into the latest deploy: right away when the app comes back to the foreground,
 * otherwise on the next page change so nobody loses what they are typing.
 * The new-order draft lives in sessionStorage, so it survives the reload.
 */
export default function VersionWatcher() {
  const { pathname } = useLocation();
  const outdated = useRef(false);

  useEffect(() => {
    if (__BUILD_ID__ === 'dev') return;
    let cancelled = false;

    const check = async () => {
      if (outdated.current) return true;
      outdated.current = isOutdated(__BUILD_ID__, await fetchLatestBuildId());
      return outdated.current;
    };
    const onVisible = async () => {
      if (document.visibilityState !== 'visible') return;
      if ((await check()) && !cancelled) window.location.reload();
    };

    void check();
    const timer = window.setInterval(() => void check(), CHECK_EVERY_MS);
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, []);

  useEffect(() => {
    if (outdated.current) window.location.reload();
  }, [pathname]);

  return null;
}
