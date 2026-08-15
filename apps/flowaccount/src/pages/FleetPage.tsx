import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { calcFleetCost, calcFleetMargin } from '../calc/fleet';
import { listCategories } from '../data/categories';
import { listFleetAssets } from '../data/fleetAssets';
import { createFleetLog, listFleetLogs } from '../data/fleetLogs';
import type { FaCategory, FaFleetAsset, FaFleetLog } from '../types';
import { formatMoney } from '../types';
import { useAuth } from '../auth/AuthProvider';
import Button from '../components/ui/Button';
import DataTable, { Column } from '../components/ui/DataTable';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import Modal from '../components/ui/Modal';
import MoneyInput from '../components/ui/MoneyInput';
import Select from '../components/ui/Select';

const today = () => new Date().toISOString().slice(0, 10);

export default function FleetPage() {
  const { user } = useAuth();
  const [logs, setLogs] = useState<FaFleetLog[]>([]);
  const [assets, setAssets] = useState<FaFleetAsset[]>([]);
  const [categories, setCategories] = useState<FaCategory[]>([]);
  const [error, setError] = useState('');
  const [open, setOpen] = useState(false);

  const [assetId, setAssetId] = useState('');
  const [workDate, setWorkDate] = useState(today());
  const [driverName, setDriverName] = useState('');
  const [workDays, setWorkDays] = useState<number | ''>(1);
  const [otAmount, setOtAmount] = useState<number | ''>(0);
  const [incomeAmount, setIncomeAmount] = useState<number | ''>(0);
  const [postToLedger, setPostToLedger] = useState(false);
  const [costCategoryId, setCostCategoryId] = useState('');

  const asset = useMemo(() => assets.find((a) => a.id === assetId) || null, [assets, assetId]);

  const previewCost = useMemo(() => {
    if (!asset) return 0;
    return calcFleetCost({
      dailyRate: asset.dailyRate,
      workDays: Number(workDays) || 0,
      otAmount: Number(otAmount) || 0,
    });
  }, [asset, workDays, otAmount]);

  const previewMargin = useMemo(
    () => calcFleetMargin(Number(incomeAmount) || 0, previewCost),
    [incomeAmount, previewCost],
  );

  const reload = useCallback(async () => {
    setError('');
    try {
      const [l, a, c] = await Promise.all([listFleetLogs(), listFleetAssets(), listCategories()]);
      setLogs(l);
      setAssets(a);
      const expenseCats = c.filter((x) => x.kind === 'expense' || x.kind === 'both');
      setCategories(expenseCats);
      if (!assetId && a[0]) setAssetId(a[0].id);
      if (!costCategoryId && expenseCats[0]) setCostCategoryId(expenseCats[0].id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'โหลดไม่สำเร็จ');
    }
  }, [assetId, costCategoryId]);

  useEffect(() => {
    void reload();
  }, []);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!asset) return;
    try {
      const log = await createFleetLog({
        asset,
        workDate,
        driverName,
        workDays: Number(workDays) || 0,
        otAmount: Number(otAmount) || 0,
        incomeAmount: Number(incomeAmount) || 0,
        postToLedger,
        costCategoryId,
        createdBy: user?.username,
      });
      setOpen(false);
      await reload();
      window.open(`/fleet/${log.id}/statement`, '_blank');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
    }
  };

  const columns: Column<FaFleetLog>[] = [
    { key: 'date', header: 'วันที่', render: (r) => r.workDate },
    { key: 'asset', header: 'รถ/เครื่องจักร', render: (r) => r.assetNameSnapshot },
    { key: 'driver', header: 'คนขับ', render: (r) => r.driverName },
    {
      key: 'days',
      header: 'วัน',
      className: 'tabular-nums',
      render: (r) => r.workDays,
    },
    {
      key: 'cost',
      header: 'ต้นทุน',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.totalCost),
    },
    {
      key: 'income',
      header: 'รายได้',
      className: 'text-right tabular-nums',
      render: (r) => formatMoney(r.incomeAmount),
    },
    {
      key: 'actions',
      header: '',
      render: (r) => (
        <Link to={`/fleet/${r.id}/statement`} className="text-sm text-accent hover:underline">
          สรุปรายคัน
        </Link>
      ),
    },
  ];

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight">ต้นทุนรถและเครื่องจักร</h2>
          <p className="mt-1 text-sm text-muted">บันทึกต้นทุนรายคันและออกใบสรุป</p>
        </div>
        <Button onClick={() => setOpen(true)}>บันทึกรายการ</Button>
      </div>

      {error ? <p className="text-sm text-destructive">{error}</p> : null}
      <DataTable columns={columns} rows={logs} rowKey={(r) => r.id} />

      <Modal
        open={open}
        title="บันทึกต้นทุนรถ"
        onClose={() => setOpen(false)}
        footer={
          <>
            <Button variant="secondary" onClick={() => setOpen(false)}>
              ยกเลิก
            </Button>
            <Button type="submit" form="fleet-form">
              บันทึกและเปิดสรุป
            </Button>
          </>
        }
      >
        <form id="fleet-form" className="space-y-4" onSubmit={submit}>
          <Field id="f-asset" label="รถ/เครื่องจักร">
            <Select id="f-asset" value={assetId} onChange={(e) => setAssetId(e.target.value)} required>
              {assets.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name} ({formatMoney(a.dailyRate)}/วัน)
                </option>
              ))}
            </Select>
          </Field>
          <Field id="f-date" label="วันที่ทำงาน">
            <Input id="f-date" type="date" value={workDate} onChange={(e) => setWorkDate(e.target.value)} required />
          </Field>
          <Field id="f-driver" label="ชื่อคนขับ">
            <Input id="f-driver" value={driverName} onChange={(e) => setDriverName(e.target.value)} required />
          </Field>
          <Field id="f-days" label="จำนวนวัน">
            <MoneyInput id="f-days" value={workDays} onValueChange={setWorkDays} />
          </Field>
          <Field id="f-ot" label="ค่า OT ของรถ">
            <MoneyInput id="f-ot" value={otAmount} onValueChange={setOtAmount} />
          </Field>
          <Field id="f-income" label="รายได้ที่เกี่ยวเนื่อง (ถ้ามี)">
            <MoneyInput id="f-income" value={incomeAmount} onValueChange={setIncomeAmount} />
          </Field>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={postToLedger} onChange={(e) => setPostToLedger(e.target.checked)} />
            บันทึกต้นทุนลงสมุดรายจ่าย
          </label>
          {postToLedger ? (
            <Field id="f-cat" label="หมวดบัญชี">
              <Select id="f-cat" value={costCategoryId} onChange={(e) => setCostCategoryId(e.target.value)}>
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </Select>
            </Field>
          ) : null}
          <p className="text-sm text-muted">
            ต้นทุนรวม <span className="tabular-nums font-medium text-ink">{formatMoney(previewCost)}</span>
            {' · '}กำไรขั้นต้น{' '}
            <span className="tabular-nums font-medium text-ink">{formatMoney(previewMargin)}</span>
          </p>
        </form>
      </Modal>
    </div>
  );
}
