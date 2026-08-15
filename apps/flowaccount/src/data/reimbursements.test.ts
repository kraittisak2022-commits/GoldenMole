import { describe, expect, it, vi, beforeEach } from 'vitest';

const maybeSingle = vi.fn();
const select = vi.fn(() => ({ single: maybeSingle }));
const updateEq = vi.fn(() => ({ select: () => ({ single: maybeSingle }) }));
const update = vi.fn(() => ({ eq: updateEq }));
const upsertSelect = vi.fn(() => ({ single: maybeSingle }));
const upsert = vi.fn(() => ({ select: upsertSelect }));
const from = vi.fn((table: string) => {
  if (table === 'fa_ledger_entries') return { upsert };
  if (table === 'fa_reimbursements') return { update };
  return {};
});

vi.mock('../lib/supabase', () => ({
  supabase: { from: (t: string) => from(t) },
}));

describe('approveReimbursement', () => {
  beforeEach(() => {
    maybeSingle.mockReset();
    from.mockClear();
    upsert.mockClear();
    update.mockClear();
  });

  it('posts expense to ledger and marks reimbursement approved', async () => {
    maybeSingle
      .mockResolvedValueOnce({
        data: {
          id: 'led-new',
          date: '2026-08-08',
          description: 'เบิก',
          category_id: 'cat-repair',
          entry_type: 'expense',
          amount: 1500,
          source: 'reimbursement',
          source_id: 'reimb-1',
        },
        error: null,
      })
      .mockResolvedValueOnce({
        data: {
          id: 'reimb-1',
          date: '2026-08-08',
          payer_name: 'สมชาย',
          description: 'ซ่อมยาง',
          amount: 1500,
          status: 'approved',
          approved_category_id: 'cat-repair',
          ledger_entry_id: 'led-new',
          approved_by: 'boss',
          approved_at: '2026-08-15T00:00:00.000Z',
        },
        error: null,
      });

    const { approveReimbursement } = await import('./reimbursements');
    const result = await approveReimbursement({
      reimbursement: {
        id: 'reimb-1',
        date: '2026-08-08',
        payerName: 'สมชาย',
        description: 'ซ่อมยาง',
        quantity: 1,
        amount: 1500,
        status: 'pending',
      },
      categoryId: 'cat-repair',
      approvedBy: 'boss',
    });

    expect(result.status).toBe('approved');
    expect(result.ledgerEntryId).toBe('led-new');
    expect(upsert).toHaveBeenCalled();
    expect(update).toHaveBeenCalled();
  });

  it('rejects already-approved items', async () => {
    const { approveReimbursement } = await import('./reimbursements');
    await expect(
      approveReimbursement({
        reimbursement: {
          id: 'reimb-1',
          date: '2026-08-08',
          payerName: 'สมชาย',
          description: 'ซ่อมยาง',
          quantity: 1,
          amount: 1500,
          status: 'approved',
        },
        categoryId: 'cat-repair',
        approvedBy: 'boss',
      }),
    ).rejects.toThrow(/อนุมัติแล้ว/);
  });
});
