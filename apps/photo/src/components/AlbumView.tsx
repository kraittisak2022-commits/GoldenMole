import { ChangeEvent, DragEvent, ReactNode, useRef, useState } from 'react';
import { Copy, Download, ExternalLink, ImagePlus, GalleryVerticalEnd, Settings, Star, Trash2, UploadCloud, X } from 'lucide-react';
import type { MediaItem, UploadTarget } from '../../shared/types';
import { formatCount, formatReportDateLong } from '../lib/format';
import JustifiedGrid from './JustifiedGrid';
import Lightbox from './Lightbox';
import { useCopyShare } from './ShareCard';
import Button from './ui/Button';
import IconButton from './ui/IconButton';
import Modal from './ui/Modal';
import { EmptyState } from './ui/States';
import TextField from './ui/TextField';
import { useUploads } from './uploads/UploadProvider';

export interface StaffActions {
  onDelete: (ids: string[]) => Promise<void>;
  onSetCover: (id: string) => Promise<void>;
  onOpenSettings: () => void;
}

interface Props {
  title: string;
  reportDate: string;
  media: MediaItem[];
  shareUrl: string;
  driveFolderUrl: string;
  /** null when uploading is not allowed. */
  uploadTarget: UploadTarget | null;
  /** Ask link visitors for an optional name the first time they upload. */
  askUploaderName?: boolean;
  staff?: StaffActions;
  topBar: ReactNode;
}

const NAME_KEY = 'photo_uploader_name';
const readName = () => {
  try {
    return localStorage.getItem(NAME_KEY);
  } catch {
    return null;
  }
};

/** Drive serves downloads from its own domain; hidden iframes start several at once without leaving the page. */
function downloadAll(items: MediaItem[]) {
  items.forEach((item, i) => {
    setTimeout(() => {
      const frame = document.createElement('iframe');
      frame.style.display = 'none';
      frame.src = item.src.download;
      document.body.appendChild(frame);
      setTimeout(() => frame.remove(), 60_000);
    }, i * 500);
  });
}

