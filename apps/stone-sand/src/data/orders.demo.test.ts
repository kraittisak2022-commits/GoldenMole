import { demoCreditDraft } from '../tour/demoData';
import { endDemoSession, startDemoSession } from '../tour/tourSession';
import type { Customer, Product } from '../types';
import { createOrder } from './orders';

const rpc = vi.fn();

vi.mock('../lib/supabase', () => {
  const query = {
    select: () => query,
    eq: () => query,
    is: () => query,
    or: () => query,
    maybeSingle: async () => ({ data: { id: 'ord-1', order_no: 'DEMO-DO-1', demo_session: 'x', items: [] }, error: null }),
  };
  return {
    supabase: {
      rpc: (...args: unknown[]) => rpc(...args),
      from: () => query,
    },
  };
});

const customer: Customer = {
  id: 'cus-1',
  name: 'ลูกค้าตัวอย่าง',
  aliases: [],
  phone: '',
  address: '',
  zoneId: null,
  taxId: '',
  lat: null,
  lng: null,
  isCredit: true,
  note: '',
  createdAt: '2026-10-09',
};
const product: Product = { id: 'p1', name: 'ทราย', category: 'sand', unit: 'คิว', pricePerUnit: 500, sortOrder: 0, active: true };

const createCall = () => rpc.mock.calls.find((c) => c[0] === 'ss_create_order')!;

beforeEach(() => rpc.mockResolvedValue({ data: { id: 'ord-1' }, error: null }));
afterEach(() => {
  rpc.mockReset();
  endDemoSession();
});

describe('createOrder demo tagging', () => {
  it('sends demo_session while a tour runs and maps the demo flag back', async () => {
    const session = startDemoSession();
    const order = await createOrder(demoCreditDraft(customer, product, 'shop'), 'tester');
    const [, args] = createCall();
    expect(args.p_order.demo_session).toBe(session);
    expect(args.p_order.payment_status).toBe('credit');
    expect(args.p_items[0]).toMatchObject({ product_id: 'p1', quantity: 2, amount: 1000 });
    expect(order.demo).toBe(true);
  });

  it('sends no demo_session for normal orders', async () => {
    await createOrder(demoCreditDraft(customer, product, 'shop'), 'tester');
    expect(createCall()[1].p_order.demo_session).toBeNull();
  });
});
