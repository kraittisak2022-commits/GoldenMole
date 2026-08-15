import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { listCategories } from '../data/categories';
import { deleteLedgerEntry, listLedgerEntries, saveLedgerEntry } from '../data/ledger';
import {
  collectMonthKeys,
  currentMonthKey,
  defaultDateForMonth,
  formatMonthLabel,
  isMonthKey,
  shiftMonth,
} from '../lib/ledgerMonth';
import { sumPaidByTotals } from '../lib/ledgerPaidBy';
import type { EntryType, FaLedgerEntry, LedgerPaidBy } from '../types';
import { formatMoney, LEDGER_PAID_BY_LABEL } from '../types';
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

export default function LedgerPage() {
  const { user } = useAuth();
  const [searchParams, setSearchParams] = useSearchParams();
  const [entries, setEntries] = useState<FaLedgerEntry[]>([]);
  const [categories, setCategories] = useState<Awaited<ReturnType<typeof listCategories>>>([]);
  const [monthKey, setMonthKey] = useState(() => currentMonthKey());
  const [filterCategoryId, setFilterCategoryId] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [entryOpen, setEntryOpen] = useState(false);
  const [editing, setEditing] = useState<FaLedgerEntry | null>(null);

  const [date, setDate] = useState(() => defaultDateForMonth(currentMonthKey()));
  const [description, setDescription] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [entryType, setEntryType] = useState<EntryType>('expense');
  const [quantity, setQuantity] = useState<number | ''>(1);
  const [amount, setAmount] = useState<number | ''>('');
  const [paidBy, setPaidBy] = useState<LedgerPaidBy | ''>('');

  const catMap = useMemo(() => new Map(categories.map((c) => [c.id, c])), [categories]);

  const monthOptions = useMemo(
    () => collectMonthKeys(entries.map((e) => e.date), currentMonthKey()),
    [entries],
  );

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

  const monthEntries = useMemo(
    () => entries.filter((e) => e.date.startsWith(monthKey)),
    [entries, monthKey],
  );

  const filteredEntries = useMemo(() => {
    if (!filterCategoryId) return monthEntries;
    return monthEntries.filter((e) => e.categoryId === filterCategoryId);
  }, [monthEntries, filterCategoryId]);

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

  const paidByTotals = useMemo(() => sumPaidByTotals(filteredEntries), [filteredEntries]);
  const hasPaidByBreakdown =
    paidByTotals.A > 0 || paidByTotals.B > 0 || paidByTotals.AB > 0;

  const patchParams = useCallback(
    (patch: { month?: string; category?: string | null }) => {
      const next = new URLSearchParams(searchParams);
      if (patch.month !== undefined) {
        if (patch.month) next.set('month', patch.month);
        else next.delete('month');
      }
      if (patch.category !== undefined) {
        if (patch.category) next.set('category', patch.category);
        else next.delete('category');
      }
      setSearchParams(next, { replace: true });
    },
    [searchParams, setSearchParams],
  );

  const reload = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const [e, c] = await Promise.all([listLedgerEntries(), listCategories()]);
      setEntries(e);
      setCategories(c);

      const months = collectMonthKeys(
        e.map((row) => row.date),
        currentMonthKey(),
      );
      const urlMonth = searchParams.get('month') || '';
      setMonthKey((prev) => {
        if (isMonthKey(urlMonth) && (months.includes(urlMonth) || urlMonth <= currentMonthKey())) {
          return urlMonth;
        }
        if (months.includes(prev)) return prev;
        return months[0] || currentMonthKey();
      });

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

  const onMonthChange = (value: string) => {
    if (!isMonthKey(value)) return;
    setMonthKey(value);
    patchParams({ month: value });
  };

  const onFilterChange = (value: string) => {
    setFilterCategoryId(value);
    patchParams({ category: value || null });
  };

  const goPrevMonth = () => onMonthChange(shiftMonth(monthKey, -1));
  const goNextMonth = () => {
    const next = shiftMonth(monthKey, 1);
    if (next > currentMonthKey() && !monthOptions.includes(next)) return;
    onMonthChange(next);
  };
  const canGoNext =
    shiftMonth(monthKey, 1) <= currentMonthKey() || monthOptions.includes(shiftMonth(monthKey, 1));

  const openCreate = () => {
    setEditing(null);
    setDate(defaultDateForMonth(monthKey));
    setDescription('');
    setEntryType('expense');
    setQuantity(1);
    setAmount('');
    setPaidBy('');
    setCategoryId(filterCategoryId || categories[0]?.id || '');
    setEntryOpen(true);
  };

  const openEdit = (row: FaLedgerEntry) => {
    if (row.source !== 'manual') return;
    setEditing(row);
    setDate(row.date);
    setDescription(row.description);
    setEntryType(row.entryType);
    setQuantity(row.quantity || 1);
    setAmount(row.amount);
    setPaidBy(row.paidBy || '');
    setCategoryId(row.categoryId);
    setEntryOpen(true);
  };

  const submitEntry = async (e: FormEvent) => {
    e.preventDefault();
    if (!categoryId || amount === '' || Number(amount) < 0) return;
    const qty = Number(quantity);
    try {
      await saveLedgerEntry({
        id: editing?.id,
        date,
        description,
        categoryId,
        entryType,
        quantity: qty > 0 ? qty : 1,
        amount: Number(amount),
        paidBy: paidBy || null,
        source: 'manual',
        createdBy: user?.username,
      });
      setEntryOpen(false);
      const entryMonth = date.slice(0, 7);
      if (isMonthKey(entryMonth) && entryMonth !== monthKey) {
        setMonthKey(entryMonth);
        patchParams({ month: entryMonth });
      }
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
      key: 'qty',
      header: 'จำนวน (ชิ้น)',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.quantity ?? 1),
    },
    {
      key: 'amount',
      header: 'จำนวนเงิน',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.amount),
    },
    {
      key: 'paidBy',
      header: 'ผู้จ่าย',
      render: (r) =>
        r.paidBy ? (
          <span className="inline-flex rounded-full bg-sky-50 px-2.5 py-0.5 text-xs font-medium text-sky-800">
            {LEDGER_PAID_BY_LABEL[r.paidBy]}
          </span>
        ) : (
          <span className="text-muted">—</span>
        ),
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
          <p className="mt-1 text-sm text-muted">แยกดูรายเดือน · กรองตามหมวดหมู่ได้</p>
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
          <div className="min-w-[240px]">
            <Field id="ledger-filter-month" label="เดือน">
              <div className="flex items-center gap-2">
                <Button
                  type="button"
                  variant="secondary"
                  className="min-h-11 min-w-11 px-0"
                  aria-label="เดือนก่อนหน้า"
                  onClick={goPrevMonth}
                >
                  ‹
                </Button>
                <Select
                  id="ledger-filter-month"
                  value={monthOptions.includes(monthKey) ? monthKey : monthOptions[0] || monthKey}
                  onChange={(e) => onMonthChange(e.target.value)}
                  aria-label="เลือกเดือน"
                >
                  {!monthOptions.includes(monthKey) ? (
                    <option value={monthKey}>{formatMonthLabel(monthKey)}</option>
                  ) : null}
                  {monthOptions.map((m) => (
                    <option key={m} value={m}>
                      {formatMonthLabel(m)}
                    </option>
                  ))}
                </Select>
                <Button
                  type="button"
                  variant="secondary"
                  className="min-h-11 min-w-11 px-0"
                  aria-label="เดือนถัดไป"
                  disabled={!canGoNext}
                  onClick={goNextMonth}
                >
                  ›
                </Button>
              </div>
            </Field>
          </div>
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
              <span className="font-medium text-ink">{formatMonthLabel(monthKey)}</span>
              {filterCategoryId ? (
                <>
                  {' '}
                  · <span className="font-medium text-ink">{filterCategoryName}</span>
                </>
              ) : null}
            </span>
            <span>{categoryTotals.count} รายการ</span>
            <span className="tabular-nums">รับ {formatMoney(categoryTotals.income)}</span>
            <span className="tabular-nums">จ่าย {formatMoney(categoryTotals.expense)}</span>
            <span className="tabular-nums font-medium text-ink">
              คงเหลือ {formatMoney(categoryTotals.income - categoryTotals.expense)}
            </span>
          </div>
          {hasPaidByBreakdown ? (
            <div className="mt-3 rounded-lg border border-border bg-surface-muted/40 px-3 py-3 space-y-2">
              <p className="text-xs font-medium uppercase tracking-wide text-muted">สรุปผู้จ่าย (รายจ่าย)</p>
              <div className="flex flex-wrap gap-x-5 gap-y-1 text-sm">
                <span className="tabular-nums">
                  A <span className="font-medium text-ink">{formatMoney(paidByTotals.A)}</span>
                </span>
                <span className="tabular-nums">
                  B <span className="font-medium text-ink">{formatMoney(paidByTotals.B)}</span>
                </span>
                <span className="tabular-nums">
                  A และ B <span className="font-medium text-ink">{formatMoney(paidByTotals.AB)}</span>
                </span>
              </div>
              <p className="text-sm text-muted">
                ส่วนแบ่งจริง (A และ B คนละครึ่ง):{' '}
                <span className="tabular-nums font-medium text-ink">
                  A {formatMoney(paidByTotals.shareA)}
                </span>
                {' · '}
                <span className="tabular-nums font-medium text-ink">
                  B {formatMoney(paidByTotals.shareB)}
                </span>
              </p>
            </div>
          ) : null}
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
              ? `ยังไม่มีรายการในหมวด "${filterCategoryName}" เดือน${formatMonthLabel(monthKey)}`
              : `ยังไม่มีรายรับ-รายจ่ายในเดือน${formatMonthLabel(monthKey)}`
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
          <div className="grid gap-4 sm:grid-cols-2">
            <Field id="led-qty" label="จำนวน (ชิ้น)">
              <MoneyInput
                id="led-qty"
                placeholder="1"
                value={quantity}
                onValueChange={(v) => setQuantity(v === '' ? '' : v)}
                required
              />
            </Field>
            <Field id="led-amt" label="จำนวนเงิน (บาท)">
              <MoneyInput id="led-amt" placeholder="0" value={amount} onValueChange={setAmount} required />
            </Field>
          </div>
          <Field id="led-paid-by" label="ผู้จ่าย (กรณีแบ่งจ่าย)">
            <div id="led-paid-by" className="flex flex-wrap gap-3 pt-1" role="radiogroup" aria-label="ผู้จ่าย">
              {(
                [
                  { value: '', label: 'ไม่ระบุ' },
                  { value: 'A' as const, label: 'A' },
                  { value: 'B' as const, label: 'B' },
                  { value: 'AB' as const, label: 'A และ B' },
                ] as const
              ).map((opt) => (
                <label key={opt.value || 'none'} className="inline-flex cursor-pointer items-center gap-2 text-sm text-ink">
                  <input
                    type="radio"
                    name="led-paid-by"
                    className="size-4 accent-sky-600"
                    checked={paidBy === opt.value}
                    onChange={() => setPaidBy(opt.value)}
                  />
                  {opt.label}
                </label>
              ))}
            </div>
          </Field>
        </form>
      </Modal>
    </div>
  );
}
