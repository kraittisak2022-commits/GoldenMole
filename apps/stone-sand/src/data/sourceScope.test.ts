import { canSeeSource, lockedSource, parseOrderSource, scoped, setLockedSource } from './sourceScope';

function fakeQuery() {
  const calls: [string, ...unknown[]][] = [];
  const q = {
    calls,
    eq(column: string, value: string) {
      calls.push(['eq', column, value]);
      return q;
    },
    is(column: string, value: null) {
      calls.push(['is', column, value]);
      return q;
    },
  };
  return q;
}

afterEach(() => {
  setLockedSource(null);
});

describe('sourceScope', () => {
  it('sees every source and hides all demo rows when not limited', () => {
    expect(lockedSource()).toBeNull();
    expect(canSeeSource('shop') && canSeeSource('pit')).toBe(true);
    expect(scoped(fakeQuery()).calls).toEqual([['is', 'demo_session', null]]);
  });

  it('limits queries and visibility to the locked source', () => {
    setLockedSource('shop');
    expect(canSeeSource('shop')).toBe(true);
    expect(canSeeSource('pit')).toBe(false);
    expect(scoped(fakeQuery()).calls).toEqual([
      ['eq', 'source', 'shop'],
      ['is', 'demo_session', null],
    ]);
  });

  it('parses only known sources from the database', () => {
    expect(parseOrderSource('pit')).toBe('pit');
    expect(parseOrderSource(null)).toBeNull();
    expect(parseOrderSource('other')).toBeNull();
  });
});
