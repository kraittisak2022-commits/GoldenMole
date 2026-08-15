import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  buildCategorySummaries,
  deleteCategory,
  listCategories,
  restoreCategory,
  saveCategory,
  sumLedgerTotals,
} from '../data/categories';
import { listLedgerEntries } from '../data/ledger';
import {
  collectMonthKeys,
  collectYearKeys,
  currentMonthKey,
  currentYearKey,
  formatMonthLabel,
  formatYearLabel,
  isMonthKey,
  isYearKey,
  shiftMonth,
  shiftYear,
} from '../lib/ledgerMonth';
import { listExpensesByPaidBy, sumPaidByTotals } from '../lib/ledgerPaidBy';
import type { CategoryKind, FaCategory, FaLedgerEntry, LedgerPaidBy } from '../types';
import { formatMoney, LEDGER_PAID_BY_LABEL } from '../types';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import DataTable, { Column } from '../components/ui/DataTable';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import Modal from '../components/ui/Modal';
import Select from '../components/ui/Select';

const KIND_LABEL: Record<CategoryKind, string> = {
  income: 'รายรับ',
  expense: 'รายจ่าย',
  both: 'รับ/จ่าย',
};

const PARTY_ORDER: LedgerPaidBy[] = ['A', 'B', 'AB'];

type PeriodMode = 'month' | 'year';

