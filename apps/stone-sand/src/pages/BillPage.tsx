import { useMemo, useRef, useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { ArrowLeft, CheckCircle2, Download, Plus, Printer } from 'lucide-react';
import BillDocument from '../components/bill/BillDocument';
import BillSpread from '../components/bill/BillSpread';
import ScaledSheet from '../components/bill/ScaledSheet';
import { billFromOrder, billFromStatement, type BillData } from '../components/bill/billData';
import Button from '../components/ui/Button';
import { ErrorBox, Loading } from '../components/ui/States';
import { useCatalog } from '../context/CatalogProvider';
import { getOrder, getOrdersByIds } from '../data/orders';
import { getStatement } from '../data/statements';
import { useAsync } from '../hooks/useAsync';
import { formatMoney } from '../lib/format';

type CopyMode = 'original' | 'both';

export default function BillPage({ mode }: { mode: 'order' | 'statement' }) {
  const { id = '' } = useParams();
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const created = params.get('created') === '1';
  const { settings, zoneById, driverById } = useCatalog();
  const [docKind, setDocKind] = useState<'delivery' | 'receipt' | null>(null);
  const [copies, setCopies] = useState<CopyMode>('both');
  const [saving, setSaving] = useState(false);
  const sheetRef = useRef<HTMLDivElement>(null);

  const { data, error, loading } = useAsync(async () => {
    if (mode === 'order') {
      const order = await getOrder(id);
      return order ? { order, statement: null, orders: [] } : null;
    }
    const statement = await getStatement(id);
    if (!statement) return null;
    return { order: null, statement, orders: await getOrdersByIds(statement.orderIds) };
  }, [mode, id]);

  const order = data?.order ?? null;
  const kind = docKind ?? (order?.paymentStatus === 'paid' && order.receiptNo ? 'receipt' : 'delivery');

  const bill: BillData | null = useMemo(() => {
    if (!data) return null;
    if (data.order) return billFromOrder(data.order, kind, zoneById(data.order.zoneId), driverById(data.order.driverId));
    if (data.statement) return billFromStatement(data.statement, data.orders);
    return null;
  }, [data, kind, zoneById, driverById]);

  if (loading && !data) return <Loading />;
  if (error) return <div className="p-4"><ErrorBox message={error} /></div>;
  if (!bill) return <div className="p-4"><ErrorBox message="ไม่พบเอกสาร" /></div>;

  const backTo = order ? `/orders/${order.id}` : '/statements';

  const savePng = async () => {
    if (!sheetRef.current) return;
    setSaving(true);
    try {
      const { default: html2canvas } = await import('html2canvas');
      const canvas = await html2canvas(sheetRef.current, {
        scale: 2,
        backgroundColor: '#ffffff',
        useCORS: true,
        onclone: (doc) => {
          doc.querySelectorAll<HTMLElement>('.bill-scale, .bill-fit').forEach((el) => {
            el.style.transform = 'none';
          });
          doc.querySelectorAll<HTMLElement>('.bill-half').forEach((el) => {
            el.style.overflow = 'visible';
          });
        },
      });
      const link = document.createElement('a');
      link.download = `${bill.docNo}.png`;
      link.href = canvas.toDataURL('image/png');
      link.click();
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="min-h-[100dvh] bg-slate-100 print:min-h-0 print:bg-white">
      <header className="no-print sticky top-0 z-30 border-b border-border bg-surface/95 pt-safe-top backdrop-blur">
        <div className="mx-auto flex max-w-4xl flex-wrap items-center gap-2 px-3 py-2">
          <Link
            to={backTo}
            aria-label="กลับ"
            className="inline-flex min-h-11 min-w-11 items-center justify-center rounded text-muted hover:bg-subtle hover:text-ink"
          >
            <ArrowLeft size={20} aria-hidden />
          </Link>
          <div className="min-w-0 flex-1">
            <p className="truncate font-semibold tabular-nums">{bill.docNo}</p>
            <p className="truncate text-xs text-muted">
              {bill.customer.name} · {formatMoney(bill.total)} บาท
            </p>
          </div>
          <Button variant="secondary" onClick={savePng} disabled={saving} aria-label="บันทึกเป็นรูป">
            <Download size={18} aria-hidden /> <span className="hidden sm:inline">{saving ? 'กำลังบันทึก…' : 'บันทึกรูป'}</span>
          </Button>
          <Button onClick={() => window.print()}>
            <Printer size={18} aria-hidden /> พิมพ์
          </Button>
        </div>
        <div className="mx-auto flex max-w-4xl flex-wrap items-center gap-2 px-3 pb-2">
          {order ? (
            <Segmented
              label="ประเภทเอกสาร"
              value={kind}
              onChange={(v) => setDocKind(v as 'delivery' | 'receipt')}
              options={[
                { value: 'delivery', label: 'ใบส่งของ' },
                ...(order.receiptNo ? [{ value: 'receipt', label: 'ใบเสร็จรับเงิน' }] : []),
              ]}
            />
          ) : null}
          <Segmented
            label="จำนวนชุดที่พิมพ์"
            value={copies}
            onChange={(v) => setCopies(v as CopyMode)}
            options={[
              { value: 'both', label: 'ต้นฉบับ + สำเนา' },
              { value: 'original', label: 'ต้นฉบับอย่างเดียว' },
            ]}
          />
        </div>
      </header>

      {created ? (
        <div className="no-print mx-auto mt-3 max-w-4xl px-3">
          <div className="flex flex-wrap items-center gap-3 rounded border border-emerald-200 bg-success-soft px-4 py-3 text-sm text-emerald-800">
            <CheckCircle2 size={18} aria-hidden />
            <span className="flex-1">บันทึกออเดอร์เรียบร้อย พิมพ์บิลหรือบันทึกรูปส่งให้ลูกค้าได้เลย</span>
            <Button variant="secondary" onClick={() => navigate('/new', { replace: true })}>
              <Plus size={16} aria-hidden /> ออเดอร์ถัดไป
            </Button>
          </div>
        </div>
      ) : null}

      <main className="bill-print-root mx-auto max-w-6xl p-3 sm:p-6">
        <p className="no-print mb-2 text-center text-xs text-muted">กระดาษ A4 แนวนอน · ต้นฉบับซ้าย สำเนาขวา (ขนาด A5) ตัดตามเส้นประ</p>
        <ScaledSheet>
          <BillSpread
            left={<BillDocument ref={sheetRef} bill={bill} copy="original" company={settings.company} payment={settings.payment} />}
            right={
              copies === 'both' ? (
                <BillDocument bill={bill} copy="copy" company={settings.company} payment={settings.payment} />
              ) : null
            }
          />
        </ScaledSheet>
      </main>
    </div>
  );
}

function Segmented({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
}) {
  return (
    <div className="flex rounded border border-border bg-surface p-0.5" role="radiogroup" aria-label={label}>
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          role="radio"
          aria-checked={value === o.value}
          onClick={() => onChange(o.value)}
          className={[
            'min-h-10 rounded px-3 text-sm font-medium transition-colors cursor-pointer',
            value === o.value ? 'bg-primary text-primary-foreground' : 'text-muted hover:text-ink',
          ].join(' ')}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}
