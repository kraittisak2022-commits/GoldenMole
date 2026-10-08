import { supabase } from '../lib/supabase';
import type { OrderSource, Statement } from '../types';

const STATEMENT_SELECT = '*, links:ss_statement_orders(order_id)';

export function mapStatement(row: any): Statement {
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
    total: Number(row.total || 0),
    status: row.status,
    paymentMethod: row.payment_method,
    clearedAt: row.cleared_at,
    verifyToken: row.verify_token,
    note: row.note || '',
    createdBy: row.created_by,
    createdAt: row.created_at,
    orderIds: (row.links || []).map((l: any) => l.order_id),
  };
}

export async function listStatements(opts: { customerId?: string } = {}): Promise<Statement[]> {
  let q = supabase.from('ss_statements').select(STATEMENT_SELECT).order('created_at', { ascending: false }).limit(300);
  if (opts.customerId) q = q.eq('customer_id', opts.customerId);
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return (data || []).map(mapStatement);
}

export async function getStatement(id: string): Promise<Statement | null> {
  const { data, error } = await supabase.from('ss_statements').select(STATEMENT_SELECT).eq('id', id).maybeSingle();
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

export async function clearStatement(id: string, method: 'cash' | 'transfer', by: string): Promise<Statement> {
  const { error } = await supabase.rpc('ss_clear_statement', { p_statement_id: id, p_method: method, p_by: by });
  if (error) throw new Error(error.message);
  const s = await getStatement(id);
  if (!s) throw new Error('ไม่พบใบวางบิล');
  return s;
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
