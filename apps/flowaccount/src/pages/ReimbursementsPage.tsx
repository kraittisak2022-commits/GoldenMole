import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { listCategories } from '../data/categories';
import { listPayers, payerClaimUrl, savePayer, setPayerInactive } from '../data/payers';
import { uploadReimbProof } from '../data/reimbProof';
import {
  approveReimbursement,
  attachRepaymentProof,
  buildPayerSummaries,
  listReimbursements,
  rejectReimbursement,
  saveReimbursementBatch,
} from '../data/reimbursements';
import type { FaCategory, FaReimbPayer, FaReimbursement } from '../types';
import { formatMoney } from '../types';
import { useAuth } from '../auth/AuthProvider';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import DataTable, { Column } from '../components/ui/DataTable';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import Modal from '../components/ui/Modal';
import MoneyInput from '../components/ui/MoneyInput';
import Select from '../components/ui/Select';
import StatusBadge from '../components/ui/StatusBadge';

const today = () => new Date().toISOString().slice(0, 10);

type LineItem = { description: string; amount: number | '' };

export default function ReimbursementsPage() {
  const { user } = useAuth();
  const [rows, setRows] = useState<FaReimbursement[]>([]);
  const [payers, setPayers] = useState<FaReimbPayer[]>([]);
  const [categories, setCategories] = useState<FaCategory[]>([]);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [loading, setLoading] = useState(true);

  const [createOpen, setCreateOpen] = useState(false);
  const [payerOpen, setPayerOpen] = useState(false);
  const [approveOpen, setApproveOpen] = useState(false);
  const [proofOpen, setProofOpen] = useState(false);
  const [selected, setSelected] = useState<FaReimbursement | null>(null);
  const [categoryId, setCategoryId] = useState('');
  const [proofBusy, setProofBusy] = useState(false);

  const [date, setDate] = useState(today());
  const [payerId, setPayerId] = useState('');
  const [items, setItems] = useState<LineItem[]>([{ description: '', amount: '' }]);
  const [newPayerName, setNewPayerName] = useState('');

  const reload = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const [r, c, p] = await Promise.all([
        listReimbursements(),
        listCategories(),
        listPayers({ includeInactive: true }),
      ]);
      setRows(r);
      setCategories(c.filter((x) => x.kind === 'expense' || x.kind === 'both'));
      setPayers(p);
      setPayerId((prev) => prev || p.find((x) => !x.inactive)?.id || '');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'โหลดไม่สำเร็จ');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  const activePayers = useMemo(() => payers.filter((p) => !p.inactive), [payers]);
  const summaries = useMemo(() => buildPayerSummaries(rows), [rows]);
  const groupedClaims = useMemo(() => {
    const map = new Map<string, { key: string; name: string; rows: FaReimbursement[]; total: number }>();
    for (const row of rows) {
      const key = row.payerId || `name:${row.payerName}`;
      const group = map.get(key) || { key, name: row.payerName, rows: [], total: 0 };
      group.rows.push(row);
      group.total += row.amount;
      map.set(key, group);
    }
    return [...map.values()]
      .map((g) => ({
        ...g,
        rows: g.rows.slice().sort((a, b) => b.date.localeCompare(a.date) || b.id.localeCompare(a.id)),
      }))
      .sort((a, b) => a.name.localeCompare(b.name, 'th'));
  }, [rows]);
  const itemsTotal = useMemo(
    () => items.reduce((s, item) => s + (typeof item.amount === 'number' ? item.amount : 0), 0),
    [items],
  );

  const selectedPayer = activePayers.find((p) => p.id === payerId) || null;

  const openCreate = () => {
    setDate(today());
    setItems([{ description: '', amount: '' }]);
    setCreateOpen(true);
  };

  const submitCreate = async (e: FormEvent) => {
    e.preventDefault();
    if (!selectedPayer) {
      setError('กรุณาเลือกหรือเพิ่มผู้สำรองจ่าย');
      return;
    }
    try {
      await saveReimbursementBatch({
        date,
        payerName: selectedPayer.name,
        payerId: selectedPayer.id,
        items: items.map((item) => ({
          description: item.description,
          amount: Number(item.amount) || 0,
        })),
      });
      setCreateOpen(false);
      setMessage(`บันทึก ${items.filter((i) => i.description && i.amount).length} รายการแล้ว · รวม ${formatMoney(itemsTotal)} บาท`);
      await reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
    }
  };

  const submitPayer = async (e: FormEvent) => {
    e.preventDefault();
    if (!newPayerName.trim()) return;
    try {
      const created = await savePayer({ name: newPayerName });
      setNewPayerName('');
      setPayerOpen(false);
      setMessage(`เพิ่มผู้สำรองจ่าย "${created.name}" แล้ว`);
      await reload();
      setPayerId(created.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'เพิ่มชื่อไม่สำเร็จ');
    }
  };

  const copyLink = async (payer: FaReimbPayer) => {
    const url = payerClaimUrl(payer.shareToken);
    try {
      await navigator.clipboard.writeText(url);
      setMessage(`คัดลอกลิงก์ของ ${payer.name} แล้ว`);
    } catch {
      setMessage(url);
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
      setMessage('อนุมัติการเบิกเงินแล้ว');
      await reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'อนุมัติไม่สำเร็จ');
    }
  };

  const openProof = (row: FaReimbursement) => {
    setSelected(row);
    setProofOpen(true);
  };

  const onProofFile = async (file: File | null) => {
    if (!selected || !file) return;
    setProofBusy(true);
    setError('');
    try {
      const url = await uploadReimbProof(file, `repay/${selected.id}`);
      await attachRepaymentProof({ id: selected.id, proofUrl: url });
      setProofOpen(false);
      setSelected(null);
      setMessage('แนบหลักฐานการจ่ายเงินคืนแล้ว');
      await reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'อัปโหลดไม่สำเร็จ');
    } finally {
      setProofBusy(false);
    }
  };

  const summaryColumns: Column<(typeof summaries)[number]>[] = [
    { key: 'name', header: 'ผู้สำรองจ่าย', render: (r) => r.payerName },
    {
      key: 'total',
      header: 'จ่ายไปแล้ว',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.totalPaid),
    },
    {
      key: 'pending',
      header: 'รอเบิก',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.pendingAmount),
    },
    {
      key: 'approved',
      header: 'อนุมัติแล้ว',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.approvedAmount),
    },
    {
      key: 'repaid',
      header: 'จ่ายคืนแล้ว',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.repaidAmount),
    },
    {
      key: 'unpaid',
      header: 'ยังไม่จ่ายคืน',
      className: 'text-right tabular-nums font-medium',
      render: (r) => formatMoney(r.unpaidApprovedAmount),
    },
  ];

  const columns: Column<FaReimbursement>[] = [
    { key: 'date', header: 'วันที่', render: (r) => r.date },
    { key: 'desc', header: 'รายการ', render: (r) => r.description },
    {
      key: 'amount',
      header: 'จำนวนเงิน',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.amount),
    },
    {
      key: 'status',
      header: 'สถานะเบิก',
      render: (r) => <StatusBadge status={r.status} />,
    },
    {
      key: 'repay',
      header: 'จ่ายคืน',
      render: (r) =>
        r.status !== 'approved' ? (
          <span className="text-xs text-muted">—</span>
        ) : r.repaidAt || r.repaymentProofUrl ? (
          <a
            className="text-sm text-accent hover:underline"
            href={r.repaymentProofUrl || undefined}
            target="_blank"
            rel="noreferrer"
          >
            จ่ายคืนแล้ว
          </a>
        ) : (
          <span className="text-sm text-destructive">ยังไม่จ่ายคืน</span>
        ),
    },
    {
      key: 'actions',
      header: '',
      render: (r) => (
        <div className="flex flex-wrap justify-end gap-2">
          {r.status === 'pending' ? (
            <>
              <Button className="min-h-9" onClick={() => openApprove(r)}>
                อนุมัติ
              </Button>
              <Button
                variant="ghost"
                className="min-h-9"
                onClick={() => void rejectReimbursement(r.id).then(reload)}
              >
                ปฏิเสธ
              </Button>
            </>
          ) : null}
          {r.status === 'approved' ? (
            <Button variant="secondary" className="min-h-9" onClick={() => openProof(r)}>
              แนบสลิปจ่ายคืน
            </Button>
          ) : null}
        </div>
      ),
    },
  ];

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight">เบิกสำรองจ่าย</h2>
          <p className="mt-1 text-sm text-muted">
            เพิ่มผู้สำรองจ่าย · บันทึกรายการ · ส่งลิงก์ให้กรอกเอง · ติดตามการเบิกและหลักฐานจ่ายคืน
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button variant="secondary" onClick={() => setPayerOpen(true)}>
            เพิ่มผู้สำรองจ่าย
          </Button>
          <Button onClick={openCreate}>บันทึกสำรองจ่าย</Button>
        </div>
      </div>

      {message ? <p className="text-sm text-accent">{message}</p> : null}
      {error ? <p className="text-sm text-destructive">{error}</p> : null}

      {loading ? (
        <p className="text-sm text-muted">กำลังโหลด…</p>
      ) : (
        <>
          <Card className="overflow-hidden p-0">
            <div className="border-b border-border px-4 py-3">
              <h3 className="text-sm font-medium text-ink">สรุปตามผู้สำรองจ่าย</h3>
              <p className="mt-1 text-xs text-muted">ใครจ่ายไปเท่าไร · เบิกแล้วหรือยัง · จ่ายคืนแล้วหรือยัง</p>
            </div>
            <DataTable
              columns={summaryColumns}
              rows={summaries}
              rowKey={(r) => r.payerId || r.payerName}
              emptyText="ยังไม่มีรายการสำรองจ่าย"
            />
          </Card>

          <Card className="p-4">
            <h3 className="text-sm font-medium text-ink">ลิงก์ให้ผู้สำรองจ่ายกรอกเอง</h3>
            <ul className="mt-3 space-y-2">
              {activePayers.length === 0 ? (
                <li className="text-sm text-muted">ยังไม่มีรายชื่อ — กดเพิ่มผู้สำรองจ่ายก่อน</li>
              ) : (
                activePayers.map((p) => (
                  <li
                    key={p.id}
                    className="flex flex-wrap items-center justify-between gap-2 rounded-DEFAULT border border-border px-3 py-2"
                  >
                    <div className="min-w-0">
                      <p className="text-sm font-medium text-ink">{p.name}</p>
                      <p className="truncate text-xs text-muted">{payerClaimUrl(p.shareToken)}</p>
                    </div>
                    <div className="flex gap-2">
                      <Button variant="secondary" className="min-h-9" onClick={() => void copyLink(p)}>
                        คัดลอกลิงก์
                      </Button>
                      <Button
                        variant="ghost"
                        className="min-h-9 text-destructive"
                        onClick={() => void setPayerInactive(p.id).then(reload)}
                      >
                        ปิดใช้
                      </Button>
                    </div>
                  </li>
                ))
              )}
            </ul>
          </Card>

          <div className="space-y-4">
            <div>
              <h3 className="text-sm font-medium text-ink">รายการเบิกแยกตามชื่อ</h3>
              <p className="mt-1 text-xs text-muted">แต่ละคนมีรายการย่อยของตนเอง</p>
            </div>
            {groupedClaims.length === 0 ? (
              <Card className="p-4">
                <p className="text-sm text-muted">ยังไม่มีรายการ</p>
              </Card>
            ) : (
              groupedClaims.map((group) => (
                <Card key={group.key} className="overflow-hidden p-0">
                  <div className="flex flex-wrap items-center justify-between gap-2 border-b border-border bg-slate-50 px-4 py-3">
                    <div>
                      <h4 className="text-base font-semibold text-ink">{group.name}</h4>
                      <p className="text-xs text-muted">{group.rows.length} รายการ</p>
                    </div>
                    <p className="text-sm tabular-nums text-muted">
                      รวม{' '}
                      <span className="font-semibold text-ink">{formatMoney(group.total)}</span> บาท
                    </p>
                  </div>
                  <DataTable columns={columns} rows={group.rows} rowKey={(r) => r.id} />
                </Card>
              ))
            )}
          </div>
        </>
      )}

      <Modal
        open={payerOpen}
        title="เพิ่มผู้สำรองจ่าย"
        onClose={() => setPayerOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setPayerOpen(false)}>
              ยกเลิก
            </Button>
            <Button type="submit" form="payer-form">
              บันทึกชื่อ
            </Button>
          </>
        }
      >
        <form id="payer-form" className="space-y-4" onSubmit={submitPayer}>
          <Field id="payer-name" label="ชื่อผู้สำรองเงินจ่ายก่อน">
            <Input
              id="payer-name"
              value={newPayerName}
              onChange={(e) => setNewPayerName(e.target.value)}
              required
              placeholder="เช่น สมชาย"
            />
          </Field>
        </form>
      </Modal>

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
          <Field id="r-payer" label="ผู้สำรองจ่าย">
            <Select id="r-payer" value={payerId} onChange={(e) => setPayerId(e.target.value)} required>
              <option value="">— เลือกชื่อ —</option>
              {activePayers.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </Select>
          </Field>

          <div className="space-y-3">
            <div className="flex items-center justify-between gap-2">
              <p className="text-sm font-medium text-ink">รายการที่จ่าย</p>
              <Button
                type="button"
                variant="secondary"
                className="min-h-9"
                onClick={() => setItems((prev) => [...prev, { description: '', amount: '' }])}
              >
                + เพิ่มรายการ
              </Button>
            </div>
            {items.map((item, index) => (
              <div key={index} className="grid gap-2 sm:grid-cols-[1fr_140px_auto]">
                <Input
                  aria-label={`รายการที่ ${index + 1}`}
                  placeholder="รายการ"
                  value={item.description}
                  onChange={(e) =>
                    setItems((prev) =>
                      prev.map((row, i) => (i === index ? { ...row, description: e.target.value } : row)),
                    )
                  }
                  required
                />
                <MoneyInput
                  aria-label={`จำนวนเงินรายการที่ ${index + 1}`}
                  value={item.amount}
                  onValueChange={(v) =>
                    setItems((prev) => prev.map((row, i) => (i === index ? { ...row, amount: v } : row)))
                  }
                  required
                />
                <Button
                  type="button"
                  variant="ghost"
                  className="min-h-11"
                  disabled={items.length <= 1}
                  onClick={() => setItems((prev) => prev.filter((_, i) => i !== index))}
                >
                  ลบ
                </Button>
              </div>
            ))}
            <p className="text-sm text-muted">
              รวมเงินที่จ่าย:{' '}
              <span className="font-semibold tabular-nums text-ink">{formatMoney(itemsTotal)}</span> บาท
            </p>
          </div>
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

      <Modal
        open={proofOpen}
        title="แนบสลิป / หลักฐานจ่ายคืน"
        onClose={() => setProofOpen(false)}
        footer={
          <Button variant="secondary" onClick={() => setProofOpen(false)}>
            ปิด
          </Button>
        }
      >
        <div className="space-y-3">
          <p className="text-sm text-muted">
            {selected?.payerName} — {selected?.description} ({formatMoney(selected?.amount || 0)} บาท)
          </p>
          <Field id="proof-file" label="ไฟล์สลิปหรือหลักฐาน">
            <Input
              id="proof-file"
              type="file"
              accept="image/*,.pdf"
              disabled={proofBusy}
              onChange={(e) => void onProofFile(e.target.files?.[0] || null)}
            />
          </Field>
          {proofBusy ? <p className="text-sm text-muted">กำลังอัปโหลด…</p> : null}
        </div>
      </Modal>
    </div>
  );
}
