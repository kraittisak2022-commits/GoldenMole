import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { calcPayrollTotal } from '../calc/payroll';
import { listCategories } from '../data/categories';
import { listEmployees } from '../data/employees';
import { createPayrollSlip, listPayrollSlips } from '../data/payroll';
import type { FaCategory, FaEmployee, FaPayrollSlip } from '../types';
import { EMPLOYEE_TYPE_LABEL, formatMoney } from '../types';
import { useAuth } from '../auth/AuthProvider';
import Button from '../components/ui/Button';
import DataTable, { Column } from '../components/ui/DataTable';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import Modal from '../components/ui/Modal';
import MoneyInput from '../components/ui/MoneyInput';
import Select from '../components/ui/Select';

const today = () => new Date().toISOString().slice(0, 10);

export default function PayrollPage() {
  const { user } = useAuth();
  const [slips, setSlips] = useState<FaPayrollSlip[]>([]);
  const [employees, setEmployees] = useState<FaEmployee[]>([]);
  const [categories, setCategories] = useState<FaCategory[]>([]);
  const [error, setError] = useState('');
  const [open, setOpen] = useState(false);

  const [employeeId, setEmployeeId] = useState('');
  const [payDate, setPayDate] = useState(today());
  const [workDays, setWorkDays] = useState<number | ''>(0);
  const [otAmount, setOtAmount] = useState<number | ''>(0);
  const [specialAmount, setSpecialAmount] = useState<number | ''>(0);
  const [postToLedger, setPostToLedger] = useState(true);
  const [salaryCategoryId, setSalaryCategoryId] = useState('');

  const employee = useMemo(
    () => employees.find((e) => e.id === employeeId) || null,
    [employees, employeeId],
  );

  const previewTotal = useMemo(() => {
    if (!employee) return 0;
    return calcPayrollTotal({
      employeeType: employee.type,
      basePay: employee.basePay,
      workDays: Number(workDays) || 0,
      otAmount: Number(otAmount) || 0,
      specialAmount: Number(specialAmount) || 0,
    });
  }, [employee, workDays, otAmount, specialAmount]);

  const reload = useCallback(async () => {
    setError('');
    try {
      const [s, e, c] = await Promise.all([listPayrollSlips(), listEmployees(), listCategories()]);
      setSlips(s);
      setEmployees(e);
      const expenseCats = c.filter((x) => x.kind === 'expense' || x.kind === 'both');
      setCategories(expenseCats);
      const salary = expenseCats.find((x) => x.id === 'cat-salary') || expenseCats[0];
      if (salary) setSalaryCategoryId(salary.id);
      if (!employeeId && e[0]) setEmployeeId(e[0].id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'โหลดไม่สำเร็จ');
    }
  }, [employeeId]);

  useEffect(() => {
    void reload();
  }, []);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!employee) return;
    try {
      const slip = await createPayrollSlip({
        employee,
        payDate,
        workDays: Number(workDays) || 0,
        otAmount: Number(otAmount) || 0,
        specialAmount: Number(specialAmount) || 0,
        postToLedger,
        salaryCategoryId,
        createdBy: user?.username,
      });
      setOpen(false);
      await reload();
      window.open(`/payroll/${slip.id}/payslip`, '_blank');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
    }
  };

  const columns: Column<FaPayrollSlip>[] = [
    { key: 'date', header: 'วันที่จ่าย', render: (r) => r.payDate },
    { key: 'name', header: 'พนักงาน', render: (r) => r.employeeName },
    {
      key: 'type',
      header: 'ประเภท',
      render: (r) => EMPLOYEE_TYPE_LABEL[r.employeeType],
    },
    {
      key: 'days',
      header: 'วันทำงาน',
      className: 'tabular-nums',
      render: (r) => r.workDays,
    },
    {
      key: 'total',
      header: 'รวม',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.total),
    },
    {
      key: 'actions',
      header: '',
      render: (r) => (
        <Link to={`/payroll/${r.id}/payslip`} className="text-sm text-accent hover:underline">
          เปิดสลิป
        </Link>
      ),
    },
  ];

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight">เงินเดือนพนักงาน</h2>
          <p className="mt-1 text-sm text-muted">คำนวณอัตโนมัติและออกใบจ่ายเงินเดือนรายบุคคล</p>
        </div>
        <Button onClick={() => setOpen(true)}>สร้างสลิป</Button>
      </div>

      {error ? <p className="text-sm text-destructive">{error}</p> : null}
      <DataTable columns={columns} rows={slips} rowKey={(r) => r.id} />

      <Modal
        open={open}
        title="สร้างใบจ่ายเงินเดือน"
        onClose={() => setOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setOpen(false)}>
              ยกเลิก
            </Button>
            <Button type="submit" form="pay-form">
              บันทึกและเปิดสลิป
            </Button>
          </>
        }
      >
        <form id="pay-form" className="space-y-4" onSubmit={submit}>
          <Field id="p-emp" label="พนักงาน">
            <Select id="p-emp" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} required>
              {employees.map((emp) => (
                <option key={emp.id} value={emp.id}>
                  {emp.name} ({EMPLOYEE_TYPE_LABEL[emp.type]})
                </option>
              ))}
            </Select>
          </Field>
          <Field id="p-date" label="วันที่จ่าย">
            <Input id="p-date" type="date" value={payDate} onChange={(e) => setPayDate(e.target.value)} required />
          </Field>
          <Field id="p-days" label="จำนวนวันทำงาน">
            <MoneyInput id="p-days" value={workDays} onValueChange={setWorkDays} />
          </Field>
          <Field id="p-ot" label="ค่า OT">
            <MoneyInput id="p-ot" value={otAmount} onValueChange={setOtAmount} />
          </Field>
          <Field id="p-special" label="เงินพิเศษ">
            <MoneyInput id="p-special" value={specialAmount} onValueChange={setSpecialAmount} />
          </Field>
          <label className="flex items-center gap-2 text-sm text-ink">
            <input
              type="checkbox"
              checked={postToLedger}
              onChange={(e) => setPostToLedger(e.target.checked)}
            />
            บันทึกลงสมุดรายจ่าย (หมวดเงินเดือน)
          </label>
          {postToLedger ? (
            <Field id="p-cat" label="หมวดบัญชี">
              <Select
                id="p-cat"
                value={salaryCategoryId}
                onChange={(e) => setSalaryCategoryId(e.target.value)}
              >
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </Select>
            </Field>
          ) : null}
          <p className="text-sm text-muted">
            รวมสุทธิ:{' '}
            <span className="font-semibold tabular-nums text-ink">{formatMoney(previewTotal)}</span> บาท
          </p>
        </form>
      </Modal>
    </div>
  );
}
