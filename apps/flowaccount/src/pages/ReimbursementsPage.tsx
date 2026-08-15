import { FormEvent, useCallback, useEffect, useState } from 'react';
import { listCategories } from '../data/categories';
import {
  approveReimbursement,
  listReimbursements,
  rejectReimbursement,
  saveReimbursement,
} from '../data/reimbursements';
import type { FaCategory, FaReimbursement } from '../types';
import { formatMoney } from '../types';
import { useAuth } from '../auth/AuthProvider';
import Button from '../components/ui/Button';
import DataTable, { Column } from '../components/ui/DataTable';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import Modal from '../components/ui/Modal';
import MoneyInput from '../components/ui/MoneyInput';
import Select from '../components/ui/Select';
import StatusBadge from '../components/ui/StatusBadge';

const today = () => new Date().toISOString().slice(0, 10);

export default function ReimbursementsPage() {
  const { user } = useAuth();
  const [rows, setRows] = useState<FaReimbursement[]>([]);
  const [categories, setCategories] = useState<FaCategory[]>([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const [createOpen, setCreateOpen] = useState(false);
  const [approveOpen, setApproveOpen] = useState(false);
  const [selected, setSelected] = useState<FaReimbursement | null>(null);
  const [categoryId, setCategoryId] = useState('');

  const [date, setDate] = useState(today());
  const [payerName, setPayerName] = useState('');
  const [description, setDescription] = useState('');
  const [amount, setAmount] = useState<number | ''>('');

  const reload = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const [r, c] = await Promise.all([listReimbursements(), listCategories()]);
      setRows(r);
      setCategories(c.filter((x) => x.kind === 'expense' || x.kind === 'both'));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'โหลดไม่สำเร็จ');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  const submitCreate = async (e: FormEvent) => {
    e.preventDefault();
    if (amount === '') return;
    try {
      await saveReimbursement({
        date,
        payerName,
        description,
        amount: Number(amount),
      });
      setCreateOpen(false);
      setPayerName('');
      setDescription('');
      setAmount('');
      await reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
    }
  };

  const openApprove = (row: FaReimbursement) => {
    setSelected(row);
    setCategoryId(categories[0]?.id || '');
    setApproveOpen(true);
  };

  const submitApprove = async (e: FormEvent) => {
    e.preventDefault();
    if (!selected || !categoryId) return;
    try {
      await approveReimbursement({
        reimbursement: selected,
        categoryId,
        approvedBy: user?.username || user?.displayName || 'admin',
      });
      setApproveOpen(false);
      setSelected(null);
      await reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'อนุมัติไม่สำเร็จ');
    }
  };

  const columns: Column<FaReimbursement>[] = [
    { key: 'date', header: 'วันที่', render: (r) => r.date },
    { key: 'payer', header: 'ผู้สำรองจ่าย', render: (r) => r.payerName },
    { key: 'desc', header: 'รายการ', render: (r) => r.description },
    {
      key: 'amount',
      header: 'จำนวนเงิน',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.amount),
    },
    {
      key: 'status',
      header: 'สถานะ',
      render: (r) => <StatusBadge status={r.status} />,
    },
    {
      key: 'actions',
      header: '',
      render: (r) =>
        r.status === 'pending' ? (
          <div className="flex justify-end gap-2">
            <Button className="min-h-9" onClick={() => openApprove(r)}>
              อนุมัติการเบิกเงิน
            </Button>
            <Button
              variant="ghost"
              className="min-h-9"
              onClick={() => void rejectReimbursement(r.id).then(reload)}
            >
              ปฏิเสธ
            </Button>
          </div>
        ) : null,
    },
  ];

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight">เบิกสำรองจ่าย</h2>
          <p className="mt-1 text-sm text-muted">
            เมื่ออนุมัติ ระบบจะถามหมวดบัญชีแล้วบันทึกลงสมุดรายรับ-รายจ่ายอัตโนมัติ
          </p>
        </div>
        <Button onClick={() => setCreateOpen(true)}>บันทึกสำรองจ่าย</Button>
      </div>

      {error ? <p className="text-sm text-destructive">{error}</p> : null}
      {loading ? <p className="text-sm text-muted">กำลังโหลด…</p> : <DataTable columns={columns} rows={rows} rowKey={(r) => r.id} />}

      <Modal
        open={createOpen}
        title="บันทึกสำรองจ่าย"
        onClose={() => setCreateOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setCreateOpen(false)}>
              ยกเลิก
            </Button>
            <Button type="submit" form="reimb-form">
              บันทึก
            </Button>
          </>
        }
      >
        <form id="reimb-form" className="space-y-4" onSubmit={submitCreate}>
          <Field id="r-date" label="วันที่">
            <Input id="r-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} required />
          </Field>
          <Field id="r-payer" label="ชื่อผู้สำรองจ่าย">
            <Input id="r-payer" value={payerName} onChange={(e) => setPayerName(e.target.value)} required />
          </Field>
          <Field id="r-desc" label="รายการที่จ่าย">
            <Input id="r-desc" value={description} onChange={(e) => setDescription(e.target.value)} required />
          </Field>
          <Field id="r-amt" label="จำนวนเงิน">
            <MoneyInput id="r-amt" value={amount} onValueChange={setAmount} required />
          </Field>
        </form>
      </Modal>

      <Modal
        open={approveOpen}
        title="อนุมัติการเบิกเงิน"
        onClose={() => setApproveOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setApproveOpen(false)}>
              ยกเลิก
            </Button>
            <Button type="submit" form="approve-form">
              ยืนยันอนุมัติ
            </Button>
          </>
        }
      >
        <form id="approve-form" className="space-y-4" onSubmit={submitApprove}>
          <p className="text-sm text-muted">
            {selected?.payerName} — {selected?.description} ({formatMoney(selected?.amount || 0)} บาท)
          </p>
          <Field id="a-cat" label="หมวดหมู่บัญชี">
            <Select id="a-cat" value={categoryId} onChange={(e) => setCategoryId(e.target.value)} required>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </Field>
        </form>
      </Modal>
    </div>
  );
}