export default function CategoriesPage() {
  const [categories, setCategories] = useState<FaCategory[]>([]);
  const [entries, setEntries] = useState<FaLedgerEntry[]>([]);
  const [periodMode, setPeriodMode] = useState<PeriodMode>('month');
  const [monthKey, setMonthKey] = useState(() => currentMonthKey());
  const [yearKey, setYearKey] = useState(() => currentYearKey());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [addOpen, setAddOpen] = useState(false);
  const [catName, setCatName] = useState('');
  const [catKind, setCatKind] = useState<CategoryKind>('expense');
  const [showArchived, setShowArchived] = useState(false);
  const [partyTab, setPartyTab] = useState<LedgerPaidBy>('A');

  const reload = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const [c, e] = await Promise.all([
        listCategories({ includeArchived: true }),
        listLedgerEntries(),
      ]);
      setCategories(c);
      setEntries(e);
      const dates = e.map((row) => row.date);
      const months = collectMonthKeys(dates, currentMonthKey());
      const years = collectYearKeys(dates, currentYearKey());
      setMonthKey((prev) => (months.includes(prev) ? prev : months[0] || currentMonthKey()));
      setYearKey((prev) => (years.includes(prev) ? prev : years[0] || currentYearKey()));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'โหลดไม่สำเร็จ');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  const monthOptions = useMemo(
    () => collectMonthKeys(entries.map((e) => e.date), currentMonthKey()),
    [entries],
  );

  const yearOptions = useMemo(
    () => collectYearKeys(entries.map((e) => e.date), currentYearKey()),
    [entries],
  );

  const periodEntries = useMemo(() => {
    if (periodMode === 'year') return entries.filter((e) => e.date.startsWith(yearKey));
    return entries.filter((e) => e.date.startsWith(monthKey));
  }, [entries, periodMode, monthKey, yearKey]);

  const periodLabel = periodMode === 'year' ? formatYearLabel(yearKey) : formatMonthLabel(monthKey);

  const visibleCategories = useMemo(
    () => categories.filter((c) => (showArchived ? true : !c.archived)),
    [categories, showArchived],
  );

  const summaries = useMemo(
    () => buildCategorySummaries(visibleCategories, periodEntries),
    [visibleCategories, periodEntries],
  );

  const periodTotals = useMemo(() => sumLedgerTotals(periodEntries), [periodEntries]);

  const paidByTotals = useMemo(() => sumPaidByTotals(periodEntries), [periodEntries]);
  const hasPaidByBreakdown =
    paidByTotals.A > 0 || paidByTotals.B > 0 || paidByTotals.AB > 0;

  const catNameById = useMemo(
    () => new Map(categories.map((c) => [c.id, c.name])),
    [categories],
  );

  const partySections = useMemo(
    () =>
      PARTY_ORDER.map((party) => {
        const rows = listExpensesByPaidBy(periodEntries, party);
        const total =
          party === 'A' ? paidByTotals.A : party === 'B' ? paidByTotals.B : paidByTotals.AB;
        return { party, rows, total };
      }),
    [periodEntries, paidByTotals],
  );

  const activeParty = useMemo(
    () => partySections.find((s) => s.party === partyTab) || partySections[0],
    [partySections, partyTab],
  );

  const partyLineColumns: Column<FaLedgerEntry>[] = useMemo(
    () => [
      { key: 'date', header: 'วันที่', render: (r) => r.date },
      { key: 'desc', header: 'รายการ', render: (r) => r.description },
      {
        key: 'cat',
        header: 'หมวดหมู่',
        render: (r) => catNameById.get(r.categoryId) || r.categoryId,
      },
      {
        key: 'amount',
        header: 'จำนวนเงิน',
        className: 'text-right tabular-nums',
        render: (r) => formatMoney(r.amount),
      },
    ],
    [catNameById],
  );

  const onMonthChange = (value: string) => {
    if (!isMonthKey(value)) return;
    setMonthKey(value);
  };

  const onYearChange = (value: string) => {
    if (!isYearKey(value)) return;
    setYearKey(value);
  };

  const goPrevMonth = () => onMonthChange(shiftMonth(monthKey, -1));
  const goNextMonth = () => {
    const next = shiftMonth(monthKey, 1);
    if (next > currentMonthKey() && !monthOptions.includes(next)) return;
    onMonthChange(next);
  };
  const canGoNextMonth =
    shiftMonth(monthKey, 1) <= currentMonthKey() || monthOptions.includes(shiftMonth(monthKey, 1));

  const goPrevYear = () => onYearChange(shiftYear(yearKey, -1));
  const goNextYear = () => {
    const next = shiftYear(yearKey, 1);
    if (next > currentYearKey() && !yearOptions.includes(next)) return;
    onYearChange(next);
  };
  const canGoNextYear =
    shiftYear(yearKey, 1) <= currentYearKey() || yearOptions.includes(shiftYear(yearKey, 1));

  const categoryLedgerHref = (categoryId: string) => {
    const params = new URLSearchParams({ category: categoryId });
    if (periodMode === 'month') params.set('month', monthKey);
    return `/ledger?${params.toString()}`;
  };
  const submitCategory = async (e: FormEvent) => {
    e.preventDefault();
    if (!catName.trim()) return;
    try {
      const created = await saveCategory({
        name: catName,
        kind: catKind,
        sortOrder: (categories.reduce((m, c) => Math.max(m, c.sortOrder), 0) || 0) + 10,
      });
      setCatName('');
      setCatKind('expense');
      setAddOpen(false);
      setMessage(`เพิ่มหมวด "${created.name}" แล้ว`);
      await reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกหมวดไม่สำเร็จ');
    }
  };

  const onDelete = async (cat: FaCategory) => {
    const label = cat.name;
    const ok = window.confirm(
      `ลบหมวด "${label}"?\n\nถ้ายังมีรายการในหมวด ระบบจะเก็บหมวดไว้ในสถานะปิดใช้งาน เพื่อให้ดูสรุปรายการย้อนหลังได้\nถ้าไม่มีรายการ จะลบหมวดออกจากระบบ`,
    );
    if (!ok) return;
    try {
      const result = await deleteCategory(cat.id);
      setMessage(
        result === 'deleted'
          ? `ลบหมวด "${label}" แล้ว`
          : `ปิดใช้งานหมวด "${label}" แล้ว — รายการยังดูสรุปได้จากปุ่มแสดงหมวดที่ปิด`,
      );
      setShowArchived(result === 'archived');
      await reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'ลบหมวดไม่สำเร็จ');
    }
  };

  const onRestore = async (cat: FaCategory) => {
    try {
      await restoreCategory(cat.id);
      setMessage(`เปิดใช้หมวด "${cat.name}" อีกครั้งแล้ว`);
      await reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'เปิดใช้หมวดไม่สำเร็จ');
    }
  };

  const summaryColumns: Column<(typeof summaries)[number]>[] = [
    {
      key: 'name',
      header: 'หมวดหมู่',
      render: (r) => (
        <Link
          to={categoryLedgerHref(r.category.id)}
          className="font-medium text-ink hover:underline"
        >
          {r.category.name}
          {r.category.archived ? (
            <span className="ml-2 text-xs font-normal text-muted">(ปิดใช้)</span>
          ) : null}
        </Link>
      ),
    },
    {
      key: 'kind',
      header: 'ประเภท',
      render: (r) => KIND_LABEL[r.category.kind],
    },
    {
      key: 'count',
      header: 'รายการ',
      className: 'text-right tabular-nums',
      render: (r) => r.entryCount,
    },
    {
      key: 'income',
      header: 'รายรับ',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.incomeTotal),
    },
    {
      key: 'expense',
      header: 'รายจ่าย',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.expenseTotal),
    },
    {
      key: 'net',
      header: 'คงเหลือ',
      className: 'text-right tabular-nums font-medium',
      render: (r) => formatMoney(r.incomeTotal - r.expenseTotal),
    },
    {
      key: 'actions',
      header: '',
      render: (r) => (
        <div className="flex justify-end gap-1">
          {r.category.archived ? (
            <Button variant="ghost" className="min-h-9 px-2" onClick={() => void onRestore(r.category)}>
              เปิดใช้
            </Button>
          ) : (
            <Button
              variant="ghost"
              className="min-h-9 px-2 text-destructive"
              onClick={() => void onDelete(r.category)}
            >
              ลบ
            </Button>
          )}
        </div>
      ),
    },
  ];

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight">สรุปรายรับ-จ่าย</h2>
          <p className="mt-1 text-sm text-muted">
            สรุปรายรับ-รายจ่ายแยกรายเดือนและรายปี · แยกตามหมวดหมู่ · และรายจ่ายของฝ่าย
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button variant="secondary" onClick={() => setShowArchived((v) => !v)}>
            {showArchived ? 'ซ่อนหมวดที่ปิดใช้' : 'แสดงหมวดที่ปิดใช้'}
          </Button>
          <Button onClick={() => setAddOpen(true)}>เพิ่มหมวดหมู่</Button>
        </div>
      </div>

      {message ? <p className="text-sm text-accent">{message}</p> : null}
      {error ? <p className="text-sm text-destructive">{error}</p> : null}

      {loading ? (
        <p className="text-sm text-muted">กำลังโหลด…</p>
      ) : (
        <>
          <Card className="space-y-4 p-4">
            <div className="flex flex-wrap gap-2" role="tablist" aria-label="ช่วงเวลาสรุป">
              <Button
                type="button"
                role="tab"
                aria-selected={periodMode === 'month'}
                variant={periodMode === 'month' ? 'primary' : 'ghost'}
                onClick={() => setPeriodMode('month')}
              >
                รายเดือน
              </Button>
              <Button
                type="button"
                role="tab"
                aria-selected={periodMode === 'year'}
                variant={periodMode === 'year' ? 'primary' : 'ghost'}
                onClick={() => setPeriodMode('year')}
              >
                รายปี
              </Button>
            </div>
            {periodMode === 'month' ? (
              <Field id="cat-summary-month" label="เดือนที่สรุป">
                <div className="flex flex-nowrap items-center gap-2">
                  <Button
                    type="button"
                    variant="secondary"
                    className="min-h-11 min-w-11 shrink-0 px-0"
                    aria-label="เดือนก่อนหน้า"
                    onClick={goPrevMonth}
                  >
                    ‹
                  </Button>
                  <Select
                    id="cat-summary-month"
                    className="w-auto min-w-[10rem] max-w-[16rem] flex-1"
                    value={monthOptions.includes(monthKey) ? monthKey : monthOptions[0] || monthKey}
                    onChange={(e) => onMonthChange(e.target.value)}
                    aria-label="เลือกเดือนที่สรุป"
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
                    className="min-h-11 min-w-11 shrink-0 px-0"
                    aria-label="เดือนถัดไป"
                    disabled={!canGoNextMonth}
                    onClick={goNextMonth}
                  >
                    ›
                  </Button>
                </div>
              </Field>
            ) : (
              <Field id="cat-summary-year" label="ปีที่สรุป">
                <div className="flex flex-nowrap items-center gap-2">
                  <Button
                    type="button"
                    variant="secondary"
                    className="min-h-11 min-w-11 shrink-0 px-0"
                    aria-label="ปีก่อนหน้า"
                    onClick={goPrevYear}
                  >
                    ‹
                  </Button>
                  <Select
                    id="cat-summary-year"
                    className="w-auto min-w-[8rem] max-w-[14rem] flex-1"
                    value={yearOptions.includes(yearKey) ? yearKey : yearOptions[0] || yearKey}
                    onChange={(e) => onYearChange(e.target.value)}
                    aria-label="เลือกปีที่สรุป"
                  >
                    {!yearOptions.includes(yearKey) ? (
                      <option value={yearKey}>{formatYearLabel(yearKey)}</option>
                    ) : null}
                    {yearOptions.map((y) => (
                      <option key={y} value={y}>
                        {formatYearLabel(y)}
                      </option>
                    ))}
                  </Select>
                  <Button
                    type="button"
                    variant="secondary"
                    className="min-h-11 min-w-11 shrink-0 px-0"
                    aria-label="ปีถัดไป"
                    disabled={!canGoNextYear}
                    onClick={goNextYear}
                  >
                    ›
                  </Button>
                </div>
              </Field>
            )}
          </Card>

          <div className="grid gap-4 sm:grid-cols-3">
            <Card className="p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-muted">รายรับรวม</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums text-ink">
                {formatMoney(periodTotals.incomeTotal)}
              </p>
              <p className="mt-1 text-xs text-muted">{periodLabel}</p>
            </Card>
            <Card className="p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-muted">รายจ่ายรวม</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums text-ink">
                {formatMoney(periodTotals.expenseTotal)}
              </p>
              <p className="mt-1 text-xs text-muted">{periodTotals.entryCount} รายการ</p>
            </Card>
            <Card className="p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-muted">คงเหลือ</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums text-ink">
                {formatMoney(periodTotals.incomeTotal - periodTotals.expenseTotal)}
              </p>
              <p className="mt-1 text-xs text-muted">
                รับ − จ่าย {periodMode === 'year' ? 'ในปีนี้' : 'ในเดือนนี้'}
              </p>
            </Card>
          </div>

          <Card className="overflow-hidden p-0">
            <div className="border-b border-border px-4 py-3">
              <h3 className="text-sm font-medium text-ink">สรุปตามหมวดหมู่ · {periodLabel}</h3>
              <p className="mt-1 text-xs text-muted">แยกรายรับและรายจ่ายในแต่ละหัวข้อหมวดหมู่</p>
            </div>
            <DataTable
              columns={summaryColumns}
              rows={summaries}
              rowKey={(r) => r.category.id}
              emptyText="ยังไม่มีหมวดหมู่ — กดเพิ่มหมวดหมู่เพื่อเริ่มต้น"
            />
          </Card>

          <Card className="overflow-hidden p-0">
            <div className="border-b border-border px-4 py-3">
              <h3 className="text-sm font-medium text-ink">
                รายจ่ายของฝ่าย · {periodLabel}
              </h3>
              <p className="mt-1 text-xs text-muted">
                แยกจากสรุปหมวดหมู่ — แต่ละฝ่ายดูได้ว่าตนเองจ่ายค่าอะไรบ้างใน
                {periodMode === 'year' ? 'ปีนี้' : 'เดือนนี้'}
              </p>
            </div>
            {!hasPaidByBreakdown ? (
              <p className="px-4 py-6 text-sm text-muted">
                ยังไม่มีรายจ่ายที่ระบุฝ่ายใน{periodMode === 'year' ? 'ปี' : 'เดือน'}นี้ — ตั้งค่าที่หน้ารายรับ-รายจ่าย
              </p>
            ) : (
              <div className="space-y-4 p-4">
                <div className="grid gap-2 sm:grid-cols-3 text-sm">
                  <div className="rounded-md border border-border bg-slate-50 px-3 py-2">
                    <p className="text-xs text-muted">รายจ่ายของฝ่าย A</p>
                    <p className="tabular-nums font-medium text-ink">{formatMoney(paidByTotals.A)}</p>
                  </div>
                  <div className="rounded-md border border-border bg-slate-50 px-3 py-2">
                    <p className="text-xs text-muted">รายจ่ายของฝ่าย B</p>
                    <p className="tabular-nums font-medium text-ink">{formatMoney(paidByTotals.B)}</p>
                  </div>
                  <div className="rounded-md border border-border bg-slate-50 px-3 py-2">
                    <p className="text-xs text-muted">รายจ่ายของฝ่าย A และ B</p>
                    <p className="tabular-nums font-medium text-ink">{formatMoney(paidByTotals.AB)}</p>
                    {paidByTotals.AB > 0 ? (
                      <p className="mt-1 text-xs text-muted">
                        แบ่งฝ่ายละ {formatMoney(paidByTotals.AB / 2)}
                      </p>
                    ) : null}
                  </div>
                </div>
                <p className="text-sm text-muted">
                  รวมหลังแบ่งครึ่ง:{' '}
                  <span className="tabular-nums font-medium text-ink">
                    A {formatMoney(paidByTotals.shareA)}
                  </span>
                  {' · '}
                  <span className="tabular-nums font-medium text-ink">
                    B {formatMoney(paidByTotals.shareB)}
                  </span>
                </p>

                <div
                  className="flex flex-wrap gap-2 border-b border-border pb-2"
                  role="tablist"
                  aria-label="รายจ่ายของฝ่าย"
                >
                  {partySections.map(({ party, rows, total }) => (
                    <Button
                      key={party}
                      type="button"
                      role="tab"
                      aria-selected={partyTab === party}
                      variant={partyTab === party ? 'primary' : 'ghost'}
                      className="min-h-10"
                      onClick={() => setPartyTab(party)}
                    >
                      ฝ่าย {LEDGER_PAID_BY_LABEL[party]}
                      <span className="ml-2 text-xs opacity-80">
                        ({rows.length} · {formatMoney(total)})
                      </span>
                    </Button>
                  ))}
                </div>

                <div role="tabpanel" aria-label={`รายจ่ายของฝ่าย ${LEDGER_PAID_BY_LABEL[activeParty.party]}`}>
                  <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                    <p className="text-sm text-muted">
                      รายการย่อยฝ่าย {LEDGER_PAID_BY_LABEL[activeParty.party]} · {activeParty.rows.length}{' '}
                      รายการ
                    </p>
                    <p className="text-sm tabular-nums text-muted">
                      รวม{' '}
                      <span className="font-semibold text-ink">{formatMoney(activeParty.total)}</span>{' '}
                      บาท
                      {activeParty.party === 'AB' && activeParty.total > 0
                        ? ` (ฝ่ายละ ${formatMoney(activeParty.total / 2)})`
                        : ''}
                    </p>
                  </div>
                  <div className="overflow-hidden rounded-lg border border-border">
                    <DataTable
                      columns={partyLineColumns}
                      rows={activeParty.rows}
                      rowKey={(r) => r.id}
                      emptyText={`ยังไม่มีรายจ่ายของฝ่าย ${LEDGER_PAID_BY_LABEL[activeParty.party]} ใน${periodMode === 'year' ? 'ปี' : 'เดือน'}นี้`}
                    />
                  </div>
                </div>
              </div>
            )}
          </Card>
        </>
      )}

      <Modal
        open={addOpen}
        title="เพิ่มหมวดหมู่"
        onClose={() => setAddOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setAddOpen(false)}>
              ยกเลิก
            </Button>
            <Button type="submit" form="cat-add-form">
              บันทึกหมวด
            </Button>
          </>
        }
      >
        <form id="cat-add-form" className="space-y-4" onSubmit={submitCategory}>
          <Field id="new-cat-name" label="ชื่อหมวด">
            <Input
              id="new-cat-name"
              value={catName}
              onChange={(e) => setCatName(e.target.value)}
              required
              placeholder="เช่น ค่าวัสดุก่อสร้าง"
            />
          </Field>
          <Field id="new-cat-kind" label="ใช้กับ">
            <Select
              id="new-cat-kind"
              value={catKind}
              onChange={(e) => setCatKind(e.target.value as CategoryKind)}
            >
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
