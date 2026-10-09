import { useState, type ReactNode } from 'react';
import { useParams } from 'react-router-dom';
import { Ban, Banknote, CheckCircle2, MapPin, PackageX, Phone, Truck } from 'lucide-react';
import Badge from '../components/ui/Badge';
import Button from '../components/ui/Button';
import Input from '../components/ui/Input';
import { Loading } from '../components/ui/States';
import { confirmDriverJob, fetchDriverJob, type DriverJob } from '../data/driverJob';
import { useAsync } from '../hooks/useAsync';
import { DEFAULT_SETTINGS } from '../types';
import { digitsOnly, formatDateTh, formatDateTime, formatMoney, formatNumber, formatPhone, googleMapsUrl } from '../lib/format';

type CashChoice = 'full' | 'partial';

export default function DriverJobPage() {
  const { token = '' } = useParams();
  const { data: job, error, loading, setData } = useAsync(() => fetchDriverJob(token), [token]);
  const company = DEFAULT_SETTINGS.company;

  return (
    <div className="flex min-h-[100dvh] flex-col items-center bg-page px-4 py-8">
      <div className="w-full max-w-md">
        <div className="mb-5 text-center">
          <p className="text-sm font-semibold text-primary">{company.nameTh}</p>
          <p className="text-xs text-muted">ยืนยันการส่งของสำหรับคนขับ</p>
        </div>

        {loading && !job ? (
          <Loading label="กำลังโหลดงาน…" />
        ) : error || !job ? (
          <div className="rounded border border-red-200 bg-surface p-6 text-center">
            <PackageX size={44} className="mx-auto text-destructive" aria-hidden />
            <h1 className="mt-3 text-lg font-semibold">ไม่พบงานนี้</h1>
            <p className="mt-1 text-sm text-muted">ลิงก์อาจไม่ครบ กรุณาติดต่อร้าน {company.phone}</p>
          </div>
        ) : (
          <JobView token={token} job={job} onConfirmed={setData} />
        )}
      </div>
    </div>
  );
}

function JobView({ token, job, onConfirmed }: { token: string; job: DriverJob; onConfirmed: (j: DriverJob) => void }) {
  const collect = job.codAmount > 0;
  const reported = job.reportedAt != null;
  const [editing, setEditing] = useState(false);
  const showForm = !job.cancelled && (!reported || editing);

  return (
    <div className="flex flex-col gap-4">
      <section className="rounded border border-border bg-surface p-5">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h1 className="text-lg font-semibold tabular-nums">{job.orderNo}</h1>
            <p className="text-sm text-muted">
              {formatDateTh(job.orderDate)}
              {job.driver ? ` · ${job.driver}` : ''}
            </p>
          </div>
          {job.cancelled ? (
            <Badge tone="danger">ยกเลิก</Badge>
          ) : job.deliveryStatus === 'delivered' ? (
            <Badge tone="success">ส่งแล้ว</Badge>
          ) : (
            <Badge tone="warning">รอส่ง</Badge>
          )}
        </div>

        <dl className="mt-4 flex flex-col gap-3 border-t border-border pt-4 text-sm">
          <Row label="ลูกค้า">
            <span className="font-medium">{job.customer}</span>
            {job.phone ? (
              <a
                href={`tel:${digitsOnly(job.phone)}`}
                className="ml-2 inline-flex items-center gap-1 font-medium text-primary underline-offset-2 hover:underline"
              >
                <Phone size={14} aria-hidden />
                {formatPhone(job.phone)}
              </a>
            ) : null}
          </Row>
          <Row label="สินค้า">
            {job.items.map((it) => `${it.name} ${formatNumber(it.quantity)} ${it.unit}`).join(', ') || '-'}
          </Row>
          {job.truckSize ? (
            <Row label="รถ">
              <span className="inline-flex items-center gap-1">
                <Truck size={14} aria-hidden />
                {job.truckSize} คิว × {job.trips} เที่ยว
              </span>
            </Row>
          ) : null}
          {job.zone ? <Row label="ตำบล">{job.zone}</Row> : null}
          {job.address ? <Row label="ที่อยู่">{job.address}</Row> : null}
          {job.note ? <Row label="หมายเหตุ">{job.note}</Row> : null}
        </dl>

        {job.lat != null && job.lng != null ? (
          <a
            href={googleMapsUrl(job.lat, job.lng)}
            target="_blank"
            rel="noreferrer"
            className="mt-4 flex min-h-11 items-center justify-center gap-2 rounded border border-border bg-surface px-4 text-base font-medium text-ink transition-colors hover:bg-subtle"
          >
            <MapPin size={18} className="text-primary" aria-hidden />
            เปิดแผนที่นำทาง
          </a>
        ) : null}
      </section>

      {job.cancelled ? (
        <div className="flex items-center gap-3 rounded border border-red-200 bg-red-50 p-4 text-sm text-destructive">
          <Ban size={22} aria-hidden />
          <p>ออเดอร์นี้ถูกยกเลิกแล้ว ไม่ต้องส่งของ</p>
        </div>
      ) : (
        <CashBanner job={job} />
      )}

      {reported && !editing ? <ReportedCard job={job} onEdit={collect ? () => setEditing(true) : undefined} /> : null}

      {showForm ? (
        <ConfirmForm
          token={token}
          job={job}
          onDone={(j) => {
            setEditing(false);
            onConfirmed(j);
          }}
          onCancel={editing ? () => setEditing(false) : undefined}
        />
      ) : null}
    </div>
  );
}

