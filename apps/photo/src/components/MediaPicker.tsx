import { ChangeEvent, DragEvent, useEffect, useRef, useState } from 'react';
import { Film, Image as ImageIcon, ImagePlus, Play, X } from 'lucide-react';
import { checkUpload, guessMimeType, MAX_IMAGE_BYTES, MAX_VIDEO_BYTES } from '../../shared/limits';
import { formatBytes } from '../lib/format';

/** Rendering every full-size photo would exhaust memory on phones; the rest are counted in a "+N" tile. */
const MAX_PREVIEWS = 30;

const fileKey = (f: File) => `${f.name}:${f.size}:${f.lastModified}`;

function Preview({ file, onRemove }: { file: File; onRemove: () => void }) {
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  const isVideo = guessMimeType(file.name, file.type).startsWith('video/');

  useEffect(() => {
    const objectUrl = URL.createObjectURL(file);
    setUrl(objectUrl);
    return () => URL.revokeObjectURL(objectUrl);
  }, [file]);

  return (
    <li className="no-callout relative aspect-square overflow-hidden rounded-lg bg-container">
      {url && !failed ? (
        isVideo ? (
          // #t=0.1 makes iOS Safari paint the first frame instead of a blank box.
          <video src={`${url}#t=0.1`} muted playsInline preload="metadata" onError={() => setFailed(true)} className="h-full w-full object-cover" />
        ) : (
          <img src={url} alt="" loading="lazy" decoding="async" onError={() => setFailed(true)} className="h-full w-full object-cover" />
        )
      ) : (
        <span className="flex h-full w-full items-center justify-center text-muted">
          {isVideo ? <Film size={22} strokeWidth={1.5} aria-hidden /> : <ImageIcon size={22} strokeWidth={1.5} aria-hidden />}
        </span>
      )}
      {isVideo ? (
        <span className="pointer-events-none absolute bottom-1 left-1 flex h-5 w-5 items-center justify-center rounded-full bg-black/55 text-white">
          <Play size={10} fill="currentColor" aria-hidden />
        </span>
      ) : null}
      <button
        type="button"
        onClick={onRemove}
        aria-label={`เอา ${file.name} ออก`}
        className="absolute right-0 top-0 flex h-9 w-9 cursor-pointer items-start justify-end p-1"
      >
        <span className="flex h-6 w-6 items-center justify-center rounded-full bg-black/60 text-white">
          <X size={14} strokeWidth={2.5} aria-hidden />
        </span>
      </button>
    </li>
  );
}

interface Props {
  files: File[];
  onChange: (files: File[]) => void;
}

/** Choose photos and videos before the album exists, like starting an album in LINE. */
export default function MediaPicker({ files, onChange }: Props) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [dragging, setDragging] = useState(false);
  const [rejected, setRejected] = useState(0);

  const add = (picked: File[]) => {
    const ok = picked.filter((f) => checkUpload({ mimeType: guessMimeType(f.name, f.type), size: f.size }).ok);
    setRejected(picked.length - ok.length);
    const seen = new Set(files.map(fileKey));
    onChange([...files, ...ok.filter((f) => !seen.has(fileKey(f)))]);
  };

  const onInput = (e: ChangeEvent<HTMLInputElement>) => {
    add(Array.from(e.target.files ?? []));
    e.target.value = '';
  };
  const onDrop = (e: DragEvent) => {
    e.preventDefault();
    setDragging(false);
    add(Array.from(e.dataTransfer.files));
  };

  const totalBytes = files.reduce((sum, f) => sum + f.size, 0);
  const shown = files.slice(0, MAX_PREVIEWS);
  const hidden = files.length - shown.length;

  return (
    <div
      onDragOver={(e) => {
        e.preventDefault();
        setDragging(true);
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={onDrop}
      className={`rounded-2xl transition ${dragging ? 'bg-primary/10 ring-2 ring-primary' : ''}`}
    >
      <div className="mb-2 flex items-baseline justify-between gap-2">
        <p className="text-sm font-medium text-ink">รูปและวิดีโอ</p>
        {files.length ? (
          <p className="text-xs text-muted">
            {files.length} รายการ · {formatBytes(totalBytes)}
          </p>
        ) : null}
      </div>
      <ul className="grid grid-cols-4 gap-1.5 sm:grid-cols-5">
        <li className="aspect-square">
          <button
            type="button"
            onClick={() => inputRef.current?.click()}
            className="flex h-full w-full cursor-pointer flex-col items-center justify-center gap-1 rounded-lg border-2 border-dashed border-border text-primary transition hover:bg-primary/[0.06] active:bg-primary/[0.12]"
          >
            <ImagePlus size={24} aria-hidden />
            <span className="text-[11px] font-medium">{files.length ? 'เพิ่มอีก' : 'เลือก'}</span>
          </button>
        </li>
        {shown.map((file) => (
          <Preview key={fileKey(file)} file={file} onRemove={() => onChange(files.filter((f) => f !== file))} />
        ))}
        {hidden > 0 ? (
          <li className="flex aspect-square items-center justify-center rounded-lg bg-container text-sm font-medium text-muted">+{hidden}</li>
        ) : null}
      </ul>
      {rejected ? (
        <p role="alert" className="mt-2 text-xs text-destructive">
          ข้าม {rejected} ไฟล์ที่ไม่ใช่รูป/วิดีโอ หรือใหญ่เกินไป (รูปไม่เกิน {formatBytes(MAX_IMAGE_BYTES)} วิดีโอไม่เกิน {formatBytes(MAX_VIDEO_BYTES)})
        </p>
      ) : null}
      {!files.length ? <p className="mt-2 text-xs text-muted">เลือกไว้ก่อนได้เลย ระบบจะอัปโหลดให้ทันทีหลังสร้างอัลบั้ม</p> : null}
      <input ref={inputRef} type="file" accept="image/*,video/*" multiple className="hidden" onChange={onInput} tabIndex={-1} aria-hidden />
    </div>
  );
}
