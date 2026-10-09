import { forwardRef, type ReactNode } from 'react';
import { bahtText } from '../../calc/bahtText';
import { DOC_TITLE, formatDateShort, formatDateTh, formatDateTime, formatMoney, formatNumber, formatPhone } from '../../lib/format';
import { promptPayPayload } from '../../lib/promptpay';
import { PAYMENT_METHOD_LABEL, type CompanySettings, type PaymentSettings } from '../../types';
import logoUrl from '../../assets/pirasit-logo.png';
import BillSecurity from './BillSecurity';
import BillStamp from './BillStamp';
import QrImage from './QrImage';
import { PAYMENT_CHOICES, type BillData } from './billData';

interface Props {
  bill: BillData;
  copy: 'original' | 'copy';
  company: CompanySettings;
  payment: PaymentSettings;
  size?: BillSize;
}

export type BillSize = 'a4' | 'a5';

/** a5 is laid out narrower than A4 (same 1:√2 ratio) so it stays legible when fitted onto half an A4 sheet. */
const LAYOUT = {
  a4: {
    sheet: 'bill-sheet-a4 mx-auto shadow-lg',
    style: { width: '210mm', minHeight: '297mm', padding: '13mm 14mm 11mm' },
    headerGap: 'gap-6',
    logo: 'h-[76px]',
    company: 'text-[17px]',
    companyEn: 'text-[9.5px] tracking-[0.1em]',
    title: 'text-[22px]',
    payQr: 72,
    infoCols: 'grid-cols-[1fr_15.5rem]',
    totalsCols: 'grid-cols-[1fr_16rem]',
    padRows: 5,
    signers: 'mt-6 gap-8',
    stampSize: 140,
    stampTop: ['-top-24', '-top-14'],
    signLine: 'mt-10 w-52',
    footer: 'mt-5',
  },
  a5: {
    sheet: '',
    style: { width: '160mm', minHeight: '226.3mm', padding: '9mm 9mm 7mm' },
    headerGap: 'gap-4',
    logo: 'h-[62px]',
    company: 'text-[15px]',
    companyEn: 'text-[8.5px] tracking-[0.03em]',
    title: 'text-[19px]',
    payQr: 64,
    infoCols: 'grid-cols-[1fr_13rem]',
    totalsCols: 'grid-cols-[1fr_14rem]',
    padRows: 3,
    signers: 'mt-4 gap-6',
    stampSize: 112,
    stampTop: ['-top-20', '-top-12'],
    signLine: 'mt-8 w-44',
    footer: 'mt-4',
  },
} as const;

const SIGNERS: Record<BillData['kind'], [string, string]> = {
  delivery: ['ผู้รับสินค้า', 'ผู้ส่งสินค้า'],
  receipt: ['ผู้จ่ายเงิน', 'ผู้รับเงิน'],
  statement: ['ผู้รับวางบิล', 'ผู้วางบิล'],
};

