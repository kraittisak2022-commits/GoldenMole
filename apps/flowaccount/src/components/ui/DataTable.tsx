import { ReactNode } from 'react';

export interface Column<T> {
  key: string;
  header: string;
  className?: string;
  render: (row: T) => ReactNode;
}

interface DataTableProps<T> {
  columns: Column<T>[];
  rows: T[];
  rowKey: (row: T) => string;
  emptyText?: string;
}

export default function DataTable<T>({
  columns,
  rows,
  rowKey,
  emptyText = 'ไม่มีข้อมูล',
}: DataTableProps<T>) {
  return (
    <div className="overflow-x-auto rounded-DEFAULT border border-border bg-surface">
      <table className="min-w-full text-left text-sm">
        <thead className="border-b border-border bg-slate-50/80 text-xs font-medium uppercase tracking-wide text-muted">
          <tr>
            {columns.map((c) => (
              <th key={c.key} className={`px-4 py-3 whitespace-nowrap ${c.className || ''}`}>
                {c.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 ? (
            <tr>
              <td colSpan={columns.length} className="px-4 py-8 text-center text-muted">
                {emptyText}
              </td>
            </tr>
          ) : (
            rows.map((row) => (
              <tr key={rowKey(row)} className="border-b border-border last:border-0 hover:bg-slate-50/60">
                {columns.map((c) => (
                  <td key={c.key} className={`px-4 py-3 align-middle ${c.className || ''}`}>
                    {c.render(row)}
                  </td>
                ))}
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  );
}
