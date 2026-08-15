import { describe, expect, it, vi, beforeEach } from 'vitest';

const maybeSingle = vi.fn();
const select = vi.fn(() => ({ single: maybeSingle }));
const updateEq = vi.fn(() => ({ select: () => ({ single: maybeSingle }) }));
const update = vi.fn(() => ({ eq: updateEq }));
const upsertSelect = vi.fn(() => ({ single: maybeSingle }));
const upsert = vi.fn(() => ({ select: upsertSelect }));
const eqChain = {
  single: maybeSingle,
  eq: vi.fn(function eq() {
    return eqChain;
  }),
};
const from = vi.fn((table: string) => {
  if (table === 'fa_ledger_entries') return { upsert };
  if (table === 'fa_reimbursements') return { update, select: () => eqChain };
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

  it('marks reimbursement approved without posting ledger yet', async () => {
    maybeSingle.mockResolvedValueOnce({
      data: {
        id: 'reimb-1',
        date: '2026-08-08',
        payer_name: 'สมชาย',
        description: 'ซ่อมยาง',
        quantity: 1,
        amount: 1500,
        status: 'approved',
        approved_category_id: 'cat-repair',
        ledger_entry_id: null,
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
    expect(result.ledgerEntryId).toBeNull();
    expect(upsert).not.toHaveBeenCalled();
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

describe('attachRepaymentProof', () => {
  beforeEach(() => {
    maybeSingle.mockReset();
    from.mockClear();
    upsert.mockClear();
    update.mockClear();
  });

  it('posts ledger with claim date then marks repaid', async () => {
    maybeSingle
      .mockResolvedValueOnce({
        data: {
          id: 'reimb-1',
          date: '2026-07-24',
          payer_name: 'สมชาย',
          description: 'ของใช้ทั่วไป',
          quantity: 1,
          amount: 200,
          status: 'approved',
          approved_category_id: 'cat-general',
          ledger_entry_id: null,
        },
        error: null,
      })
      .mockResolvedValueOnce({
        data: {
          id: 'led-new',
          date: '2026-07-24',
          description: 'เบิกสำรองจ่าย: ของใช้ทั่วไป (สมชาย)',
          category_id: 'cat-general',
          entry_type: 'expense',
          quantity: 1,
          amount: 200,
          source: 'reimbursement',
          source_id: 'reimb-1',
        },
        error: null,
      })
      .mockResolvedValueOnce({
        data: {
          id: 'reimb-1',
          date: '2026-07-24',
          payer_name: 'สมชาย',
          description: 'ของใช้ทั่วไป',
          quantity: 1,
          amount: 200,
          status: 'approved',
          approved_category_id: 'cat-general',
          ledger_entry_id: 'led-new',
          repayment_proof_url: 'https://example.com/slip.jpg',
          repaid_at: '2026-08-15T00:00:00.000Z',
        },
        error: null,
      });

    const { attachRepaymentProof } = await import('./reimbursements');
    const result = await attachRepaymentProof({
      id: 'reimb-1',
      proofUrl: 'https://example.com/slip.jpg',
    });

    expect(upsert).toHaveBeenCalled();
    const ledgerPayload = upsert.mock.calls[0][0];
    expect(ledgerPayload.date).toBe('2026-07-24');
    expect(ledgerPayload.source).toBe('reimbursement');
    expect(result.ledgerEntryId).toBe('led-new');
    expect(result.repaymentProofUrl).toBe('https://example.com/slip.jpg');
  });
});
