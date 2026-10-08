import { canSeeSource, lockedSource, parseOrderSource, scoped, setLockedSource } from './sourceScope';

function fakeQuery() {
  const calls: [string, string][] = [];
  const q = {
    calls,
    eq(column: string, value: string) {
      calls.push([column, value]);
      return q;
    },
  };
  return q;
}

afterEach(() => setLockedSource(null));

describe('sourceScope', () => {
  it('sees everything and leaves queries alone when not limited', () => {
    expect(lockedSource()).toBeNull();
    expect(canSeeSource('shop') && canSeeSource('pit')).toBe(true);
    expect(scoped(fakeQuery()).calls).toEqual([]);
  });

  it('limits queries and visibility to the locked source', () => {
    setLockedSource('shop');
    expect(canSeeSource('shop')).toBe(true);
    expect(canSeeSource('pit')).toBe(false);
    expect(scoped(fakeQuery()).calls).toEqual([['source', 'shop']]);
  });

  it('parses only known sources from the database', () => {
    expect(parseOrderSource('pit')).toBe('pit');
    expect(parseOrderSource(null)).toBeNull();
    expect(parseOrderSource('other')).toBeNull();
  });
});
