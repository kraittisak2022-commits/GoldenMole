import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import {
  AlertTriangle,
  ArrowRight,
  Check,
  Circle,
  CircleDot,
  FileText,
} from "lucide-react";
import DemoBadge from "../../components/DemoBadge";
import SourceBadge from "../../components/SourceBadge";
import Badge from "../../components/ui/Badge";
import {
  BILL_STAGE,
  netMargin,
  stageAction,
  type BillStep,
  type BillSummary,
  type BillTotals,
} from "../../lib/billSummary";
import { formatDateShort, formatMoney } from "../../lib/format";
import type { Order } from "../../types";

export interface BillRowData {
  order: Order;
  summary: BillSummary;
  driverName: string;
}

/** Desktop columns: bill · ยอดบิล · ค่ารถ · คงเหลือ · actions. Shared by header, rows and footer. */
const COLS = "lg:grid-cols-[minmax(0,1fr)_8.5rem_8.5rem_9rem_9.5rem]";

function Steps({
  steps,
  cancelled,
}: {
  steps: BillStep[];
  cancelled: boolean;
}) {
  const shown = steps.filter((s) => s.state !== "skip");
  return (
    <ol
      className="flex flex-wrap items-center gap-x-1.5 gap-y-1 text-xs"
      aria-label="ขั้นตอน"
    >
      {shown.map((step, i) => {
        const done = step.state === "done" && !cancelled;
        const current = step.state === "current" && !cancelled;
        const status = done
          ? "เสร็จ"
          : current
            ? "ขั้นตอนปัจจุบัน"
            : "ยังไม่ถึง";
        return (
          <li key={step.key} className="flex items-center gap-1.5">
            {i > 0 ? <span className="h-px w-3 bg-border" aria-hidden /> : null}
            <span
              className={[
                "inline-flex items-center gap-1",
                done
                  ? "text-ink"
                  : current
                    ? "font-semibold text-primary"
                    : "text-muted",
              ].join(" ")}
            >
              {done ? (
                <span
                  className="grid h-4 w-4 place-items-center rounded-full bg-success text-white"
                  aria-hidden
                >
                  <Check size={11} strokeWidth={3} />
                </span>
              ) : current ? (
                <CircleDot size={16} aria-hidden />
              ) : (
                <Circle size={16} className="text-muted/50" aria-hidden />
              )}
              {step.label}
              <span className="sr-only">: {status}</span>
            </span>
          </li>
        );
      })}
    </ol>
  );
}

function Cell({
  label,
  children,
  sub,
}: {
  label: string;
  children: ReactNode;
  sub?: ReactNode;
}) {
  return (
    <div className="min-w-0 lg:text-right">
      <dt className="text-xs text-muted lg:sr-only">{label}</dt>
      <dd className="whitespace-nowrap tabular-nums">{children}</dd>
      {sub ? <dd className="mt-0.5 text-xs text-muted">{sub}</dd> : null}
    </div>
  );
}

function Figures({ order: o, summary: s }: BillRowData) {
  const cancelled = s.stage === "cancelled";
  const delivery = o.fulfillment === "delivery";
  const loss = delivery && s.deliveryMargin < 0 && !cancelled;
  const margin = netMargin(s.net, s.revenue);

  return (
    <dl className="grid grid-cols-3 gap-3 rounded bg-subtle/70 px-3 py-2.5 text-sm lg:contents">
      <Cell
        label="ยอดบิล"
        sub={
          cancelled ? null : s.receivable > 0 ? (
            <span className="font-medium text-warning">
              ค้างรับ {formatMoney(s.receivable)}
            </span>
          ) : (
            <span className="text-success">รับเงินครบ</span>
          )
        }
      >
        <span className="font-medium">{formatMoney(s.revenue)}</span>
      </Cell>

      <Cell
        label="ค่ารถคนขับ"
        sub={delivery ? `เก็บค่าส่ง ${formatMoney(s.deliveryFee)}` : "มารับเอง"}
      >
        {!delivery || (!s.driverCost && !s.driverCostEstimated) ? (
          <span className="text-muted">—</span>
        ) : (
          <span
            className={s.driverCostEstimated ? "text-muted" : ""}
            title={
              s.driverCostEstimated
                ? "ประมาณตามเรทตำบล ยังไม่จ่ายคนขับ"
                : "จ่ายคนขับแล้ว"
            }
          >
            {s.driverCostEstimated ? "≈ " : ""}−{formatMoney(s.driverCost)}
            <span className="sr-only">
              {s.driverCostEstimated ? " (ประมาณ ยังไม่จ่าย)" : " (จ่ายแล้ว)"}
            </span>
          </span>
        )}
      </Cell>

      <Cell
        label="คงเหลือเข้าร้าน"
        sub={
          loss ? (
            <span className="inline-flex items-center gap-1 text-warning lg:justify-end">
              <AlertTriangle size={12} aria-hidden /> ค่าส่งขาด{" "}
              {formatMoney(-s.deliveryMargin)}
            </span>
          ) : margin != null && !cancelled ? (
            `${margin}% ของยอดบิล`
          ) : null
        }
      >
        <b
          className={[
            "font-semibold",
            cancelled ? "text-muted" : "text-success",
          ].join(" ")}
        >
          {formatMoney(s.net)}
        </b>
      </Cell>
    </dl>
  );
}

