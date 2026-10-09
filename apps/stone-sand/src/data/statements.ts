import { supabase } from '../lib/supabase';
import { scoped } from './sourceScope';
import type { OrderSource, Statement, StatementPayment } from '../types';

const STATEMENT_SELECT =
  '*, links:ss_statement_orders(order_id),' +
  ' payments:ss_payments!ss_payments_statement_id_fkey(id, amount, method, paid_at, note, created_by)';

function mapPayment(p: any): StatementPayment {
  return {
    id: p.id,
    amount: Number(p.amount || 0),
    method: p.method === 'transfer' ? 'transfer' : 'cash',
    paidAt: p.paid_at,
    note: p.note || '',
    createdBy: p.created_by,
  };
}

export function mapStatement(row: any): Statement {
  const total = Number(row.total || 0);
  const payments = (row.payments || []).map(mapPayment).sort((a: StatementPayment, b: StatementPayment) => a.paidAt.localeCompare(b.paidAt));
  const paidAmount = payments.reduce((s: number, p: StatementPayment) => s + p.amount, 0);
  return {
    id: row.id,
    statementNo: row.statement_no,
    source: row.source === 'pit' ? 'pit' : 'shop',
    customerId: row.customer_id,
    customer: {
      name: row.customer_snapshot?.name || '',
      phone: row.customer_snapshot?.phone || '',
      address: row.customer_snapshot?.address || '',
      taxId: row.customer_snapshot?.taxId || '',
    },
    periodFrom: row.period_from,
    periodTo: row.period_to,
    total,
    status: row.status,
    paymentMethod: row.payment_method,
    clearedAt: row.cleared_at,
    verifyToken: row.verify_token,
    note: row.note || '',
    createdBy: row.created_by,
    createdAt: row.created_at,
    orderIds: (row.links || []).map((l: any) => l.order_id),
    payments,
    paidAmount,
    balance: row.status === 'cleared' ? 0 : Math.max(0, total - paidAmount),
    demo: !!row.demo_session,
  };
}

export async function listStatements(opts: { customerId?: string } = {}): Promise<Statement[]> {
  let q = scoped(supabase.from('ss_statements').select(STATEMENT_SELECT)).order('created_at', { ascending: false }).limit(300);
  if (opts.customerId) q = q.eq('customer_id', opts.customerId);
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return (data || []).map(mapStatement);
}

export async function getStatement(id: string): Promise<Statement | null> {
  const { data, error } = await scoped(supabase.from('ss_statements').select(STATEMENT_SELECT)).eq('id', id).maybeSingle();
  if (error) throw new Error(error.message);
  return data ? mapStatement(data) : null;
}

export async function createStatement(input: {
  source: OrderSource;
  customerId: string;
  orderIds: string[];
  from: string;
  to: string;
  note: string;
  by: string;
}): Promise<Statement> {
  const { data, error } = await supabase.rpc('ss_create_statement', {
    p_customer_id: input.customerId,
    p_order_ids: input.orderIds,
    p_from: input.from,
    p_to: input.to,
    p_note: input.note,
    p_by: input.by,
    p_source: input.source,
  });
  if (error) throw new Error(error.message);
  const s = await getStatement((data as any).id);
  if (!s) throw new Error('ไม่พบใบวางบิล');
  return s;
}

/** Records part (or the rest) of a statement; it clears once payments reach its total. */
export async function payStatement(input: {
  id: string;
  amount: number;
  method: 'cash' | 'transfer';
  note: string;
  by: string;
}): Promise<Statement> {
  const { error } = await supabase.rpc('ss_pay_statement', {
    p_statement_id: input.id,
    p_amount: input.amount,
    p_method: input.method,
    p_note: input.note,
    p_by: input.by,
  });
  if (error) throw new Error(error.message);
  const s = await getStatement(input.id);
  if (!s) throw new Error('ไม่พบใบวางบิล');
  return s;
}

export async function deleteStatementPayment(paymentId: string, by: string): Promise<void> {
  const { error } = await supabase.rpc('ss_delete_statement_payment', { p_payment_id: paymentId, p_by: by });
  if (error) throw new Error(error.message);
}

/** Works on cleared statements too: their orders go back to outstanding. */
export async function deleteStatement(id: string, by: string): Promise<void> {
  const { error } = await supabase.rpc('ss_delete_statement', { p_statement_id: id, p_by: by });
  if (error) throw new Error(error.message);
}

export interface VerifyResult {
  kind: 'order' | 'statement';
  docNo: string;
  receiptNo?: string | null;
  date: string;
  customer: string;
  total: number;
  paymentStatus: 'unpaid' | 'paid' | 'credit';
  cleared: boolean;
  cancelled: boolean;
}

export async function verifyDocument(token: string): Promise<VerifyResult | null> {
  const { data, error } = await supabase.rpc('ss_verify_document', { p_token: token });
  if (error) throw new Error(error.message);
  return (data as VerifyResult | null) ?? null;
}
