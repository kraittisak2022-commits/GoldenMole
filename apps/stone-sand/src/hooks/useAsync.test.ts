import { act, renderHook, waitFor } from '@testing-library/react';
import { clearAsyncCache, useAsync } from './useAsync';

afterEach(() => clearAsyncCache());

describe('useAsync cache', () => {
  it('shows the last result at once on the next mount, then refreshes it', async () => {
    const first = renderHook(() => useAsync(() => Promise.resolve(['a']), [], 'list'));
    await waitFor(() => expect(first.result.current.data).toEqual(['a']));
    first.unmount();

    let resolve: (v: string[]) => void = () => {};
    const second = renderHook(() => useAsync(() => new Promise<string[]>((r) => (resolve = r)), [], 'list'));
    expect(second.result.current.data).toEqual(['a']);
    await act(async () => resolve(['a', 'b']));
    expect(second.result.current.data).toEqual(['a', 'b']);
  });

  it('keeps results for different deps apart', async () => {
    const { result, rerender } = renderHook(({ id }) => useAsync(() => Promise.resolve(`order ${id}`), [id], 'order'), {
      initialProps: { id: 1 },
    });
    await waitFor(() => expect(result.current.data).toBe('order 1'));
    rerender({ id: 2 });
    await waitFor(() => expect(result.current.data).toBe('order 2'));

    const again = renderHook(() => useAsync(() => new Promise<string>(() => {}), [1], 'order'));
    expect(again.result.current.data).toBe('order 1');
  });

  it('setData updates the cache; no key means no cache', async () => {
    const a = renderHook(() => useAsync(() => Promise.resolve(1), [], 'n'));
    await waitFor(() => expect(a.result.current.data).toBe(1));
    act(() => a.result.current.setData(5));
    a.unmount();
    expect(renderHook(() => useAsync(() => new Promise<number>(() => {}), [], 'n')).result.current.data).toBe(5);
    expect(renderHook(() => useAsync(() => new Promise<number>(() => {}), [])).result.current.data).toBeUndefined();
  });
});
