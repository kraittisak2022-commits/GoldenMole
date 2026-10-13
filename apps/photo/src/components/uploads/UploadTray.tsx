import { useState } from 'react';
import { AlertCircle, CheckCircle2, ChevronDown, ChevronUp, Film, Image as ImageIcon, RotateCw, X } from 'lucide-react';
import { formatBytes } from '../../lib/format';
import IconButton from '../ui/IconButton';
import { type UploadItem, useUploads } from './UploadProvider';

function Row({ item }: { item: UploadItem }) {
  const { retry, cancel } = useUploads();
  const Icon = item.mimeType.startsWith('video/') ? Film : ImageIcon;
  const active = item.status === 'queued' || item.status === 'uploading';
  const detail =
    item.status === 'error'
      ? item.error
      : item.status === 'canceled'
        ? 'ยกเลิกแล้ว'
        : item.status === 'queued'
          ? `รอคิว · ${formatBytes(item.file.size)}`
          : item.status === 'done'
            ? formatBytes(item.file.size)
            : `${Math.round(item.progress * 100)}% · ${formatBytes(item.file.size)}`;

  return (
    <li className="flex items-center gap-3 py-2 pl-4 pr-2">
      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-container text-muted">
        <Icon size={20} aria-hidden />
      </span>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm text-ink">{item.file.name}</p>
        <p className={`truncate text-xs ${item.status === 'error' ? 'text-destructive' : 'text-muted'}`}>{detail}</p>
        {item.status === 'uploading' ? (
          <div className="mt-1 h-1 overflow-hidden rounded-full bg-container-high" role="progressbar" aria-valuenow={Math.round(item.progress * 100)} aria-valuemin={0} aria-valuemax={100} aria-label={`อัปโหลด ${item.file.name}`}>
            <div className="h-full rounded-full bg-primary transition-[width] duration-200" style={{ width: `${item.progress * 100}%` }} />
          </div>
        ) : null}
      </div>
      {item.status === 'done' ? (
        <CheckCircle2 size={22} className="mr-2.5 shrink-0 text-success" aria-label="อัปโหลดแล้ว" />
      ) : item.status === 'error' ? (
        <IconButton label="ลองใหม่" onClick={() => retry(item.id)}>
          <RotateCw size={18} aria-hidden />
        </IconButton>
      ) : active ? (
        <IconButton label="ยกเลิก" onClick={() => cancel(item.id)}>
          <X size={18} aria-hidden />
        </IconButton>
      ) : null}
    </li>
  );
}

/** Bottom-right panel like Google Photos: summary header, collapsible list, closes when everything finished. */
export default function UploadTray() {
  const { items, clearFinished } = useUploads();
  const [collapsed, setCollapsed] = useState(false);
  if (!items.length) return null;

  const active = items.filter((i) => i.status === 'queued' || i.status === 'uploading').length;
  const failed = items.filter((i) => i.status === 'error').length;
  const done = items.filter((i) => i.status === 'done').length;
  const title = active
    ? `กำลังอัปโหลด ${active} รายการ`
    : failed
      ? `อัปโหลดไม่สำเร็จ ${failed} รายการ`
      : `อัปโหลดแล้ว ${done} รายการ`;
  const counted = items.filter((i) => i.status !== 'canceled' && i.status !== 'error');
  const totalBytes = counted.reduce((sum, i) => sum + i.file.size, 0);
  const sentBytes = counted.reduce((sum, i) => sum + i.file.size * (i.status === 'done' ? 1 : i.progress), 0);
  const overall = totalBytes ? sentBytes / totalBytes : 0;

  return (
    <section
      aria-label="การอัปโหลด"
      className="fade-in fixed bottom-[max(1rem,env(safe-area-inset-bottom))] left-4 right-4 z-40 overflow-hidden rounded-2xl bg-surface shadow-e3 sm:left-auto sm:w-[380px]"
    >
      <div className="flex items-center gap-1 bg-container py-1 pl-4 pr-1">
        {failed && !active ? <AlertCircle size={20} className="shrink-0 text-destructive" aria-hidden /> : null}
        <div className="min-w-0 flex-1">
          <h2 className="truncate text-sm font-medium text-ink" aria-live="polite">
            {title}
          </h2>
          {active ? <p className="truncate text-xs text-muted">เปิดหน้านี้ค้างไว้จนกว่าจะเสร็จ</p> : null}
        </div>
        <IconButton label={collapsed ? 'แสดงรายการ' : 'ย่อรายการ'} aria-expanded={!collapsed} onClick={() => setCollapsed((v) => !v)}>
          {collapsed ? <ChevronUp size={20} aria-hidden /> : <ChevronDown size={20} aria-hidden />}
        </IconButton>
        {!active ? (
          <IconButton label="ปิด" onClick={clearFinished}>
            <X size={20} aria-hidden />
          </IconButton>
        ) : null}
      </div>
      {active ? (
        <div className="h-1 bg-container-high" role="progressbar" aria-valuenow={Math.round(overall * 100)} aria-valuemin={0} aria-valuemax={100} aria-label="ความคืบหน้ารวม">
          <div className="h-full bg-primary transition-[width] duration-300" style={{ width: `${overall * 100}%` }} />
        </div>
      ) : null}
      {!collapsed ? (
        <ul className="max-h-[min(40dvh,320px)] overflow-y-auto overscroll-contain py-1">
          {items.map((item) => (
            <Row key={item.id} item={item} />
          ))}
        </ul>
      ) : null}
    </section>
  );
}
