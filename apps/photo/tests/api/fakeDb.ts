export interface Query {
  table: string;
  op: 'select' | 'insert' | 'update' | 'delete';
  filters: Record<string, unknown>;
  payload?: unknown;
}
export type Result = { data: unknown; error: { message: string } | null; count?: number | null };

/** What each query returns, plus every query seen, for assertions. Tests replace `respond`. */
export const fake = {
  respond: (_q: Query): Result => ({ data: null, error: null }),
  queries: [] as Query[],
};

const FILTERS = ['eq', 'is', 'gte', 'lt', 'in', 'like', 'ilike'];

/** Chainable stand-in for the supabase-js query builder. */
function builder(q: Query): unknown {
  return new Proxy(
    {},
    {
      get(_t, prop: string) {
        if (prop === 'then') {
          return (resolve: (r: Result) => void) => {
            fake.queries.push(q);
            resolve(fake.respond(q));
          };
        }
        return (...args: unknown[]) => {
          if (FILTERS.includes(prop)) q.filters[String(args[0])] = args[1];
          if (prop === 'insert' || prop === 'update' || prop === 'delete') {
            q.op = prop;
            q.payload = args[0];
          }
          return builder(q);
        };
      },
    },
  );
}

export const supabaseAdminMock = {
  db: () => ({ from: (table: string) => builder({ table, op: 'select', filters: {} }) }),
  must: (r: Result) => {
    if (r.error) throw new Error(r.error.message);
    return r.data;
  },
};

export function resetFake(respond: (q: Query) => Result) {
  fake.respond = respond;
  fake.queries = [];
}
