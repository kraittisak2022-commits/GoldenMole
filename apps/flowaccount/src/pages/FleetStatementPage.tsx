import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { calcFleetMargin } from '../calc/fleet';
import { getFleetLog } from '../data/fleetLogs';
import type { FaFleetLog } from '../types';
import { formatMoney } from '../types';
import Button from '../components/ui/Button';

export default function FleetStatementPage() {
  const { id } = useParams<{ id: string }>();
  const [log, setLog] = useState<FaFleetLog | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!id) return;
    void getFleetLog(id)
      .then(setLog)
      .catch((err) => setError(err instanceof Error ? err.message : 'โหลดไม่สำเร็จ'));
  }, [id]);

  if (error) return <p className="p-8 text-sm text-destructive">{error}</p>;
  if (!log) return <p className="p-8 text-sm text-muted">กำลังโหลด…</p>;

  const margin = calcFleetMargin(log.incomeAmount, log.totalCost);
  const laborLine = log.dailyRateSnapshot * log.workDays;

  return (
    <div className="mx-auto max-w-[720px] bg-white p-8 text-ink print:max-w-none print:p-10">
      <div className="mb-6 flex items-start justify-between gap-4 print:hidden">
        <Link to="/fleet" className="text-sm text-accent hover:underline">
          ← กลับ
        </Link>
        <Button onClick={() => window.print()}>พิมพ์</Button>
      </div>

      <header className="border-b border-border pb-4">
        <p className="text-xs uppercase tracking-wider text-muted">GoldenMole · FlowAccount</p>
        <h1 className="mt-1 text-2xl font-semibold">ใบสรุปต้นทุนรายคัน</h1>
        <p className="mt-1 text-sm text-muted">Fleet / Machinery Cost Statement</p>
      </header>

      <dl className="mt-6 grid grid-cols-2 gap-x-6 gap-y-3 text-sm">
        <div>
          <dt className="text-muted">รถ/เครื่องจักร</dt>
          <dd className="font-medium">{log.assetNameSnapshot}</dd>
        </div>
        <div>
          <dt className="text-muted">คนขับ</dt>
          <dd>{log.driverName}</dd>
        </div>
        <div>
          <dt className="text-muted">วันที่ทำงาน</dt>
          <dd>{log.workDate}</dd>
        </div>
        <div>
          <dt className="text-muted">จำนวนวัน</dt>
          <dd className="tabular-nums">{log.workDays} วัน</dd>
        </div>
      </dl>

      <table className="mt-8 w-full text-sm">
        <thead>
          <tr className="border-b border-border text-left text-muted">
            <th className="py-2 font-medium">รายการ</th>
            <th className="py-2 text-right font-medium">จำนวนเงิน</th>
          </tr>
        </thead>
        <tbody>
          <tr className="border-b border-border">
            <td className="py-2">
              ค่าแรงรถ ({formatMoney(log.dailyRateSnapshot)} × {log.workDays} วัน)
            </td>
            <td className="py-2 text-right tabular-nums">{formatMoney(laborLine)}</td>
          </tr>
          <tr className="border-b border-border">
            <td className="py-2">ค่า OT ของรถ</td>
            <td className="py-2 text-right tabular-nums">{formatMoney(log.otAmount)}</td>
          </tr>
          <tr className="border-b border-border">
            <td className="py-2 font-medium">รวมต้นทุน</td>
            <td className="py-2 text-right font-medium tabular-nums">{formatMoney(log.totalCost)}</td>
          </tr>
          <tr className="border-b border-border">
            <td className="py-2">รายได้ที่เกี่ยวเนื่อง</td>
            <td className="py-2 text-right tabular-nums">{formatMoney(log.incomeAmount)}</td>
          </tr>
          <tr>
            <td className="py-3 font-semibold">กำไร / (ขาดทุน) ขั้นต้น</td>
            <td className="py-3 text-right text-lg font-semibold tabular-nums">
              {formatMoney(margin)} บาท
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  );
}