function CashBanner({ job }: { job: DriverJob }) {
  if (job.codAmount > 0) {
    return (
      <div className="flex items-center gap-3 rounded border border-amber-300 bg-amber-50 p-4">
        <Banknote size={28} className="shrink-0 text-amber-700" aria-hidden />
        <div>
          <p className="text-sm text-amber-800">เก็บเงินสดปลายทาง</p>
          <p className="text-2xl font-bold tabular-nums text-amber-900">{formatMoney(job.codAmount)} บาท</p>
        </div>
      </div>
    );
  }
  return (
    <div className="rounded border border-border bg-subtle p-4 text-sm text-muted">
      {job.paid ? 'ลูกค้าชำระเงินแล้ว ไม่ต้องเก็บเงิน' : 'ไม่ต้องเก็บเงินจากลูกค้า (ร้านเรียกเก็บเอง)'}
    </div>
  );
}

function ReportedCard({ job, onEdit }: { job: DriverJob; onEdit?: () => void }) {
  const short = job.codAmount > 0 && job.cashReported != null && job.cashReported < job.codAmount;
  return (
    <section className="rounded border border-emerald-200 bg-emerald-50 p-5 text-center">
      <CheckCircle2 size={44} className="mx-auto text-success" aria-hidden />
      <h2 className="mt-2 text-lg font-semibold text-emerald-900">ยืนยันส่งสำเร็จแล้ว</h2>
      <p className="text-sm text-emerald-800">{formatDateTime(job.reportedAt ?? '')}</p>
      {job.codAmount > 0 && job.cashReported != null ? (
        <p className={`mt-3 text-base font-medium ${short ? 'text-amber-800' : 'text-emerald-900'}`}>
          แจ้งเก็บเงินสด {formatMoney(job.cashReported)} บาท
          {short ? ` (ขาด ${formatMoney(job.codAmount - job.cashReported)} บาท)` : ''}
        </p>
      ) : null}
      <p className="mt-2 text-sm text-emerald-800">
        {job.codAmount > 0 ? 'ร้านได้รับแจ้งแล้ว นำเงินส่งร้านตอนเคลียร์ค่ารถ' : 'ร้านได้รับแจ้งแล้ว ขอบคุณครับ'}
      </p>
      {onEdit ? (
        <button type="button" onClick={onEdit} className="mt-3 text-sm font-medium text-primary underline underline-offset-2">
          แก้ไขยอดเงินที่แจ้ง
        </button>
      ) : null}
    </section>
  );
}

function ConfirmForm({
  token,
  job,
  onDone,
  onCancel,
}: {
  token: string;
  job: DriverJob;
  onDone: (j: DriverJob) => void;
  onCancel?: () => void;
}) {
  const collect = job.codAmount > 0;
  const [choice, setChoice] = useState<CashChoice | null>(null);
  const [amount, setAmount] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const parsed = Number(amount.replace(/,/g, '').trim());
  const amountValid = amount.trim() !== '' && Number.isFinite(parsed) && parsed >= 0;
  const cash = !collect ? null : choice === 'full' ? job.codAmount : choice === 'partial' && amountValid ? parsed : null;
  const ready = !collect || cash != null;

  async function submit() {
    if (!ready || busy) return;
    setBusy(true);
    setError('');
    try {
      onDone(await confirmDriverJob(token, cash));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="flex flex-col gap-3 rounded border border-border bg-surface p-5">
      {collect ? (
        <fieldset className="flex flex-col gap-2">
          <legend className="mb-2 text-sm font-medium text-ink">เงินสดที่เก็บจากลูกค้า</legend>
          <ChoiceCard checked={choice === 'full'} onSelect={() => setChoice('full')}>
            ได้รับครบ {formatMoney(job.codAmount)} บาท
          </ChoiceCard>
          <ChoiceCard checked={choice === 'partial'} onSelect={() => setChoice('partial')}>
            ได้รับไม่ครบ / ยังไม่ได้รับ
          </ChoiceCard>
          {choice === 'partial' ? (
            <div className="flex flex-col gap-1 pt-1">
              <label htmlFor="driver-cash" className="text-sm text-muted">
                ยอดที่ได้รับจริง (บาท) ใส่ 0 ถ้ายังไม่ได้รับ
              </label>
              <Input
                id="driver-cash"
                inputMode="decimal"
                autoComplete="off"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                invalid={amount.trim() !== '' && !amountValid}
                placeholder="0"
                autoFocus
              />
            </div>
          ) : null}
        </fieldset>
      ) : null}

      {error ? (
        <p role="alert" className="text-sm text-destructive">
          {error}
        </p>
      ) : null}

      <Button variant="success" size="lg" onClick={submit} disabled={!ready || busy}>
        <CheckCircle2 size={20} aria-hidden />
        {busy ? 'กำลังบันทึก…' : job.deliveryStatus === 'delivered' && !onCancel ? 'ยืนยันยอดเงิน' : 'ยืนยันส่งสำเร็จ'}
      </Button>
      {onCancel ? (
        <Button variant="ghost" onClick={onCancel} disabled={busy}>
          ยกเลิกการแก้ไข
        </Button>
      ) : null}
    </section>
  );
}

function ChoiceCard({ checked, onSelect, children }: { checked: boolean; onSelect: () => void; children: ReactNode }) {
  return (
    <label
      className={[
        'flex min-h-12 cursor-pointer items-center gap-3 rounded border px-4 py-3 text-base transition-colors',
        checked ? 'border-primary bg-primary/5 font-medium text-ink' : 'border-border text-ink hover:bg-subtle',
      ].join(' ')}
    >
      <input type="radio" name="driver-cash-choice" checked={checked} onChange={onSelect} className="h-5 w-5 accent-primary" />
      {children}
    </label>
  );
}

function Row({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid grid-cols-[4.5rem_1fr] gap-3">
      <dt className="text-muted">{label}</dt>
      <dd className="min-w-0 break-words">{children}</dd>
    </div>
  );
}
