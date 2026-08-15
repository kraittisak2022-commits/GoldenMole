import { FormEvent, useCallback, useEffect, useState } from 'react';
import { listEmployees, saveEmployee, setEmployeeInactive } from '../data/employees';
import { listFleetAssets, saveFleetAsset, setFleetAssetInactive } from '../data/fleetAssets';
import type { EmployeeType, FaEmployee, FaFleetAsset } from '../types';
import { EMPLOYEE_TYPE_LABEL, formatMoney } from '../types';
import Button from '../components/ui/Button';
import DataTable, { Column } from '../components/ui/DataTable';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import Modal from '../components/ui/Modal';
import MoneyInput from '../components/ui/MoneyInput';
import Select from '../components/ui/Select';

export default function MastersPage() {
  const [tab, setTab] = useState<'employees' | 'fleet'>('employees');
  const [employees, setEmployees] = useState<FaEmployee[]>([]);
  const [assets, setAssets] = useState<FaFleetAsset[]>([]);
  const [error, setError] = useState('');
  const [empOpen, setEmpOpen] = useState(false);
  const [fleetOpen, setFleetOpen] = useState(false);

  const [empName, setEmpName] = useState('');
  const [empType, setEmpType] = useState<EmployeeType>('daily');
  const [empPay, setEmpPay] = useState<number | ''>('');

  const [fleetName, setFleetName] = useState('');
  const [fleetRate, setFleetRate] = useState<number | ''>('');

  const reload = useCallback(async () => {
    setError('');
    try {
      const [e, a] = await Promise.all([
        listEmployees({ includeInactive: true }),
        listFleetAssets({ includeInactive: true }),
      ]);
      setEmployees(e);
      setAssets(a);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'โหลดไม่สำเร็จ');
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  const submitEmp = async (e: FormEvent) => {
    e.preventDefault();
    if (empPay === '') return;
    try {
      await saveEmployee({ name: empName, type: empType, basePay: Number(empPay) });
      setEmpOpen(false);
      setEmpName('');
      setEmpPay('');
      await reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
    }
  };

  const submitFleet = async (e: FormEvent) => {
    e.preventDefault();
    if (fleetRate === '') return;
    try {
      await saveFleetAsset({ name: fleetName, dailyRate: Number(fleetRate) });
      setFleetOpen(false);
      setFleetName('');
      setFleetRate('');
      await reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
    }
  };

  const empColumns: Column<FaEmployee>[] = [
    { key: 'name', header: 'ชื่อ', render: (r) => r.name },
    { key: 'type', header: 'ประเภท', render: (r) => EMPLOYEE_TYPE_LABEL[r.type] },
    {
      key: 'pay',
      header: 'ค่าแรง / เงินเดือน',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.basePay),
    },
    {
      key: 'status',
      header: 'สถานะ',
      render: (r) => (r.inactive ? 'ปิดใช้งาน' : 'ใช้งาน'),
    },
    {
      key: 'actions',
      header: '',
      render: (r) => (
        <Button
          variant="ghost"
          className="min-h-9"
          onClick={() => void setEmployeeInactive(r.id, !r.inactive).then(reload)}
        >
          {r.inactive ? 'เปิดใช้' : 'ปิดใช้'}
        </Button>
      ),
    },
  ];

  const fleetColumns: Column<FaFleetAsset>[] = [
    { key: 'name', header: 'ชื่อรถ/เครื่องจักร', render: (r) => r.name },
    {
      key: 'rate',
      header: 'ค่าแรงต่อวัน',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.dailyRate),
    },
    {
      key: 'status',
      header: 'สถานะ',
      render: (r) => (r.inactive ? 'ปิดใช้งาน' : 'ใช้งาน'),
    },
    {
      key: 'actions',
      header: '',
      render: (r) => (
        <Button
          variant="ghost"
          className="min-h-9"
          onClick={() => void setFleetAssetInactive(r.id, !r.inactive).then(reload)}
        >
          {r.inactive ? 'เปิดใช้' : 'ปิดใช้'}
        </Button>
      ),
    },
  ];

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div>
        <h2 className="text-2xl font-semibold tracking-tight">ข้อมูลหลัก</h2>
        <p className="mt-1 text-sm text-muted">พนักงานและรถ/เครื่องจักรของ FlowAccount</p>
      </div>

      <div className="flex gap-2 border-b border-border pb-2">
        <Button variant={tab === 'employees' ? 'primary' : 'ghost'} onClick={() => setTab('employees')}>
          พนักงาน
        </Button>
        <Button variant={tab === 'fleet' ? 'primary' : 'ghost'} onClick={() => setTab('fleet')}>
          รถ/เครื่องจักร
        </Button>
      </div>

      {error ? <p className="text-sm text-destructive">{error}</p> : null}

      {tab === 'employees' ? (
        <>
          <div className="flex justify-end">
            <Button onClick={() => setEmpOpen(true)}>เพิ่มพนักงาน</Button>
          </div>
          <DataTable columns={empColumns} rows={employees} rowKey={(r) => r.id} />
        </>
      ) : (
        <>
          <div className="flex justify-end">
            <Button onClick={() => setFleetOpen(true)}>เพิ่มรถ/เครื่องจักร</Button>
          </div>
          <DataTable columns={fleetColumns} rows={assets} rowKey={(r) => r.id} />
        </>
      )}

      <Modal
        open={empOpen}
        title="เพิ่มพนักงาน"
        onClose={() => setEmpOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setEmpOpen(false)}>
              ยกเลิก
            </Button>
            <Button type="submit" form="emp-form">
              บันทึก
            </Button>
          </>
        }
      >
        <form id="emp-form" className="space-y-4" onSubmit={submitEmp}>
          <Field id="e-name" label="ชื่อ">
            <Input id="e-name" value={empName} onChange={(e) => setEmpName(e.target.value)} required />
          </Field>
          <Field id="e-type" label="ประเภท">
            <Select id="e-type" value={empType} onChange={(e) => setEmpType(e.target.value as EmployeeType)}>
              <option value="monthly">พนักงานเงินเดือน</option>
              <option value="daily">พนักงานรายวัน</option>
              <option value="daily_driver">พนักงานขับรถรายวัน</option>
            </Select>
          </Field>
          <Field id="e-pay" label={empType === 'monthly' ? 'เงินเดือน' : 'ค่าแรงต่อวัน'}>
            <MoneyInput id="e-pay" value={empPay} onValueChange={setEmpPay} required />
          </Field>
        </form>
      </Modal>

      <Modal
        open={fleetOpen}
        title="เพิ่มรถ/เครื่องจักร"
        onClose={() => setFleetOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setFleetOpen(false)}>
              ยกเลิก
            </Button>
            <Button type="submit" form="fleet-master-form">
              บันทึก
            </Button>
          </>
        }
      >
        <form id="fleet-master-form" className="space-y-4" onSubmit={submitFleet}>
          <Field id="fm-name" label="ชื่อ">
            <Input id="fm-name" value={fleetName} onChange={(e) => setFleetName(e.target.value)} required />
          </Field>
          <Field id="fm-rate" label="ค่าแรงต่อวัน">
            <MoneyInput id="fm-rate" value={fleetRate} onValueChange={setFleetRate} required />
          </Field>
        </form>
      </Modal>
    </div>
  );
}
