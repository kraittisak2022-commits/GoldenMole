import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { listCategories } from '../data/categories';
import { deleteLedgerEntry, listLedgerEntries, saveLedgerEntry } from '../data/ledger';
import type { EntryType, FaLedgerEntry } from '../types';
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
  const [searchParams, setSearchParams] = useSearchParams();
  const [entries, setEntries] = useState<FaLedgerEntry[]>([]);
  const [categories, setCategories] = useState<Awaited<ReturnType<typeof listCategories>>>([]);
  const [filterCategoryId, setFilterCategoryId] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [entryOpen, setEntryOpen] = useState(false);
  const [editing, setEditing] = useState<FaLedgerEntry | null>(null);

  const [date, setDate] = useState(today());
  const [description, setDescription] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [entryType, setEntryType] = useState<EntryType>('expense');
  const [amount, setAmount] = useState<number | ''>('');

  const catMap = useMemo(() => new Map(categories.map((c) => [c.id, c])), [categories]);

  const entryCategories = useMemo(
    () => categories.filter((c) => c.kind === 'both' || c.kind === entryType),
    [categories, entryType],
  );

  useEffect(() => {
    if (!entryCategories.length) {
      setCategoryId('');
      return;
    }
    if (!entryCategories.some((c) => c.id === categoryId)) {
      setCategoryId(entryCategories[0].id);
    }
  }, [entryCategories, categoryId]);

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
      const fromUrl = searchParams.get('category') || '';
      setFilterCategoryId((prev) => {
        const preferred = fromUrl || prev;
        if (preferred === '') return '';
        if (preferred && c.some((x) => x.id === preferred)) return preferred;
        return '';
      });
      setCategoryId((prev) => prev || c[0]?.id || '');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'โหลดข้อมูลไม่สำเร็จ');
    } finally {
      setLoading(false);
    }
  }, [searchParams]);

  useEffect(() => {
    void reload();
  }, [reload]);

  const onFilterChange = (value: string) => {
    setFilterCategoryId(value);
    const next = new URLSearchParams(searchParams);
    if (value) next.set('category', value);
    else next.delete('category');
    setSearchParams(next, { replace: true });
  };

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
          <Link
            to="/categories"
            className="inline-flex min-h-11 items-center justify-center gap-2 rounded-DEFAULT border border-border bg-white px-3 text-sm font-medium text-ink transition-colors hover:bg-slate-50"
          >
            หมวดหมู่
          </Link>
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
                onChange={(e) => onFilterChange(e.target.value)}
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
              {entryCategories.map((c) => (
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
    </div>
  );
}
