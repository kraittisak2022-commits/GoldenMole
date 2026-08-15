import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  buildCategorySummaries,
  deleteCategory,
  listCategories,
  restoreCategory,
  saveCategory,
} from '../data/categories';
import { listLedgerEntries } from '../data/ledger';
import type { CategoryKind, FaCategory, FaLedgerEntry } from '../types';
import { formatMoney } from '../types';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import DataTable, { Column } from '../components/ui/DataTable';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import Modal from '../components/ui/Modal';
import Select from '../components/ui/Select';
import StatusBadge from '../components/ui/StatusBadge';

const KIND_LABEL: Record<CategoryKind, string> = {
  income: 'รายรับ',
  expense: 'รายจ่าย',
  both: 'รับ/จ่าย',
};

export default function CategoriesPage() {
  const [categories, setCategories] = useState<FaCategory[]>([]);
  const [entries, setEntries] = useState<FaLedgerEntry[]>([]);
  const [selectedId, setSelectedId] = useState<string>('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [addOpen, setAddOpen] = useState(false);
  const [catName, setCatName] = useState('');
  const [catKind, setCatKind] = useState<CategoryKind>('expense');
  const [showArchived, setShowArchived] = useState(false);

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
      setSelectedId((prev) => {
        if (prev && c.some((x) => x.id === prev)) return prev;
        const active = c.find((x) => !x.archived);
        return active?.id || c[0]?.id || '';
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'โหลดไม่สำเร็จ');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  const visibleCategories = useMemo(
    () => categories.filter((c) => (showArchived ? true : !c.archived)),
    [categories, showArchived],
  );

  const summaries = useMemo(
    () => buildCategorySummaries(visibleCategories, entries),
    [visibleCategories, entries],
  );

  const selected = categories.find((c) => c.id === selectedId) || null;
  const selectedEntries = useMemo(
    () =>
      entries
        .filter((e) => e.categoryId === selectedId)
        .slice()
        .sort((a, b) => b.date.localeCompare(a.date)),
    [entries, selectedId],
  );

  const selectedTotals = useMemo(() => {
    const income = selectedEntries
      .filter((e) => e.entryType === 'income')
      .reduce((s, e) => s + e.amount, 0);
    const expense = selectedEntries
      .filter((e) => e.entryType === 'expense')
      .reduce((s, e) => s + e.amount, 0);
    return { income, expense, count: selectedEntries.length };
  }, [selectedEntries]);

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
      setSelectedId(created.id);
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
        <button
          type="button"
          className="cursor-pointer text-left font-medium text-ink hover:underline"
          onClick={() => setSelectedId(r.category.id)}
        >
          {r.category.name}
          {r.category.archived ? (
            <span className="ml-2 text-xs font-normal text-muted">(ปิดใช้)</span>
          ) : null}
        </button>
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
      header: 'รับ',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.incomeTotal),
    },
    {
      key: 'expense',
      header: 'จ่าย',
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

  const entryColumns: Column<FaLedgerEntry>[] = [
    { key: 'date', header: 'วันที่', render: (r) => r.date },
    { key: 'desc', header: 'รายการ', render: (r) => r.description },
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
  ];

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight">จัดการหมวดหมู่</h2>
          <p className="mt-1 text-sm text-muted">
            เพิ่ม/ลบหมวดหมู่ และดูสรุปรายการที่เก็บรวมในแต่ละหมวด
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
          <Card className="overflow-hidden p-0">
            <div className="border-b border-border px-4 py-3">
              <h3 className="text-sm font-medium text-ink">สรุปตามหมวดหมู่</h3>
            </div>
            <DataTable
              columns={summaryColumns}
              rows={summaries}
              rowKey={(r) => r.category.id}
              emptyText="ยังไม่มีหมวดหมู่ — กดเพิ่มหมวดหมู่เพื่อเริ่มต้น"
            />
          </Card>

          {selected ? (
            <Card className="space-y-4 p-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h3 className="text-lg font-semibold text-ink">{selected.name}</h3>
                  <p className="mt-1 text-sm text-muted">
                    {KIND_LABEL[selected.kind]}
                    {selected.archived ? ' · ปิดใช้งาน (ยังดูสรุปได้)' : null}
                  </p>
                </div>
                <div className="flex flex-wrap gap-2">
                  <Link
                    to={`/ledger?category=${encodeURIComponent(selected.id)}`}
                    className="inline-flex min-h-11 items-center rounded-DEFAULT border border-border bg-white px-3 text-sm text-ink hover:bg-slate-50"
                  >
                    เปิดในรายรับ-รายจ่าย
                  </Link>
                  {selected.archived ? (
                    <Button variant="secondary" onClick={() => void onRestore(selected)}>
                      เปิดใช้หมวดนี้
                    </Button>
                  ) : (
                    <Button variant="secondary" onClick={() => void onDelete(selected)}>
                      ลบหมวดนี้
                    </Button>
                  )}
                </div>
              </div>

              <div className="flex flex-wrap gap-4 text-sm text-muted">
                <span>{selectedTotals.count} รายการ</span>
                <span className="tabular-nums">รับ {formatMoney(selectedTotals.income)}</span>
                <span className="tabular-nums">จ่าย {formatMoney(selectedTotals.expense)}</span>
                <span className="tabular-nums font-medium text-ink">
                  คงเหลือ {formatMoney(selectedTotals.income - selectedTotals.expense)}
                </span>
              </div>

              <DataTable
                columns={entryColumns}
                rows={selectedEntries}
                rowKey={(r) => r.id}
                emptyText={`ยังไม่มีรายการในหมวด "${selected.name}"`}
              />
            </Card>
          ) : null}
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
