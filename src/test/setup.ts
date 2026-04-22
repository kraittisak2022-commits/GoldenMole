import '@testing-library/jest-dom/vitest';

if (!window.matchMedia) {
    Object.defineProperty(window, 'matchMedia', {
        writable: true,
        value: (query: string) => ({
            matches: false,
            media: query,
            onchange: null,
            addListener: () => {},
            removeListener: () => {},
            addEventListener: () => {},
            removeEventListener: () => {},
            dispatchEvent: () => false,
        }),
    });
}

if (!globalThis.ResizeObserver) {
    class ResizeObserverMock {
        private callback: ResizeObserverCallback;
        constructor(callback: ResizeObserverCallback) {
            this.callback = callback;
        }
        observe(target: Element) {
            this.callback(
                [
                    {
                        target,
                        contentRect: { x: 0, y: 0, width: 900, height: 560, top: 0, left: 0, right: 900, bottom: 560, toJSON: () => ({}) },
                    } as ResizeObserverEntry,
                ],
                this as unknown as ResizeObserver
            );
        }
        unobserve() {}
        disconnect() {}
    }
    // @ts-expect-error test polyfill
    globalThis.ResizeObserver = ResizeObserverMock;
}

Object.defineProperty(HTMLElement.prototype, 'clientHeight', {
    configurable: true,
    get() {
        return 560;
    },
});

Object.defineProperty(HTMLElement.prototype, 'clientWidth', {
    configurable: true,
    get() {
        return 900;
    },
});