const BillDocument = forwardRef<HTMLDivElement, Props>(function BillDocument({ bill: b, copy, company, payment, size = 'a5' }, ref) {
  const L = LAYOUT[size];
  const title = DOC_TITLE[b.kind];
  const statement = b.kind === 'statement';
  const partlyPaid = !b.paid && (b.paidAmount ?? 0) > 0;
  const due = partlyPaid ? Math.max(0, b.total - (b.paidAmount ?? 0)) : b.total;
  const showPromptPay =
    !b.paid && !b.cancelled && due > 0 && (statement || b.paymentMethod !== 'credit') && !!payment.promptPayId;
  const ppPayload = showPromptPay ? promptPayPayload(payment.promptPayId, due) : null;
  const showPayChannel = !b.paid && !b.cancelled && !!(payment.qrPayload || payment.bankAccountNo);
  const [customerSigner, companySigner] = SIGNERS[b.kind];
  const copyLabel = copy === 'original' ? 'ต้นฉบับ / ORIGINAL' : 'สำเนา / COPY';

  return (
    <div
      ref={ref}
      className={`bill-sheet bill-protect relative flex flex-col overflow-hidden bg-white text-[12.5px] leading-snug text-slate-900 ${L.sheet}`}
      style={L.style}
      onContextMenu={(e) => e.preventDefault()}
      onCopy={(e) => e.preventDefault()}
      onDragStart={(e) => e.preventDefault()}
    >
      <BillSecurity docNo={b.docNo} label={copy === 'original' ? 'ORIGINAL' : 'COPY'} />

      <div className="relative flex flex-1 flex-col">
        <header>
          <div className={`flex items-stretch justify-between ${L.headerGap}`}>
            <div className="flex min-w-0 items-center gap-3">
              <img src={logoUrl} alt="" draggable={false} className={`${L.logo} w-auto shrink-0`} />
              <div className="min-w-0 border-l-2 border-[#1e3a5f]/20 pl-3">
                <p className={`${L.company} font-bold leading-tight text-[#1e3a5f]`}>{company.nameTh}</p>
                <p className={`mt-0.5 font-semibold uppercase text-slate-500 ${L.companyEn}`}>{company.nameEn}</p>
                <p className="mt-1.5 text-[10.5px] leading-snug text-slate-700">{company.address}</p>
                <p className="text-[10.5px] leading-snug text-slate-700">
                  <span className="text-slate-500">เลขประจำตัวผู้เสียภาษี</span> {company.taxId}
                  <span className="mx-1.5 text-slate-300">|</span>
                  <span className="text-slate-500">โทร</span> {company.phone}
                </p>
              </div>
            </div>
            <div className="flex shrink-0 flex-col items-end justify-between gap-2">
              <div className="rounded-md bg-[#1e3a5f] px-4 py-2 text-right text-white">
                <p className={`${L.title} font-bold leading-none`}>{title.th}</p>
                <p className="mt-1.5 text-[9.5px] font-semibold tracking-[0.25em] text-white/75">{title.en}</p>
              </div>
              {showPayChannel ? (
                <div className="flex items-center gap-2 rounded-md border border-slate-300 px-2 py-1.5">
                  {payment.qrPayload ? <QrImage value={payment.qrPayload} size={L.payQr} label="QR รับเงิน" /> : null}
                  <div className="text-[10px] leading-snug text-slate-700">
                    <p className="font-semibold text-[#1e3a5f]">ช่องทางรับเงิน</p>
                    {payment.bankName ? <p>{payment.bankName}</p> : null}
                    {payment.bankAccountNo ? (
                      <p className="text-[11px] font-semibold tabular-nums text-slate-900">{payment.bankAccountNo}</p>
                    ) : null}
                    {payment.bankAccountName ? <p>{payment.bankAccountName}</p> : null}
                    {payment.qrPayload ? <p className="text-slate-500">สแกน QR เพื่อชำระ</p> : null}
                  </div>
                </div>
              ) : null}
              <span
                className={[
                  'rounded-full border px-2.5 py-0.5 text-[10px] font-semibold',
                  copy === 'original' ? 'border-[#1e3a5f] text-[#1e3a5f]' : 'border-slate-400 text-slate-500',
                ].join(' ')}
              >
                {copyLabel}
              </span>
            </div>
          </div>
          <div className="mt-3 h-[3px] rounded-full bg-[#1e3a5f]" />
          <div className="mt-[2px] h-px bg-[#1e3a5f]/35" />
        </header>

        <section className={`mt-3 grid ${L.infoCols} gap-3`}>
          <div className="rounded-md border border-slate-300 px-3 py-2">
            <p className="text-[10.5px] font-semibold text-slate-500">ลูกค้า / CUSTOMER</p>
            <p className="text-[14px] font-semibold">{b.customer.name}</p>
            {b.customer.address ? <p className="text-slate-700">{b.customer.address}</p> : null}
            <p className="text-slate-700">
              {b.customer.phone ? `โทร ${formatPhone(b.customer.phone)}` : ''}
              {b.customer.taxId ? `${b.customer.phone ? ' · ' : ''}เลขผู้เสียภาษี ${b.customer.taxId}` : ''}
            </p>
          </div>
          <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 rounded-md border border-slate-300 px-3 py-2">
            <dt className="text-slate-500">เลขที่</dt>
            <dd className="text-right font-semibold tabular-nums">{b.docNo}</dd>
            <dt className="text-slate-500">วันที่</dt>
            <dd className="text-right tabular-nums">{formatDateTh(b.date)}</dd>
            {b.period ? (
              <>
                <dt className="text-slate-500">รอบบิล</dt>
                <dd className="text-right tabular-nums">
                  {formatDateShort(b.period.from)} – {formatDateShort(b.period.to)}
                </dd>
              </>
            ) : null}
            {b.refs.map((r) => (
              <Pair key={r.label} label={r.label} value={r.value} />
            ))}
            {b.issuedBy ? <Pair label="ผู้ออกเอกสาร" value={b.issuedBy} /> : null}
          </dl>
        </section>

        {b.delivery ? (
          <section className="mt-2 flex flex-wrap gap-x-5 gap-y-0.5 rounded-md bg-slate-50 px-3 py-1.5 text-[11.5px]">
            <span>
              <b>จัดส่ง</b> {b.delivery.zone ? `ต.${b.delivery.zone} ` : ''}
              {b.delivery.address}
            </span>
            {b.delivery.truck ? <span>{b.delivery.truck}</span> : null}
            {b.delivery.driver ? <span>คนขับ: {b.delivery.driver}</span> : null}
          </section>
        ) : !statement ? (
          <section className="mt-2 rounded-md bg-slate-50 px-3 py-1.5 text-[11.5px]">
            <b>รับสินค้า</b> ลูกค้ามารับเองที่ท่าทราย
          </section>
        ) : null}

        <table className="mt-3 w-full border-collapse text-[12px]">
          <thead>
            <tr className="bg-[#1e3a5f] text-white">
              <Th className="w-10 text-center">ลำดับ</Th>
              {statement ? <Th className="w-24">วันที่</Th> : null}
              <Th>{statement ? 'เลขที่เอกสาร / รายละเอียด' : 'รายการ'}</Th>
              {!statement ? (
                <>
                  <Th className="w-16 text-right">จำนวน</Th>
                  <Th className="w-14 text-center">หน่วย</Th>
                  <Th className="w-24 text-right">ราคา/หน่วย</Th>
                </>
              ) : null}
              <Th className="w-28 text-right">จำนวนเงิน</Th>
            </tr>
          </thead>
          <tbody>
            {b.lines.map((l, i) => (
              <tr key={i} className="border-b border-slate-200 align-top">
                <Td className="text-center tabular-nums">{i + 1}</Td>
                {statement ? <Td className="tabular-nums">{l.date ? formatDateTh(l.date) : ''}</Td> : null}
                <Td>
                  <span className="font-medium">{l.description}</span>
                  {l.detail ? <span className="block text-[11px] text-slate-500">{l.detail}</span> : null}
                </Td>
                {!statement ? (
                  <>
                    <Td className="text-right tabular-nums">{l.quantity != null ? formatNumber(l.quantity) : ''}</Td>
                    <Td className="text-center">{l.unit ?? ''}</Td>
                    <Td className="text-right tabular-nums">{l.unitPrice != null ? formatMoney(l.unitPrice) : ''}</Td>
                  </>
                ) : null}
                <Td className="text-right tabular-nums">{formatMoney(l.amount)}</Td>
              </tr>
            ))}
            {Array.from({ length: Math.max(0, L.padRows + (statement ? 1 : 0) - b.lines.length) }).map((_, i) => (
              <tr key={`pad-${i}`} className="border-b border-slate-100">
                <td className="h-7" colSpan={statement ? 4 : 6} />
              </tr>
            ))}
          </tbody>
        </table>

        <section className={`mt-3 grid ${L.totalsCols} gap-4`}>
          <div className="flex flex-col gap-2">
            <div className="rounded-md bg-slate-100 px-3 py-2 text-center text-[12.5px] font-semibold">
              ({bahtText(b.total)})
            </div>

            {statement ? (
              <div className="text-[11.5px] text-slate-700">
                <p className="font-semibold text-slate-900">การชำระเงิน</p>
                {b.paid ? (
                  <p>
                    ชำระแล้ว{b.paymentMethod ? ` (${PAYMENT_METHOD_LABEL[b.paymentMethod]})` : ''}
                    {b.paidAt ? ` เมื่อ ${formatDateTh(b.paidAt)}` : ''}
                  </p>
                ) : partlyPaid ? (
                  <p>
                    รับชำระแล้ว {formatMoney(b.paidAmount ?? 0)} บาท · กรุณาชำระส่วนที่เหลือ{' '}
                    <b className="text-amber-700">{formatMoney(due)} บาท</b>
                    {payment.bankText ? ` · ${payment.bankText}` : ''}
                  </p>
                ) : (
                  <p>กรุณาชำระตามยอดข้างต้น{payment.bankText ? ` · ${payment.bankText}` : ''}</p>
                )}
              </div>
            ) : (
              <div className="text-[11.5px]">
                <p className="mb-1 font-semibold">{b.kind === 'receipt' ? 'ได้รับเงินถูกต้องแล้ว โดย' : 'การชำระเงิน'}</p>
                <div className="flex flex-wrap gap-x-4 gap-y-1">
                  {PAYMENT_CHOICES.map((m) => (
                    <span key={m} className="inline-flex items-center gap-1.5">
                      <span className="inline-flex h-3.5 w-3.5 items-center justify-center border border-slate-500 text-[10px] font-bold leading-none">
                        {b.paymentMethod === m ? '✓' : ''}
                      </span>
                      {PAYMENT_METHOD_LABEL[m]}
                    </span>
                  ))}
                </div>
                <p className="mt-1 text-slate-600">
                  สถานะ:{' '}
                  {b.paid ? (
                    <b className="text-emerald-700">ชำระแล้ว{b.paidAt ? ` ${formatDateTh(b.paidAt)}` : ''}</b>
                  ) : b.paymentMethod === 'credit' ? (
                    <b>เครดิต — รวมเคลียร์ในใบวางบิลรายเดือน</b>
                  ) : (
                    <b className="text-amber-700">ยังไม่ชำระ</b>
                  )}
                </p>
                {!b.paid && payment.bankText && b.paymentMethod !== 'credit' ? (
                  <p className="text-slate-600">{payment.bankText}</p>
                ) : null}
              </div>
            )}

            {ppPayload ? (
              <div className="flex items-center gap-3 rounded-md border border-slate-300 px-3 py-2">
                <QrImage value={ppPayload} size={76} label="QR พร้อมเพย์" />
                <div className="text-[11px] text-slate-700">
                  <p className="font-semibold text-slate-900">สแกนจ่ายด้วยพร้อมเพย์</p>
                  <p>ยอด {formatMoney(due)} บาท</p>
                  <p>พร้อมเพย์ {payment.promptPayId}</p>
                </div>
              </div>
            ) : null}

            {b.note ? <p className="text-[11.5px] text-slate-700">หมายเหตุ: {b.note}</p> : null}
          </div>

          <dl className="flex flex-col gap-1 text-[12.5px]">
            {!statement ? (
              <>
                <TotalRow label="รวมเงิน" value={formatMoney(b.gross)} />
                {b.discountAmount ? <TotalRow label={b.discountLabel ?? 'ส่วนลด'} value={`-${formatMoney(b.discountAmount)}`} /> : null}
              </>
            ) : (
              <TotalRow label={`จำนวน ${b.lines.length} รายการ`} value="" />
            )}
            <div className="mt-1 flex items-center justify-between rounded-md bg-[#1e3a5f] px-3 py-2 text-white">
              <dt className="font-semibold">ยอดสุทธิ</dt>
              <dd className="text-[16px] font-bold tabular-nums">{formatMoney(b.total)}</dd>
            </div>
            {partlyPaid ? (
              <>
                <TotalRow label="หัก รับชำระแล้ว" value={`-${formatMoney(b.paidAmount ?? 0)}`} />
                <div className="flex items-center justify-between rounded-md border-2 border-amber-600 px-3 py-1.5">
                  <dt className="font-semibold text-amber-800">คงค้างชำระ</dt>
                  <dd className="text-[15px] font-bold tabular-nums text-amber-800">{formatMoney(due)}</dd>
                </div>
              </>
            ) : null}
            <p className="mt-1 text-right text-[10.5px] text-slate-500">ราคานี้ไม่มีภาษีมูลค่าเพิ่ม</p>
          </dl>
        </section>

        <div className="flex-1" />

        <section className={`grid grid-cols-2 ${L.signers}`}>
          <Signature title={customerSigner} line={L.signLine} />
          <div className="relative">
            <Signature title={companySigner} org={`ในนาม ${company.nameTh}`} line={L.signLine} />
            <div className={`pointer-events-none absolute left-1/2 -translate-x-1/2 ${L.stampTop[b.paid ? 0 : 1]}`}>
              <BillStamp size={L.stampSize} paidDate={b.paid ? formatDateTh(b.paidAt || b.date) : undefined} />
            </div>
          </div>
        </section>

        <footer className={`${L.footer} flex items-center justify-between gap-4 border-t border-slate-300 pt-2`}>
          <p className="text-[10px] text-slate-600">พิมพ์เมื่อ {formatDateTime(new Date())}</p>
          <p className="shrink-0 rounded border border-slate-400 px-2 py-1 text-[10.5px] font-semibold text-slate-700">
            เอกสารนี้ไม่ใช่ใบกำกับภาษี
          </p>
        </footer>
      </div>

      {b.cancelled ? (
        <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
          <span className="-rotate-[28deg] rounded-xl border-[6px] border-red-600 px-8 py-2 text-[64px] font-extrabold text-red-600 opacity-60">
            ยกเลิก / VOID
          </span>
        </div>
      ) : null}
      {b.demo ? (
        <div className="pointer-events-none absolute inset-0 flex items-center justify-center" data-tour="bill-demo">
          <span className="-rotate-[28deg] rounded-xl border-[5px] border-violet-500 px-6 py-2 text-center text-[40px] font-extrabold leading-tight text-violet-500 opacity-45">
            ตัวอย่าง
            <span className="block text-[18px] font-bold">ไม่ใช่เอกสารจริง · สาธิตการใช้งาน</span>
          </span>
        </div>
      ) : null}
    </div>
  );
});

export default BillDocument;

function Pair({ label, value }: { label: string; value: string }) {
  return (
    <>
      <dt className="text-slate-500">{label}</dt>
      <dd className="text-right tabular-nums">{value}</dd>
    </>
  );
}

function Th({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <th className={`px-2 py-1.5 text-left text-[11.5px] font-semibold ${className}`}>{children}</th>;
}

function Td({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <td className={`px-2 py-1.5 ${className}`}>{children}</td>;
}

function TotalRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-3 px-1">
      <dt className="text-slate-600">{label}</dt>
      <dd className="tabular-nums">{value}</dd>
    </div>
  );
}

function Signature({ title, org, line }: { title: string; org?: string; line: string }) {
  return (
    <div className="text-center text-[11.5px]">
      <div className={`mx-auto ${line} border-b border-dotted border-slate-500`} />
      <p className="mt-1">( ........................................ )</p>
      <p className="font-semibold">{title}</p>
      {org ? <p className="text-[10px] text-slate-500">{org}</p> : null}
      <p className="mt-1 text-slate-500">วันที่ ........ / ........ / ........</p>
    </div>
  );
}
