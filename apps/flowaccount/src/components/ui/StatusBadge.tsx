interface StatusBadgeProps {
  status: 'pending' | 'approved' | 'rejected' | 'income' | 'expense';
  label?: string;
}

const styles: Record<StatusBadgeProps['status'], string> = {
  pending: 'bg-amber-50 text-amber-800 border-amber-200',
  approved: 'bg-emerald-50 text-emerald-800 border-emerald-200',
  rejected: 'bg-red-50 text-red-700 border-red-200',
  income: 'bg-sky-50 text-sky-800 border-sky-200',
  expense: 'bg-slate-100 text-slate-700 border-slate-200',
};

const defaults: Record<StatusBadgeProps['status'], string> = {
  pending: 'รออนุมัติ',
  approved: 'อนุมัติแล้ว',
  rejected: 'ปฏิเสธ',
  income: 'รับ',
  expense: 'จ่าย',
};

export default function StatusBadge({ status, label }: StatusBadgeProps) {
  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${styles[status]}`}
    >
      {label || defaults[status]}
    </span>
  );
}
