import { useParams } from 'react-router-dom';
import { Ban, ShieldAlert, ShieldCheck } from 'lucide-react';
import Badge from '../components/ui/Badge';
import { Loading } from '../components/ui/States';
import { verifyDocument } from '../data/statements';
import { useAsync } from '../hooks/useAsync';
import { DEFAULT_SETTINGS } from '../types';
import { formatDateTh, formatMoney } from '../lib/format';

export default function VerifyPage() {
  const { token = '' } = useParams();
  const { data, error, loading } = useAsync(() => verifyDocument(token), [token]);
  const company = DEFAULT_SETTINGS.company;

  return (
    <div className="flex min-h-[100dvh] flex-col items-center bg-page px-4 py-10">
      <div className="w-full max-w-md">
        <div className="mb-6 text-center">
          <p className="text-sm font-semibold text-primary">{company.nameTh}</p>
          <p className="text-xs text-muted">ระบบตรวจสอบความถูกต้องของเอกสาร</p>
        </div>

        {loading ? (
          <Loading label="กำลังตรวจสอบ…" />
        ) : error || !data ? (
          <div className="rounded border border-red-200 bg-surface p-6 text-center">
            <ShieldAlert size={44} className="mx-auto text-destructive" aria-hidden />
            <h1 className="mt-3 text-lg font-semibold">ไม่พบเอกสารนี้ในระบบ</h1>
            <p className="mt-1 text-sm text-muted">
              เอกสารอาจถูกปลอมแปลง หรือ QR เสียหาย กรุณาติดต่อ {company.phone}
            </p>
          </div>
        ) : (
          <div className="rounded border border-border bg-surface p-6">
            <div className="text-center">
              {data.cancelled ? (
                <Ban size={44} className="mx-auto text-destructive" aria-hidden />
              ) : (
                <ShieldCheck size={44} className="mx-auto text-success" aria-hidden />
              )}
              <h1 className="mt-3 text-lg font-semibold">
                {data.cancelled ? 'เอกสารนี้ถูกยกเลิกแล้ว' : 'เอกสารถูกต้อง ออกโดยระบบของร้าน'}
              </h1>
            </div>
            <dl className="mt-5 flex flex-col gap-2 border-t border-border pt-4 text-sm">
              <Row label="ประเภท" value={data.kind === 'statement' ? 'ใบวางบิล / ใบแจ้งยอด' : 'ใบส่งของ / ใบเสร็จรับเงิน'} />
              <Row label="เลขที่" value={data.docNo} />
              {data.receiptNo ? <Row label="เลขที่ใบเสร็จ" value={data.receiptNo} /> : null}
              <Row label="วันที่" value={formatDateTh(data.date)} />
              <Row label="ลูกค้า" value={data.customer} />
              <Row label="ยอดสุทธิ" value={`${formatMoney(Number(data.total))} บาท`} />
              <div className="flex items-center justify-between gap-3">
                <dt className="text-muted">สถานะ</dt>
                <dd>
                  {data.cancelled ? (
                    <Badge tone="danger">ยกเลิก</Badge>
                  ) : data.paymentStatus === 'paid' ? (
                    <Badge tone="success">ชำระแล้ว</Badge>
                  ) : data.paymentStatus === 'credit' ? (
                    <Badge tone="info">ค้างชำระ (เครดิต)</Badge>
                  ) : (
                    <Badge tone="warning">ยังไม่ชำระ</Badge>
                  )}
                </dd>
              </div>
            </dl>
            <p className="mt-5 text-center text-xs text-muted">
              ตรวจสอบตัวเลขบนเอกสารให้ตรงกับหน้านี้ หากไม่ตรงอาจเป็นเอกสารปลอม
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-3">
      <dt className="text-muted">{label}</dt>
      <dd className="text-right font-medium tabular-nums">{value}</dd>
    </div>
  );
}
