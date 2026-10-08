/**
 * The guided-tour demo session. Rows created while it is set carry demo_session = this id:
 * the database gives them DEMO- document numbers and only this browser lists them.
 */
const KEY = 'stone_sand_demo_session_v1';

function read(): string | null {
  try {
    const v = localStorage.getItem(KEY);
    return v && v.startsWith('demo-') ? v : null;
  } catch {
    return null;
  }
}

let session: string | null = read();

export function demoSession(): string | null {
  return session;
}

export function startDemoSession(): string {
  session = `demo-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
  try {
    localStorage.setItem(KEY, session);
  } catch {
    // private mode: the tour still works until reload
  }
  return session;
}

export function endDemoSession(): void {
  session = null;
  try {
    localStorage.removeItem(KEY);
  } catch {
    // ignore
  }
}

/** Real rows always; demo rows only for the current session. */
export function demoFilter<Q>(q: Q): Q {
  const f = q as unknown as { is: (column: string, value: null) => Q; or: (filters: string) => Q };
  return session ? f.or(`demo_session.is.null,demo_session.eq.${session}`) : f.is('demo_session', null);
}

export function isVisibleDemo(demoSessionValue: string | null | undefined): boolean {
  return !demoSessionValue || demoSessionValue === session;
}
