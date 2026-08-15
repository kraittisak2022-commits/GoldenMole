import { supabase } from '../lib/supabase';
import type { FaReimbursement, PayerReimbSummary } from '../types';
import { newId } from '../types';
import { saveLedgerEntry } from './ledger';

const map = (row: any): FaReimbursement => ({
  id: row.id,
  date: row.date,
  payerName: row.payer_name,
  payerId: row.payer_id,
  description: row.description || '',
  quantity: Number(row.quantity) > 0 ? Number(row.quantity) : 1,
  amount: Number(row.amount) || 0,
  status: row.status,
  approvedCategoryId: row.approved_category_id,
  ledgerEntryId: row.ledger_entry_id,
  approvedBy: row.approved_by,
  approvedAt: row.approved_at,
  receiptUrl: row.receipt_url,
  repaymentProofUrl: row.repayment_proof_url,
  repaidAt: row.repaid_at,
  createdAt: row.created_at,
});

export async function listReimbursements(opts?: { payerId?: string }): Promise<FaReimbursement[]> {
  let q = supabase.from('fa_reimbursements').select('*').order('date', { ascending: false });
  if (opts?.payerId) q = q.eq('payer_id', opts.payerId);
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return (data || []).map(map);
}

export async function saveReimbursement(input: {
  id?: string;
  date: string;
  payerName: string;
  payerId?: string | null;
  description: string;
  quantity?: number;
  amount: number;
  receiptUrl?: string | null;
}): Promise<FaReimbursement> {
  const id = input.id || newId('reimb');
  const quantity = Number(input.quantity);
  const row = {
    id,
    date: input.date,
    payer_name: input.payerName.trim(),
    payer_id: input.payerId || null,
    description: input.description.trim(),
    quantity: quantity > 0 ? quantity : 1,
    amount: Number(input.amount) || 0,
    status: 'pending',
    receipt_url: input.receiptUrl || null,
  };
  const { data, error } = await supabase.from('fa_reimbursements').upsert(row).select('*').single();
  if (error) throw new Error(error.message);
  return map(data);
}

export async function saveReimbursementBatch(input: {
  date: string;
  payerName: string;
  payerId?: string | null;
  items: Array<{ description: string; quantity?: number; amount: number; receiptUrl?: string | null }>;
}): Promise<FaReimbursement[]> {
  const cleaned = input.items
    .map((item) => ({
      description: item.description.trim(),
      quantity: Number(item.quantity) > 0 ? Number(item.quantity) : 1,
      amount: Number(item.amount) || 0,
      receiptUrl: item.receiptUrl || null,
    }))
    .filter((item) => item.description && item.amount > 0);
  if (!cleaned.length) throw new Error('กรุณาเพิ่มอย่างน้อย 1 รายการ');

  const results: FaReimbursement[] = [];
  for (const item of cleaned) {
    results.push(
      await saveReimbursement({
        date: input.date,
        payerName: input.payerName,
        payerId: input.payerId,
        description: item.description,
        quantity: item.quantity,
        amount: item.amount,
        receiptUrl: item.receiptUrl,
      }),
    );
  }
  return results;
}

export async function approveReimbursement(input: {
  reimbursement: FaReimbursement;
  categoryId: string;
  approvedBy: string;
}): Promise<FaReimbursement> {
  if (input.reimbursement.status === 'approved') {
    throw new Error('รายการนี้ถูกอนุมัติแล้ว');
  }

  // Ledger posts only after repayment proof — see attachRepaymentProof.
  const { data, error } = await supabase
    .from('fa_reimbursements')
    .update({
      status: 'approved',
      approved_category_id: input.categoryId,
      approved_by: input.approvedBy,
      approved_at: new Date().toISOString(),
    })
    .eq('id', input.reimbursement.id)
    .select('*')
    .single();

  if (error) throw new Error(error.message);
  return map(data);
}

