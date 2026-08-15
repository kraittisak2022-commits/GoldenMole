import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { sumLedgerTotals } from '../data/categories';
import { listFleetLogs } from '../data/fleetLogs';
import { listLedgerEntries } from '../data/ledger';
import { listReimbursements } from '../data/reimbursements';
import { currentMonthKey, formatMonthLabel } from '../lib/ledgerMonth';
import { formatMoney } from '../types';
import Card from '../components/ui/Card';

export default function DashboardPage() {
  const { user } = useAuth();
  const [balance, setBalance] = useState(0);
  const [totalIncome, setTotalIncome] = useState(0);
  const [totalExpense, setTotalExpense] = useState(0);
  const [monthIncome, setMonthIncome] = useState(0);
  const [monthExpense, setMonthExpense] = useState(0);
  const [pendingReimb, setPendingReimb] = useState(0);
  const [fleetCost, setFleetCost] = useState(0);
  const [error, setError] = useState('');
  const monthKey = currentMonthKey();

  useEffect(() => {
    void (async () => {
      try {
        const [ledger, reimb, fleet] = await Promise.all([
          listLedgerEntries(),
          listReimbursements(),
          listFleetLogs(),
        ]);
        const all = sumLedgerTotals(ledger);
        const monthLedger = ledger.filter((e) => e.date.startsWith(monthKey));
        const month = sumLedgerTotals(monthLedger);
        setTotalIncome(all.incomeTotal);
        setTotalExpense(all.expenseTotal);
        setBalance(all.incomeTotal - all.expenseTotal);
        setMonthIncome(month.incomeTotal);
        setMonthExpense(month.expenseTotal);
        setPendingReimb(reimb.filter((r) => r.status === 'pending').length);
        setFleetCost(
          fleet.filter((f) => f.workDate.startsWith(monthKey)).reduce((s, f) => s + f.totalCost, 0),
        );
      } catch (err) {
        setError(err instanceof Error ? err.message : 'โหลดแดชบอร์ดไม่สำเร็จ');
      }
    })();
  }, [monthKey]);

  const cards = [
    { label: `รายรับ ${formatMonthLabel(monthKey)}`, value: formatMoney(monthIncome), to: `/ledger?month=${monthKey}`, suffix: 'บาท' },
    { label: `รายจ่าย ${formatMonthLabel(monthKey)}`, value: formatMoney(monthExpense), to: `/ledger?month=${monthKey}`, suffix: 'บาท' },
    { label: 'รออนุมัติเบิก', value: String(pendingReimb), to: '/reimbursements', suffix: 'รายการ' },
    { label: 'ต้นทุนรถเดือนนี้', value: formatMoney(fleetCost), to: '/fleet', suffix: 'บาท' },
  ];

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div>
        <h2 className="text-2xl font-semibold tracking-tight text-ink">แดชบอร์ด</h2>
        <p className="mt-2 text-sm text-muted">ยินดีต้อนรับ {user?.displayName}</p>
      </div>

      {error ? <p className="text-sm text-destructive">{error}</p> : null}

      <Link to="/ledger" className="block">
        <Card className="border-accent/30 bg-sky-50/60 p-6 transition-colors hover:border-accent/50">
          <p className="text-xs font-medium uppercase tracking-wide text-muted">
            เงินคงเหลือในบัญชี (ควรมี)
          </p>
          <p className="mt-3 text-3xl font-semibold tabular-nums text-ink sm:text-4xl">
            {formatMoney(balance)}
            <span className="ml-2 text-base font-normal text-muted">บาท</span>
          </p>
          <p className="mt-3 text-sm text-muted">
            จากรายรับรวม {formatMoney(totalIncome)} − รายจ่ายรวม {formatMoney(totalExpense)} ทุกเดือน
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
