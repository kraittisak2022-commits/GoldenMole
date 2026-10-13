import { ChangeEvent, DragEvent, ReactNode, useCallback, useRef, useState } from 'react';
import { CheckCheck, Copy, Download, ExternalLink, ImagePlus, GalleryVerticalEnd, Settings, Share2, Star, Trash2, UploadCloud, X } from 'lucide-react';
import type { MediaItem, UploadTarget } from '../../shared/types';
import { formatCount, formatReportDateLong } from '../lib/format';
import JustifiedGrid from './JustifiedGrid';
import Lightbox from './Lightbox';
import { useCopyShare, useNativeShare } from './ShareCard';
import Button from './ui/Button';
import IconButton from './ui/IconButton';
import Modal from './ui/Modal';
import { EmptyState } from './ui/States';
import TextField from './ui/TextField';
import { useUploads } from './uploads/UploadProvider';

/** Signed-in staff can select and download; editing and deleting are SuperAdmin only (left undefined otherwise). */
export interface StaffActions {
  onDelete?: (ids: string[]) => Promise<void>;
  onSetCover?: (id: string) => Promise<void>;
  onOpenSettings?: () => void;
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
  const { enqueue, items: uploads } = useUploads();
  const copyShare = useCopyShare();
  const share = useNativeShare();
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

  const toggle = useCallback(
    (id: string) =>
      setSelected((prev) => {
        const next = new Set(prev);
        if (next.has(id)) next.delete(id);
        else next.add(id);
        return next;
      }),
    [],
  );

  const selectedItems = media.filter((m) => selected.has(m.id));

  const runDelete = async () => {
    if (!staff?.onDelete || !confirmDelete) return;
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
            {selected.size < media.length ? (
              <IconButton label="เลือกทั้งหมด" onClick={() => setSelected(new Set(media.map((m) => m.id)))} className="text-primary-soft-foreground">
                <CheckCheck size={22} aria-hidden />
              </IconButton>
            ) : null}
            <IconButton label="ดาวน์โหลดที่เลือก" onClick={() => downloadAll(selectedItems)} className="text-primary-soft-foreground">
              <Download size={22} aria-hidden />
            </IconButton>
            {selected.size === 1 && staff.onSetCover ? (
              <IconButton
                label="ตั้งเป็นภาพปก"
                onClick={() => staff.onSetCover?.([...selected][0]).then(() => setSelected(new Set()))}
                className="text-primary-soft-foreground"
              >
                <Star size={22} aria-hidden />
              </IconButton>
            ) : null}
            {staff.onDelete ? (
              <IconButton label="ลบที่เลือก" onClick={() => setConfirmDelete([...selected])} className="text-primary-soft-foreground">
                <Trash2 size={22} aria-hidden />
              </IconButton>
            ) : null}
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
            <div className="flex w-full gap-2 sm:w-auto">
              <Button onClick={() => copyShare(title, shareUrl)} className="flex-1 sm:flex-none">
                <Copy size={18} aria-hidden /> คัดลอกชื่อรายงาน + ลิงก์
              </Button>
              {share ? (
                <Button variant="outlined" onClick={() => share(title, shareUrl)} aria-label="แชร์" title="แชร์" className="px-3 sm:px-5">
                  <Share2 size={18} aria-hidden />
                  <span className="hidden sm:inline">แชร์</span>
                </Button>
              ) : null}
            </div>
            {uploadTarget ? (
              <Button variant="tonal" onClick={pick}>
                <ImagePlus size={18} aria-hidden /> เพิ่มรูป/วิดีโอ
              </Button>
            ) : null}
            <a
              href={driveFolderUrl}
              target="_blank"
              rel="noreferrer"
              className="inline-flex min-h-11 items-center gap-2 rounded-full border border-border px-5 text-sm font-medium text-primary transition hover:bg-primary/[0.08] active:bg-primary/[0.12]"
            >
              <ExternalLink size={18} aria-hidden /> <span className="hidden sm:inline">เปิดใน Google</span> Drive
            </a>
            {staff?.onOpenSettings ? (
              <IconButton label="ตั้งค่าอัลบั้ม" onClick={staff.onOpenSettings}>
                <Settings size={22} aria-hidden />
              </IconButton>
            ) : null}
          </div>
          {staff && media.length > 1 ? (
            <p className="mt-4 text-xs text-muted [@media(hover:hover)]:hidden">
              {staff.onDelete ? 'แตะค้างที่รูปเพื่อเลือกหลายรูป แล้วดาวน์โหลดหรือลบพร้อมกัน' : 'แตะค้างที่รูปเพื่อเลือกหลายรูป แล้วดาวน์โหลดพร้อมกัน'}
            </p>
          ) : null}
        </header>

        {media.length ? (
          <JustifiedGrid media={media} selectable={!!staff} selected={selected} onOpen={setViewing} onToggle={toggle} />
        ) : (
          <EmptyState
            icon={<GalleryVerticalEnd size={44} strokeWidth={1.5} aria-hidden />}
            title="ยังไม่มีรูปในอัลบั้มนี้"
            body={uploadTarget ? 'กด “เพิ่มรูป/วิดีโอ” หรือลากไฟล์มาวางที่หน้านี้' : 'เมื่อมีคนเพิ่มรูป รูปจะแสดงที่นี่'}
            action={
              uploadTarget ? (
                <Button onClick={pick}>
                  <ImagePlus size={18} aria-hidden /> เพิ่มรูป/วิดีโอ
                </Button>
              ) : undefined
            }
          />
        )}
      </main>

      {uploadTarget && media.length > 0 && !uploads.length && selected.size === 0 ? (
        <button
          type="button"
          onClick={pick}
          className="fade-in fixed bottom-[max(1rem,env(safe-area-inset-bottom))] right-4 z-30 flex h-14 cursor-pointer items-center gap-2 rounded-2xl bg-primary-soft pl-4 pr-5 text-sm font-medium text-primary-soft-foreground shadow-e3 transition active:scale-95 sm:hidden"
        >
          <ImagePlus size={22} aria-hidden /> เพิ่มรูป/วิดีโอ
        </button>
      ) : null}

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
          onDelete={staff?.onDelete ? (item) => setConfirmDelete([item.id]) : undefined}
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
        title="เพิ่มรูปและวิดีโอลงอัลบั้ม"
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
