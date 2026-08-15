import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { getPayrollSlip } from '../data/payroll';
import type { FaPayrollSlip } from '../types';
import { EMPLOYEE_TYPE_LABEL, formatMoney } from '../types';
import Button from '../components/ui/Button';

export default function PayslipPage() {
  const { id } = useParams<{ id: string }>();
  const [slip, setSlip] = useState<FaPayrollSlip | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!id) return;
    void getPayrollSlip(id)
      .then((s) => setSlip(s))
      .catch((err) => setError(err instanceof Error ? err.message : 'โหลดไม่สำเร็จ'));
  }, [id]);

  if (error) {
    return <p className="p-8 text-sm text-destructive">{error}</p>;
  }
  if (!slip) {
    return <p className="p-8 text-sm text-muted">กำลังโหลดสลิป…</p>;
  }

  const baseLine =
    slip.employeeType === 'monthly'
      ? slip.basePay
      : slip.basePay * slip.workDays;

  return (
    <div className="mx-auto max-w-[720px] bg-white p-8 text-ink print:max-w-none print:p-10">
      <div className="mb-6 flex items-start justify-between gap-4 print:hidden">
        <Link to="/payroll" className="text-sm text-accent hover:underline">
          ← กลับ
        </Link>
        <Button onClick={() => window.print()}>พิมพ์</Button>
      </div>

      <header className="border-b border-border pb-4">
        <p className="text-xs uppercase tracking-wider text-muted">GoldenMole · FlowAccount</p>
        <h1 className="mt-1 text-2xl font-semibold">ใบจ่ายเงินเดือนรายบุคคล</h1>
        <p className="mt-1 text-sm text-muted">Payslip</p>
      </header>

      <dl className="mt-6 grid grid-cols-2 gap-x-6 gap-y-3 text-sm">
        <div>
          <dt className="text-muted">ชื่อพนักงาน</dt>
          <dd className="font-medium">{slip.employeeName}</dd>
        </div>
        <div>
          <dt className="text-muted">ประเภท</dt>
          <dd>{EMPLOYEE_TYPE_LABEL[slip.employeeType]}</dd>
        </div>
        <div>
          <dt className="text-muted">วันที่จ่าย</dt>
          <dd>{slip.payDate}</dd>
        </div>
        <div>
          <dt className="text-muted">วันทำงาน</dt>
          <dd className="tabular-nums">{slip.workDays} วัน</dd>
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
              {slip.employeeType === 'monthly'
                ? 'เงินเดือนพื้นฐาน'
                : `ค่าแรง (${formatMoney(slip.basePay)} × ${slip.workDays} วัน)`}
            </td>
            <td className="py-2 text-right tabular-nums">{formatMoney(baseLine)}</td>
          </tr>
          <tr className="border-b border-border">
            <td className="py-2">ค่า OT</td>
            <td className="py-2 text-right tabular-nums">{formatMoney(slip.otAmount)}</td>
          </tr>
          <tr className="border-b border-border">
            <td className="py-2">เงินพิเศษ</td>
            <td className="py-2 text-right tabular-nums">{formatMoney(slip.specialAmount)}</td>
          </tr>
          <tr>
            <td className="py-3 font-semibold">รวมสุทธิ</td>
            <td className="py-3 text-right text-lg font-semibold tabular-nums">
              {formatMoney(slip.total)} บาท
            </td>
          </tr>
        </tbody>
      </table>

      <div className="mt-16 grid grid-cols-2 gap-8 text-center text-sm text-muted">
        <div>
          <div className="mx-auto mb-2 h-12 w-40 border-b border-border" />
          ผู้รับเงิน
        </div>
        <div>
          <div className="mx-auto mb-2 h-12 w-40 border-b border-border" />
          ผู้จ่ายเงิน
        </div>
      </div>
    </div>
  );
}
