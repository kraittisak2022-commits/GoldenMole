import { describe, expect, it } from 'vitest';
import { buildPayerSummaries } from './reimbursements';
import type { FaReimbursement } from '../types';

describe('buildPayerSummaries', () => {
  const rows: FaReimbursement[] = [
    {
      id: '1',
      date: '2026-08-01',
      payerName: 'สมชาย',
      payerId: 'p1',
      description: 'a',
      amount: 100,
      status: 'pending',
    },
    {
      id: '2',
      date: '2026-08-02',
      payerName: 'สมชาย',
      payerId: 'p1',
      description: 'b',
      amount: 200,
      status: 'approved',
      repaymentProofUrl: 'https://x',
      repaidAt: '2026-08-10',
    },
    {
      id: '3',
      date: '2026-08-03',
      payerName: 'สมหญิง',
      payerId: 'p2',
      description: 'c',
      amount: 50,
      status: 'approved',
    },
    {
      id: '4',
      date: '2026-08-04',
      payerName: 'สมชาย',
      payerId: 'p1',
      description: 'd',
      amount: 10,
      status: 'rejected',
    },
  ];

  it('aggregates totals and repayment status per payer', () => {
    const summary = buildPayerSummaries(rows);
    expect(summary).toHaveLength(2);
    expect(summary[0]).toMatchObject({
      payerName: 'สมชาย',
      totalPaid: 300,
      pendingAmount: 100,
      approvedAmount: 200,
      repaidAmount: 200,
      unpaidApprovedAmount: 0,
      claimCount: 2,
    });
    expect(summary[1]).toMatchObject({
      payerName: 'สมหญิง',
      totalPaid: 50,
      unpaidApprovedAmount: 50,
      repaidAmount: 0,
    });
  });
});
