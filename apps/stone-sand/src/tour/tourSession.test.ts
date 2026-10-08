import { demoSession, endDemoSession, isVisibleDemo, startDemoSession } from './tourSession';

afterEach(() => endDemoSession());

describe('tourSession', () => {
  it('starts, persists and ends a demo session', () => {
    expect(demoSession()).toBeNull();
    const id = startDemoSession();
    expect(id).toMatch(/^demo-/);
    expect(demoSession()).toBe(id);
    expect(localStorage.getItem('stone_sand_demo_session_v1')).toBe(id);
    endDemoSession();
    expect(demoSession()).toBeNull();
    expect(localStorage.getItem('stone_sand_demo_session_v1')).toBeNull();
  });

  it('shows real rows always and demo rows only for the current session', () => {
    expect(isVisibleDemo(null)).toBe(true);
    expect(isVisibleDemo('demo-other')).toBe(false);
    const id = startDemoSession();
    expect(isVisibleDemo(id)).toBe(true);
    expect(isVisibleDemo('demo-other')).toBe(false);
  });
});