export async function rejectReimbursement(id: string): Promise<void> {
  const { error } = await supabase
    .from('fa_reimbursements')
    .update({ status: 'rejected' })
    .eq('id', id)
    .eq('status', 'pending');
  if (error) throw new Error(error.message);
}

/** True when company has repaid the advance and the claim should leave the active list. */
export function isReimbursementMovedToLedger(row: FaReimbursement): boolean {
  return Boolean(row.repaidAt || row.repaymentProofUrl);
}

/** Marker stored in repayment_proof_url when repaid in cash (no slip file). */
export const CASH_REPAYMENT_MARKER = 'cash';

export function isCashRepayment(row: FaReimbursement): boolean {
  return row.repaymentProofUrl === CASH_REPAYMENT_MARKER;
}

export async function markReimbursementRepaid(input: {
  id: string;
  method: 'slip' | 'cash';
  proofUrl?: string | null;
}): Promise<FaReimbursement> {
  if (input.method === 'slip' && !input.proofUrl) {
    throw new Error('กรุณาแนบไฟล์สลิป');
  }

  const { data: existing, error: fetchError } = await supabase
    .from('fa_reimbursements')
    .select('*')
    .eq('id', input.id)
    .single();
  if (fetchError) throw new Error(fetchError.message);
  if (!existing) throw new Error('ไม่พบรายการเบิก');

  const claim = map(existing);
  if (claim.status !== 'approved') {
    throw new Error('ต้องอนุมัติรายการก่อนบันทึกการจ่ายคืน');
  }
  if (!claim.approvedCategoryId) {
    throw new Error('รายการยังไม่มีหมวดหมู่ที่อนุมัติ');
  }

  let ledgerEntryId = claim.ledgerEntryId || null;
  if (!ledgerEntryId) {
    const ledger = await saveLedgerEntry({
      date: claim.date,
      description: `เบิกสำรองจ่าย: ${claim.description} (${claim.payerName})`,
      categoryId: claim.approvedCategoryId,
      entryType: 'expense',
      quantity: claim.quantity,
      amount: claim.amount,
      source: 'reimbursement',
      sourceId: claim.id,
      createdBy: claim.approvedBy || null,
    });
    ledgerEntryId = ledger.id;
  }

  const proofValue = input.method === 'cash' ? CASH_REPAYMENT_MARKER : input.proofUrl!;

  const { data, error } = await supabase
    .from('fa_reimbursements')
    .update({
      repayment_proof_url: proofValue,
      repaid_at: new Date().toISOString(),
      ledger_entry_id: ledgerEntryId,
    })
    .eq('id', input.id)
    .select('*')
    .single();
  if (error) throw new Error(error.message);
  return map(data);
}

export async function attachRepaymentProof(input: {
  id: string;
  proofUrl: string;
}): Promise<FaReimbursement> {
  return markReimbursementRepaid({ id: input.id, method: 'slip', proofUrl: input.proofUrl });
}

export function buildPayerSummaries(rows: FaReimbursement[]): PayerReimbSummary[] {
  const mapByKey = new Map<string, PayerReimbSummary>();
  for (const row of rows) {
    if (row.status === 'rejected') continue;
    const key = row.payerId || `name:${row.payerName}`;
    const current = mapByKey.get(key) || {
      payerId: row.payerId || null,
      payerName: row.payerName,
      totalPaid: 0,
      pendingAmount: 0,
      approvedAmount: 0,
      repaidAmount: 0,
      unpaidApprovedAmount: 0,
      claimCount: 0,
    };
    current.totalPaid += row.amount;
    current.claimCount += 1;
    if (row.status === 'pending') current.pendingAmount += row.amount;
    if (row.status === 'approved') {
      current.approvedAmount += row.amount;
      if (row.repaidAt || row.repaymentProofUrl) current.repaidAmount += row.amount;
      else current.unpaidApprovedAmount += row.amount;
    }
    mapByKey.set(key, current);
  }
  return [...mapByKey.values()].sort((a, b) => b.totalPaid - a.totalPaid || a.payerName.localeCompare(b.payerName, 'th'));
}
