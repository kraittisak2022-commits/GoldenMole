import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { sumLedgerTotals } from '../data/categories';
import { listFleetLogs } from '../data/fleetLogs';
import { listLedgerEntries } from '../data/ledger';
import { listReimbursements } from '../data/reimbursements';
import {
  collectMonthKeys,
  currentMonthKey,
  formatMonthLabel,
  isMonthKey,
  shiftMonth,
} from '../lib/ledgerMonth';
import type { FaFleetLog, FaLedgerEntry } from '../types';
import { formatMoney } from '../types';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import Select from '../components/ui/Select';

type PeriodMode = 'month' | 'range';

function inMonth(date: string, monthKey: string) {
  return date.startsWith(monthKey);
}

function inRange(date: string, from: string, to: string) {
  if (!from && !to) return true;
  if (from && date < from) return false;
  if (to && date > to) return false;
  return true;
}

export default function DashboardPage() {
  const { user } = useAuth();
  const [ledger, setLedger] = useState<FaLedgerEntry[]>([]);
  const [fleet, setFleet] = useState<FaFleetLog[]>([]);
  const [pendingReimb, setPendingReimb] = useState(0);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const [periodMode, setPeriodMode] = useState<PeriodMode>('month');
  const [monthKey, setMonthKey] = useState(() => currentMonthKey());
  const [rangeFrom, setRangeFrom] = useState(() => `${currentMonthKey()}-01`);
  const [rangeTo, setRangeTo] = useState(() => {
    const now = new Date();
    return now.toISOString().slice(0, 10);
  });

  useEffect(() => {
    void (async () => {
      setLoading(true);
      try {
        const [led, reimb, fl] = await Promise.all([
          listLedgerEntries(),
          listReimbursements(),
          listFleetLogs(),
        ]);
        setLedger(led);
        setFleet(fl);
        setPendingReimb(reimb.filter((r) => r.status === 'pending').length);
        const months = collectMonthKeys(
          led.map((e) => e.date),
          currentMonthKey(),
        );
        setMonthKey((prev) => (months.includes(prev) ? prev : months[0] || currentMonthKey()));
      } catch (err) {
        setError(err instanceof Error ? err.message : 'โหลดแดชบอร์ดไม่สำเร็จ');
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  const monthOptions = useMemo(
    () => collectMonthKeys(ledger.map((e) => e.date), currentMonthKey()),
    [ledger],
  );

  const periodLedger = useMemo(() => {
    if (periodMode === 'month') return ledger.filter((e) => inMonth(e.date, monthKey));
    return ledger.filter((e) => inRange(e.date, rangeFrom, rangeTo));
  }, [ledger, periodMode, monthKey, rangeFrom, rangeTo]);

  const periodFleet = useMemo(() => {
    if (periodMode === 'month') return fleet.filter((f) => inMonth(f.workDate, monthKey));
    return fleet.filter((f) => inRange(f.workDate, rangeFrom, rangeTo));
  }, [fleet, periodMode, monthKey, rangeFrom, rangeTo]);

  const allTotals = useMemo(() => sumLedgerTotals(ledger), [ledger]);
  const periodTotals = useMemo(() => sumLedgerTotals(periodLedger), [periodLedger]);
  const fleetCost = useMemo(
    () => periodFleet.reduce((s, f) => s + f.totalCost, 0),
    [periodFleet],
  );

  const periodLabel =
    periodMode === 'month'
      ? formatMonthLabel(monthKey)
      : rangeFrom && rangeTo
        ? `${rangeFrom} → ${rangeTo}`
        : 'ช่วงที่เลือก';

  const ledgerLink =
    periodMode === 'month' ? `/ledger?month=${encodeURIComponent(monthKey)}` : '/ledger';

  const onMonthChange = (value: string) => {
    if (!isMonthKey(value)) return;
    setMonthKey(value);
  };

  const cards = [
    {
      label: `รายรับ · ${periodLabel}`,
      value: formatMoney(periodTotals.incomeTotal),
      to: ledgerLink,
      suffix: 'บาท',
    },
    {
      label: `รายจ่าย · ${periodLabel}`,
      value: formatMoney(periodTotals.expenseTotal),
      to: ledgerLink,
      suffix: 'บาท',
    },
    { label: 'รออนุมัติเบิก', value: String(pendingReimb), to: '/reimbursements', suffix: 'รายการ' },
    {
      label: `ต้นทุนรถ · ${periodLabel}`,
      value: formatMoney(fleetCost),
      to: '/fleet',
      suffix: 'บาท',
    },
  ];

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight text-ink">แดชบอร์ด</h2>
          <p className="mt-2 text-sm text-muted">ยินดีต้อนรับ {user?.displayName}</p>
        </div>

        <Card className="w-full space-y-3 p-3 lg:max-w-xl">
          <div className="flex flex-nowrap gap-2" role="tablist" aria-label="โหมดช่วงเวลา">
            <Button
              type="button"
              role="tab"
              aria-selected={periodMode === 'month'}
              variant={periodMode === 'month' ? 'primary' : 'ghost'}
              className="min-h-10"
              onClick={() => setPeriodMode('month')}
            >
              รายเดือน
            </Button>
            <Button
              type="button"
              role="tab"
              aria-selected={periodMode === 'range'}
              variant={periodMode === 'range' ? 'primary' : 'ghost'}
              className="min-h-10"
              onClick={() => setPeriodMode('range')}
            >
              ช่วงวันที่
            </Button>
          </div>

          {periodMode === 'month' ? (
            <Field id="dash-month" label="เดือน">
              <div className="flex flex-nowrap items-center gap-2">
                <Button
                  type="button"
                  variant="secondary"
                  className="min-h-11 min-w-11 shrink-0 px-0"
                  aria-label="เดือนก่อนหน้า"
                  onClick={() => onMonthChange(shiftMonth(monthKey, -1))}
                >
                  ‹
                </Button>
                <Select
                  id="dash-month"
                  className="w-auto min-w-[10rem] max-w-[16rem] flex-1"
                  value={monthOptions.includes(monthKey) ? monthKey : monthOptions[0] || monthKey}
                  onChange={(e) => onMonthChange(e.target.value)}
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
                  disabled={
                    shiftMonth(monthKey, 1) > currentMonthKey() &&
                    !monthOptions.includes(shiftMonth(monthKey, 1))
                  }
                  onClick={() => onMonthChange(shiftMonth(monthKey, 1))}
                >
                  ›
                </Button>
              </div>
            </Field>
          ) : (
            <div className="grid gap-3 sm:grid-cols-2">
              <Field id="dash-from" label="ตั้งแต่">
                <Input
                  id="dash-from"
                  type="date"
                  value={rangeFrom}
                  max={rangeTo || undefined}
                  onChange={(e) => setRangeFrom(e.target.value)}
                />
              </Field>
              <Field id="dash-to" label="ถึงวันที่">
                <Input
                  id="dash-to"
                  type="date"
                  value={rangeTo}
                  min={rangeFrom || undefined}
                  onChange={(e) => setRangeTo(e.target.value)}
                />
              </Field>
            </div>
          )}
        </Card>
      </div>

      {error ? <p className="text-sm text-destructive">{error}</p> : null}
      {loading ? <p className="text-sm text-muted">กำลังโหลด…</p> : null}

      <Link to="/ledger" className="block">
        <Card className="border-accent/30 bg-sky-50/60 p-6 transition-colors hover:border-accent/50">
          <p className="text-xs font-medium uppercase tracking-wide text-muted">
            เงินคงเหลือในบัญชี (ควรมี)
          </p>
          <p className="mt-3 text-3xl font-semibold tabular-nums text-ink sm:text-4xl">
            {formatMoney(allTotals.incomeTotal - allTotals.expenseTotal)}
            <span className="ml-2 text-base font-normal text-muted">บาท</span>
          </p>
          <p className="mt-3 text-sm text-muted">
            จากรายรับรวม {formatMoney(allTotals.incomeTotal)} − รายจ่ายรวม{' '}
            {formatMoney(allTotals.expenseTotal)} ทุกเดือน
          </p>
        </Card>
      </Link>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {cards.map((c) => (
          <Link key={c.label} to={c.to} className="block">
            <Card className="h-full p-5 transition-colors hover:border-accent/40">
              <p className="text-xs font-medium uppercase tracking-wide text-muted">{c.label}</p>
              <p className="mt-3 text-2xl font-semibold tabular-nums text-ink">
                {c.value}
                <span className="ml-1 text-sm font-normal text-muted">{c.suffix}</span>
              </p>
            </Card>
          </Link>
        ))}
      </div>
    </div>
  );
}
