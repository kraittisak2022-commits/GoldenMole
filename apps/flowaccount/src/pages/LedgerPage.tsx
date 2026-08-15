import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { archiveCategory, listCategories, saveCategory } from '../data/categories';
import { deleteLedgerEntry, listLedgerEntries, saveLedgerEntry } from '../data/ledger';
import type { EntryType, FaCategory, FaLedgerEntry } from '../types';
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

export default function LedgerPage() {
  const { user } = useAuth();
  const [entries, setEntries] = useState<FaLedgerEntry[]>([]);
  const [categories, setCategories] = useState<FaCategory[]>([]);
  const [filterCategoryId, setFilterCategoryId] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [entryOpen, setEntryOpen] = useState(false);
  const [catOpen, setCatOpen] = useState(false);
  const [editing, setEditing] = useState<FaLedgerEntry | null>(null);

  const [date, setDate] = useState(today());
  const [description, setDescription] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [entryType, setEntryType] = useState<EntryType>('expense');
  const [amount, setAmount] = useState<number | ''>('');

  const [catName, setCatName] = useState('');
  const [catKind, setCatKind] = useState<'income' | 'expense' | 'both'>('expense');

  const catMap = useMemo(() => new Map(categories.map((c) => [c.id, c])), [categories]);

  const filteredEntries = useMemo(() => {
    if (!filterCategoryId) return entries;
    return entries.filter((e) => e.categoryId === filterCategoryId);
  }, [entries, filterCategoryId]);

  const filterCategoryName = filterCategoryId
    ? catMap.get(filterCategoryId)?.name || 'หมวดที่เลือก'
    : 'ทั้งหมด';

  const categoryTotals = useMemo(() => {
    const income = filteredEntries
      .filter((e) => e.entryType === 'income')
      .reduce((s, e) => s + e.amount, 0);
    const expense = filteredEntries
      .filter((e) => e.entryType === 'expense')
      .reduce((s, e) => s + e.amount, 0);
    return { income, expense, count: filteredEntries.length };
  }, [filteredEntries]);

  const reload = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const [e, c] = await Promise.all([listLedgerEntries(), listCategories()]);
      setEntries(e);
      setCategories(c);
      setFilterCategoryId((prev) => {
        if (prev === '') return '';
        if (prev && c.some((x) => x.id === prev)) return prev;
        return '';
      });
      setCategoryId((prev) => prev || c[0]?.id || '');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'โหลดข้อมูลไม่สำเร็จ');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  const openCreate = () => {
    setEditing(null);
    setDate(today());
    setDescription('');
    setEntryType('expense');
    setAmount('');
    setCategoryId(filterCategoryId || categories[0]?.id || '');
    setEntryOpen(true);
  };

  const openEdit = (row: FaLedgerEntry) => {
    if (row.source !== 'manual') return;
    setEditing(row);
    setDate(row.date);
    setDescription(row.description);
    setEntryType(row.entryType);
    setAmount(row.amount);
    setCategoryId(row.categoryId);
    setEntryOpen(true);
  };

  const submitEntry = async (e: FormEvent) => {
    e.preventDefault();
    if (!categoryId || amount === '' || Number(amount) < 0) return;
    try {
      await saveLedgerEntry({
        id: editing?.id,
        date,
        description,
        categoryId,
        entryType,
        amount: Number(amount),
        source: 'manual',
        createdBy: user?.username,
      });
      setEntryOpen(false);
      await reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
    }
  };

  const submitCategory = async (e: FormEvent) => {
    e.preventDefault();
    if (!catName.trim()) return;
    try {
      await saveCategory({ name: catName, kind: catKind });
      setCatName('');
      setCatOpen(false);
      await reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกหมวดไม่สำเร็จ');
    }
  };

  const columns: Column<FaLedgerEntry>[] = [
    { key: 'date', header: 'วันที่', render: (r) => r.date },
    { key: 'desc', header: 'รายการ', render: (r) => r.description },
    ...(filterCategoryId
      ? []
      : [
          {
            key: 'cat',
            header: 'หมวดหมู่',
            render: (r: FaLedgerEntry) => catMap.get(r.categoryId)?.name || r.categoryId,
          } satisfies Column<FaLedgerEntry>,
        ]),
    {
      key: 'type',
      header: 'ประเภท',
      render: (r) => <StatusBadge status={r.entryType} />,
    },
    {
      key: 'amount',
      header: 'จำนวนเงิน',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.amount),
    },
    {
      key: 'actions',
      header: '',
      render: (r) =>
        r.source === 'manual' ? (
          <div className="flex gap-2 justify-end">
            <Button variant="ghost" className="min-h-9 px-2" onClick={() => openEdit(r)}>
              แก้ไข
            </Button>
            <Button
              variant="ghost"
              className="min-h-9 px-2 text-destructive"
              onClick={() => {
                void deleteLedgerEntry(r.id).then(reload);
              }}
            >
              ลบ
            </Button>
          </div>
        ) : (
          <span className="text-xs text-muted">{r.source}</span>
        ),
    },
  ];

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight">รายรับ-รายจ่าย</h2>
          <p className="mt-1 text-sm text-muted">ดูทั้งหมด หรือกรองตามหมวดหมู่</p>
        </div>
        <div className="flex gap-2">
          <Button variant="secondary" onClick={() => setCatOpen(true)}>
            จัดการหมวดหมู่
          </Button>
          <Button onClick={openCreate}>เพิ่มรายการ</Button>
        </div>
      </div>

      <Card className="p-4">
        <div className="flex flex-wrap items-end gap-4">
          <div className="min-w-[220px] flex-1">
            <Field id="ledger-filter-cat" label="หมวดหมู่">
              <Select
                id="ledger-filter-cat"
                value={filterCategoryId}
                onChange={(e) => setFilterCategoryId(e.target.value)}
                aria-label="เลือกหมวดหมู่เพื่อกรองตาราง"
              >
                <option value="">ทั้งหมด</option>
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </Select>
            </Field>
          </div>
          <div className="flex flex-wrap gap-4 text-sm text-muted pb-1">
            <span>
              มุมมอง: <span className="font-medium text-ink">{filterCategoryName}</span>
            </span>
            <span>{categoryTotals.count} รายการ</span>
            <span className="tabular-nums">รับ {formatMoney(categoryTotals.income)}</span>
            <span className="tabular-nums">จ่าย {formatMoney(categoryTotals.expense)}</span>
            <span className="tabular-nums font-medium text-ink">
              คงเหลือ {formatMoney(categoryTotals.income - categoryTotals.expense)}
            </span>
          </div>
        </div>
      </Card>

      {error ? <p className="text-sm text-destructive">{error}</p> : null}
      {loading ? (
        <p className="text-sm text-muted">กำลังโหลด…</p>
      ) : (
        <DataTable
          columns={columns}
          rows={filteredEntries}
          rowKey={(r) => r.id}
          emptyText={
            filterCategoryId
              ? `ยังไม่มีรายการในหมวด "${filterCategoryName}"`
              : 'ยังไม่มีรายรับ-รายจ่าย'
          }
        />
      )}

      <Card className="p-4">
        <h3 className="text-sm font-medium text-ink">หมวดหมู่</h3>
        <ul className="mt-3 flex flex-wrap gap-2">
          <li
            className={[
              'flex min-h-9 items-center rounded-full border px-3 text-xs',
              filterCategoryId === ''
                ? 'border-accent bg-sky-50 text-ink'
                : 'border-border text-muted',
            ].join(' ')}
          >
            <button
              type="button"
              className="cursor-pointer py-1 hover:text-ink"
              onClick={() => setFilterCategoryId('')}
            >
              ทั้งหมด
            </button>
          </li>
          {categories.map((c) => (
            <li
              key={c.id}
              className={[
                'flex min-h-9 items-center gap-1 rounded-full border px-1 pl-3 text-xs',
                filterCategoryId === c.id
                  ? 'border-accent bg-sky-50 text-ink'
                  : 'border-border text-muted',
              ].join(' ')}
            >
              <button
                type="button"
                className="cursor-pointer py-1 hover:text-ink"
                onClick={() => setFilterCategoryId(c.id)}
              >
                {c.name}
              </button>
              <button
                type="button"
                className="min-h-8 min-w-8 rounded-full text-muted hover:bg-white hover:text-destructive cursor-pointer"
                onClick={() => void archiveCategory(c.id).then(reload)}
                aria-label={`เก็บหมวด ${c.name}`}
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      </Card>

      <Modal
        open={entryOpen}
        title={editing ? 'แก้ไขรายการ' : 'เพิ่มรายการ'}
        onClose={() => setEntryOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setEntryOpen(false)}>
              ยกเลิก
            </Button>
            <Button type="submit" form="ledger-form">
              บันทึก
            </Button>
          </>
        }
      >
        <form id="ledger-form" className="space-y-4" onSubmit={submitEntry}>
          <Field id="led-date" label="วันที่">
            <Input id="led-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} required />
          </Field>
          <Field id="led-desc" label="รายการ">
            <Input id="led-desc" value={description} onChange={(e) => setDescription(e.target.value)} required />
          </Field>
          <Field id="led-type" label="ประเภท">
            <Select id="led-type" value={entryType} onChange={(e) => setEntryType(e.target.value as EntryType)}>
              <option value="expense">จ่าย</option>
              <option value="income">รับ</option>
            </Select>
          </Field>
          <Field id="led-cat" label="หมวดหมู่">
            <Select id="led-cat" value={categoryId} onChange={(e) => setCategoryId(e.target.value)} required>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="led-amt" label="จำนวนเงิน">
            <MoneyInput id="led-amt" value={amount} onValueChange={setAmount} required />
          </Field>
        </form>
      </Modal>

      <Modal
        open={catOpen}
        title="เพิ่มหมวดหมู่"
        onClose={() => setCatOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setCatOpen(false)}>
              ปิด
            </Button>
            <Button type="submit" form="cat-form">
              บันทึกหมวด
            </Button>
          </>
        }
      >
        <form id="cat-form" className="space-y-4" onSubmit={submitCategory}>
          <Field id="cat-name" label="ชื่อหมวด">
            <Input id="cat-name" value={catName} onChange={(e) => setCatName(e.target.value)} required />
          </Field>
          <Field id="cat-kind" label="ใช้กับ">
            <Select id="cat-kind" value={catKind} onChange={(e) => setCatKind(e.target.value as typeof catKind)}>
              <option value="expense">รายจ่าย</option>
              <option value="income">รายรับ</option>
              <option value="both">ทั้งสอง</option>
            </Select>
          </Field>
        </form>
      </Modal>
    </div>
  );
}
