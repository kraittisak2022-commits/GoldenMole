import { FormEvent, useEffect, useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { getPayerByToken } from '../data/payers';
import { uploadReimbProof } from '../data/reimbProof';
import { saveReimbursementBatch } from '../data/reimbursements';
import type { FaReimbPayer } from '../types';
import { formatMoney } from '../types';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import MoneyInput from '../components/ui/MoneyInput';

const today = () => new Date().toISOString().slice(0, 10);

type LineItem = { description: string; amount: number | ''; receiptFile: File | null };

export default function ClaimPage() {
  const { token = '' } = useParams();
  const [payer, setPayer] = useState<FaReimbPayer | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [done, setDone] = useState(false);
  const [saving, setSaving] = useState(false);
  const [date, setDate] = useState(today());
  const [items, setItems] = useState<LineItem[]>([{ description: '', amount: '', receiptFile: null }]);

  useEffect(() => {
    void (async () => {
      setLoading(true);
      setError('');
      try {
        const p = await getPayerByToken(token);
        setPayer(p);
        if (!p) setError('ลิงก์ไม่ถูกต้องหรือถูกปิดใช้งาน');
      } catch (err) {
        setError(err instanceof Error ? err.message : 'โหลดไม่สำเร็จ');
      } finally {
        setLoading(false);
      }
    })();
  }, [token]);

  const total = useMemo(
    () => items.reduce((s, item) => s + (typeof item.amount === 'number' ? item.amount : 0), 0),
    [items],
  );

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!payer) return;
    setSaving(true);
    setError('');
    try {
      const prepared = [];
      for (const item of items) {
        const description = item.description.trim();
        const amount = Number(item.amount) || 0;
        if (!description || amount <= 0) continue;
        let receiptUrl: string | null = null;
        if (item.receiptFile) {
          receiptUrl = await uploadReimbProof(item.receiptFile, `claims/${payer.id}`);
        }
        prepared.push({ description, amount, receiptUrl });
      }
      await saveReimbursementBatch({
        date,
        payerName: payer.name,
        payerId: payer.id,
        items: prepared,
      });
      setDone(true);
      setItems([{ description: '', amount: '', receiptFile: null }]);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="min-h-screen bg-page px-4 py-8 text-ink">
      <div className="mx-auto max-w-xl space-y-6">
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-muted">FlowAccount</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight">แจ้งรายการสำรองจ่าย</h1>
          {payer ? (
            <p className="mt-2 text-sm text-muted">
              สำหรับ <span className="font-medium text-ink">{payer.name}</span> — กรอกรายการที่จ่ายเงินไปเพื่อเบิกคืน
            </p>
          ) : null}
        </div>

        {loading ? <p className="text-sm text-muted">กำลังโหลด…</p> : null}
        {error ? <p className="text-sm text-destructive">{error}</p> : null}
        {done ? (
          <Card className="space-y-3 p-5">
            <p className="text-sm font-medium text-ink">ส่งรายการเรียบร้อยแล้ว</p>
            <p className="text-sm text-muted">รอแอดมินตรวจสอบและอนุมัติการเบิกเงินคืน</p>
            <Button onClick={() => setDone(false)}>ส่งรายการเพิ่ม</Button>
          </Card>
        ) : null}

        {!loading && payer && !done ? (
          <Card className="p-5">
            <form className="space-y-4" onSubmit={submit}>
              <Field id="claim-date" label="วันที่จ่าย">
                <Input id="claim-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} required />
              </Field>

              <div className="space-y-3">
                <div className="flex items-center justify-between gap-2">
                  <p className="text-sm font-medium text-ink">รายการที่จ่าย</p>
                  <Button
                    type="button"
                    variant="secondary"
                    className="min-h-9"
                    onClick={() =>
                      setItems((prev) => [...prev, { description: '', amount: '', receiptFile: null }])
                    }
                  >
                    + เพิ่มรายการ
                  </Button>
                </div>
                {items.map((item, index) => (
                  <div key={index} className="space-y-3 rounded-DEFAULT border border-border p-3">
                    <Field id={`claim-item-${index}`} label="รายการ">
                      <Input
                        id={`claim-item-${index}`}
                        placeholder="เช่น ค่าน้ำมัน / ค่าวัสดุ"
                        value={item.description}
                        onChange={(e) =>
                          setItems((prev) =>
                            prev.map((row, i) => (i === index ? { ...row, description: e.target.value } : row)),
                          )
                        }
                        required
                      />
                    </Field>
                    <Field id={`claim-amount-${index}`} label="ราคา (บาท)">
                      <MoneyInput
                        id={`claim-amount-${index}`}
                        placeholder="0"
                        value={item.amount}
                        onValueChange={(v) =>
                          setItems((prev) => prev.map((row, i) => (i === index ? { ...row, amount: v } : row)))
                        }
                        required
                      />
                    </Field>
                    <Field id={`claim-file-${index}`} label="แนบใบเสร็จ / หลักฐาน (ถ้ามี)">
                      <Input
                        id={`claim-file-${index}`}
                        type="file"
                        accept="image/*,.pdf"
                        onChange={(e) =>
                          setItems((prev) =>
                            prev.map((row, i) =>
                              i === index ? { ...row, receiptFile: e.target.files?.[0] || null } : row,
                            ),
                          )
                        }
                      />
                    </Field>
                    {items.length > 1 ? (
                      <Button
                        type="button"
                        variant="ghost"
                        className="min-h-9"
                        onClick={() => setItems((prev) => prev.filter((_, i) => i !== index))}
                      >
                        ลบรายการนี้
                      </Button>
                    ) : null}
                  </div>
                ))}
              </div>

              <p className="text-sm text-muted">
                รวมเงินที่จ่าย:{' '}
                <span className="font-semibold tabular-nums text-ink">{formatMoney(total)}</span> บาท
              </p>

              <Button type="submit" className="w-full" disabled={saving}>
                {saving ? 'กำลังส่ง…' : 'ส่งรายการเบิกคืน'}
              </Button>
            </form>
          </Card>
        ) : null}

        <p className="text-center text-xs text-muted">
          <Link to="/login" className="hover:underline">
            เข้าสู่ระบบแอดมิน
          </Link>
        </p>
      </div>
    </div>
  );
}