export default function AlbumView({ title, reportDate, media, shareUrl, driveFolderUrl, uploadTarget, askUploaderName, staff, topBar }: Props) {
  const { enqueue } = useUploads();
  const copyShare = useCopyShare();
  const inputRef = useRef<HTMLInputElement>(null);
  const [viewing, setViewing] = useState<number | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [confirmDelete, setConfirmDelete] = useState<string[] | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [dragging, setDragging] = useState(false);
  const [namePrompt, setNamePrompt] = useState(false);
  const [uploaderName, setUploaderName] = useState(() => readName() ?? '');

  const addFiles = (files: File[]) => {
    if (!uploadTarget || !files.length) return;
    enqueue(files, uploadTarget, askUploaderName ? uploaderName.trim() || null : null);
  };

  const pick = () => {
    if (askUploaderName && readName() === null) setNamePrompt(true);
    else inputRef.current?.click();
  };

  const confirmName = () => {
    try {
      localStorage.setItem(NAME_KEY, uploaderName.trim());
    } catch {
      // ignore
    }
    setNamePrompt(false);
    inputRef.current?.click();
  };

  const onInput = (e: ChangeEvent<HTMLInputElement>) => {
    addFiles(Array.from(e.target.files ?? []));
    e.target.value = '';
  };

  const hasFiles = (e: DragEvent) => Array.from(e.dataTransfer.types).includes('Files');
  const onDragOver = (e: DragEvent) => {
    if (!uploadTarget || !hasFiles(e)) return;
    e.preventDefault();
    setDragging(true);
  };
  const onDrop = (e: DragEvent) => {
    if (!uploadTarget) return;
    e.preventDefault();
    setDragging(false);
    addFiles(Array.from(e.dataTransfer.files));
  };

  const toggle = (id: string) =>
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const selectedItems = media.filter((m) => selected.has(m.id));

  const runDelete = async () => {
    if (!staff || !confirmDelete) return;
    setDeleting(true);
    try {
      await staff.onDelete(confirmDelete);
      setSelected(new Set());
      setConfirmDelete(null);
      setViewing(null);
    } finally {
      setDeleting(false);
    }
  };

  return (
    <div className="min-h-[100dvh] pb-32" onDragOver={onDragOver} onDragLeave={() => setDragging(false)} onDrop={onDrop}>
      {selected.size > 0 && staff ? (
        <div className="sticky top-0 z-30 border-b border-border/60 bg-primary-soft pt-[env(safe-area-inset-top)] text-primary-soft-foreground">
          <div className="mx-auto flex h-16 max-w-[1600px] items-center gap-1 px-2 sm:px-4">
            <IconButton label="ยกเลิกการเลือก" onClick={() => setSelected(new Set())} className="text-primary-soft-foreground">
              <X size={22} aria-hidden />
            </IconButton>
            <p className="min-w-0 flex-1 text-base font-medium" aria-live="polite">
              เลือกแล้ว {selected.size}
            </p>
            <IconButton label="ดาวน์โหลดที่เลือก" onClick={() => downloadAll(selectedItems)} className="text-primary-soft-foreground">
              <Download size={22} aria-hidden />
            </IconButton>
            {selected.size === 1 ? (
              <IconButton
                label="ตั้งเป็นภาพปก"
                onClick={() => staff.onSetCover([...selected][0]).then(() => setSelected(new Set()))}
                className="text-primary-soft-foreground"
              >
                <Star size={22} aria-hidden />
              </IconButton>
            ) : null}
            <IconButton label="ลบที่เลือก" onClick={() => setConfirmDelete([...selected])} className="text-primary-soft-foreground">
              <Trash2 size={22} aria-hidden />
            </IconButton>
          </div>
        </div>
      ) : (
        topBar
      )}

      <main className="mx-auto max-w-[1600px] px-4 sm:px-6">
        <header className="pb-4 pt-6 sm:pt-10">
          <h1 className="break-words text-[1.75rem] font-normal leading-tight text-ink sm:text-[2.5rem]">{title}</h1>
          <p className="mt-2 text-sm text-muted">
            {formatReportDateLong(reportDate)} · {formatCount(media.length)}
          </p>
          <div className="mt-5 flex flex-wrap items-center gap-2">
            <Button onClick={() => copyShare(title, shareUrl)}>
              <Copy size={18} aria-hidden /> คัดลอกชื่อรายงาน + ลิงก์
            </Button>
            {uploadTarget ? (
              <Button variant="tonal" onClick={pick}>
                <ImagePlus size={18} aria-hidden /> เพิ่มรูป
              </Button>
            ) : null}
            <a
              href={driveFolderUrl}
              target="_blank"
              rel="noreferrer"
              className="inline-flex min-h-11 items-center gap-2 rounded-full border border-border px-5 text-sm font-medium text-primary transition hover:bg-primary/[0.08]"
            >
              <ExternalLink size={18} aria-hidden /> เปิดใน Google Drive
            </a>
            {staff ? (
              <IconButton label="ตั้งค่าอัลบั้ม" onClick={staff.onOpenSettings}>
                <Settings size={22} aria-hidden />
              </IconButton>
            ) : null}
          </div>
        </header>

        {media.length ? (
          <JustifiedGrid media={media} selectable={!!staff} selected={selected} onOpen={setViewing} onToggle={toggle} />
        ) : (
          <EmptyState
            icon={<GalleryVerticalEnd size={44} strokeWidth={1.5} aria-hidden />}
            title="ยังไม่มีรูปในอัลบั้มนี้"
            body={uploadTarget ? 'กด “เพิ่มรูป” หรือลากไฟล์มาวางที่หน้านี้ รองรับรูปและวิดีโอ' : 'เมื่อมีคนเพิ่มรูป รูปจะแสดงที่นี่'}
            action={
              uploadTarget ? (
                <Button onClick={pick}>
                  <ImagePlus size={18} aria-hidden /> เพิ่มรูป
                </Button>
              ) : undefined
            }
          />
        )}
      </main>

      <input ref={inputRef} type="file" accept="image/*,video/*" multiple className="hidden" onChange={onInput} tabIndex={-1} aria-hidden />

      {dragging ? (
        <div className="pointer-events-none fixed inset-0 z-50 flex items-center justify-center bg-primary/10 p-6">
          <div className="flex flex-col items-center gap-3 rounded-2xl border-2 border-dashed border-primary bg-surface px-10 py-8 text-primary shadow-e3">
            <UploadCloud size={40} aria-hidden />
            <p className="text-base font-medium">วางไฟล์เพื่อเพิ่มลงอัลบั้ม</p>
          </div>
        </div>
      ) : null}

      {viewing !== null && media[viewing] ? (
        <Lightbox
          media={media}
          index={viewing}
          onIndex={setViewing}
          onClose={() => setViewing(null)}
          onDelete={staff ? (item) => setConfirmDelete([item.id]) : undefined}
        />
      ) : null}

      <Modal
        open={!!confirmDelete}
        title={confirmDelete && confirmDelete.length > 1 ? `ลบ ${confirmDelete.length} รายการ?` : 'ลบรายการนี้?'}
        onClose={() => setConfirmDelete(null)}
        footer={
          <>
            <Button variant="text" onClick={() => setConfirmDelete(null)}>
              ยกเลิก
            </Button>
            <Button variant="danger" onClick={runDelete} disabled={deleting}>
              {deleting ? 'กำลังลบ…' : 'ลบ'}
            </Button>
          </>
        }
      >
        <p className="text-sm text-muted">ไฟล์จะถูกย้ายไปถังขยะของ Google Drive และกู้คืนได้ภายใน 30 วัน</p>
      </Modal>

      <Modal
        open={namePrompt}
        title="เพิ่มรูปลงอัลบั้ม"
        onClose={() => setNamePrompt(false)}
        footer={
          <Button onClick={confirmName}>
            <ImagePlus size={18} aria-hidden /> เลือกรูปและวิดีโอ
          </Button>
        }
      >
        <TextField
          label="ชื่อของคุณ (ไม่บังคับ)"
          placeholder="เช่น ช่างสมชาย"
          value={uploaderName}
          maxLength={60}
          onChange={(e) => setUploaderName(e.target.value)}
          hint="ชื่อนี้จะแสดงในข้อมูลของรูปที่คุณเพิ่ม"
        />
      </Modal>
    </div>
  );
}
