import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { listFleetLogs } from '../data/fleetLogs';
import { listLedgerEntries } from '../data/ledger';
import { listReimbursements } from '../data/reimbursements';
import { formatMoney } from '../types';
import Card from '../components/ui/Card';

export default function DashboardPage() {
  const { user } = useAuth();
  const [income, setIncome] = useState(0);
  const [expense, setExpense] = useState(0);
  const [pendingReimb, setPendingReimb] = useState(0);
  const [fleetCost, setFleetCost] = useState(0);
  const [error, setError] = useState('');

  useEffect(() => {
    const monthPrefix = new Date().toISOString().slice(0, 7);
    void (async () => {
      try {
        const [ledger, reimb, fleet] = await Promise.all([
          listLedgerEntries(),
          listReimbursements(),
          listFleetLogs(),
        ]);
        const monthLedger = ledger.filter((e) => e.date.startsWith(monthPrefix));
        setIncome(monthLedger.filter((e) => e.entryType === 'income').reduce((s, e) => s + e.amount, 0));
        setExpense(monthLedger.filter((e) => e.entryType === 'expense').reduce((s, e) => s + e.amount, 0));
        setPendingReimb(reimb.filter((r) => r.status === 'pending').length);
        setFleetCost(
          fleet.filter((f) => f.workDate.startsWith(monthPrefix)).reduce((s, f) => s + f.totalCost, 0),
        );
      } catch (err) {
        setError(err instanceof Error ? err.message : 'โหลดแดชบอร์ดไม่สำเร็จ');
      }
    })();
  }, []);

  const cards = [
    { label: 'รายรับเดือนนี้', value: formatMoney(income), to: '/ledger', suffix: 'บาท' },
    { label: 'รายจ่ายเดือนนี้', value: formatMoney(expense), to: '/ledger', suffix: 'บาท' },
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