function BillRow(row: BillRowData) {
  const { order: o, summary: s, driverName } = row;
  const meta = BILL_STAGE[s.stage];
  const action = stageAction(o, s.stage);
  const cancelled = s.stage === "cancelled";
  const fulfillment =
    o.fulfillment === "delivery"
      ? `ส่ง ${o.trips} เที่ยว${driverName ? ` · ${driverName}` : ""}`
      : "มารับเอง";

  return (
    <li
      className={[
        "grid gap-3 px-4 py-4 transition-colors hover:bg-subtle/40 sm:px-5 lg:items-start lg:gap-x-4",
        COLS,
        cancelled ? "opacity-60" : "",
      ].join(" ")}
    >
      <div className="flex min-w-0 flex-col gap-1.5">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
          <Link
            to={`/orders/${o.id}`}
            className={[
              "max-w-full truncate font-semibold text-ink hover:text-primary hover:underline",
              cancelled ? "line-through" : "",
            ].join(" ")}
          >
            {o.customer.name}
          </Link>
          <Badge tone={meta.tone}>{meta.label}</Badge>
        </div>
        <p className="flex flex-wrap items-center gap-x-1.5 gap-y-1 text-xs text-muted tabular-nums">
          <span className="font-medium text-ink/80">{o.orderNo}</span>
          <span aria-hidden>·</span>
          <span>{formatDateShort(o.orderDate)}</span>
          <SourceBadge source={o.source} />
          {o.demo ? <DemoBadge /> : null}
          <span className="min-w-0 truncate">{fulfillment}</span>
        </p>
        <div className="mt-1">
          <Steps steps={s.steps} cancelled={cancelled} />
        </div>
      </div>

      <Figures {...row} />

      <div className="flex flex-wrap items-center gap-2 lg:flex-col lg:items-end">
        {action ? (
          <Link
            to={action.to}
            className="inline-flex min-h-9 items-center gap-1 rounded border border-border bg-surface px-3 text-sm font-medium text-primary hover:border-primary/40 hover:bg-primary-soft"
          >
            {action.label} <ArrowRight size={14} aria-hidden />
          </Link>
        ) : null}
        <Link
          to={`/bill/order/${o.id}`}
          className="inline-flex min-h-9 items-center gap-1 rounded px-2 text-sm text-muted hover:bg-subtle hover:text-primary"
        >
          <FileText size={14} aria-hidden /> ใบส่งของ
        </Link>
      </div>
    </li>
  );
}

export default function BillList({
  rows,
  totals,
}: {
  rows: BillRowData[];
  totals: BillTotals;
}) {
  return (
    <>
      <div
        className={[
          "hidden border-b border-border bg-subtle/60 px-5 py-2.5 text-xs font-medium text-muted lg:grid lg:gap-x-4",
          COLS,
        ].join(" ")}
        aria-hidden
      >
        <span>บิล · ขั้นตอน</span>
        <span className="text-right">ยอดบิล</span>
        <span className="text-right">ค่ารถคนขับ</span>
        <span className="text-right">คงเหลือเข้าร้าน</span>
        <span />
      </div>
      <ul className="divide-y divide-border">
        {rows.map((r) => (
          <BillRow key={r.order.id} {...r} />
        ))}
      </ul>
      <div
        className={[
          "flex flex-wrap items-center justify-between gap-x-4 gap-y-1 border-t border-border bg-subtle/60 px-4 py-3 text-sm sm:px-5 lg:grid lg:gap-x-4",
          COLS,
        ].join(" ")}
      >
        <span className="font-medium">รวม {totals.count} บิล</span>
        <span className="tabular-nums lg:text-right">
          <span className="text-muted lg:sr-only">ยอดบิล </span>
          {formatMoney(totals.revenue)}
        </span>
        <span className="tabular-nums text-muted lg:text-right">
          <span className="lg:sr-only">ค่ารถ </span>−
          {formatMoney(totals.driverCost)}
        </span>
        <b className="tabular-nums text-success lg:text-right">
          <span className="font-normal text-muted lg:sr-only">เหลือ </span>
          {formatMoney(totals.net)}
        </b>
        <span className="hidden lg:block" />
      </div>
    </>
  );
}
