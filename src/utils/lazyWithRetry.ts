import { lazy, type ComponentType, type LazyExoticComponent } from 'react';
import { reloadOnceForStaleChunk } from './chunkReload';

type DefaultExportModule<T> = { default: T };

/**
 * React.lazy wrapper that auto-reloads once when a hashed chunk is missing after deploy.
 */
export function lazyWithRetry<T extends ComponentType<unknown>>(
    factory: () => Promise<DefaultExportModule<T>>,
): LazyExoticComponent<T> {
    return lazy(() =>
        factory().catch((err: unknown) => {
            if (reloadOnceForStaleChunk(err)) {
                return new Promise<DefaultExportModule<T>>(() => {});
            }
            throw err;
        }),
    );
}
