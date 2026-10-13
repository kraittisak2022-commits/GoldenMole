import { useState } from 'react';
import { Check, Copy, ExternalLink, Share2 } from 'lucide-react';
import { buildShareText } from '../../shared/shareText';
import { copyText } from '../lib/clipboard';
import { useManualCopy } from './ManualCopy';
import Button from './ui/Button';
import { useToast } from './ui/Toast';

export function useCopyShare() {
  const toast = useToast();
  const manualCopy = useManualCopy();
  return async (title: string, url: string) => {
    const text = buildShareText(title, url);
    const ok = await copyText(text);
    if (ok) toast('คัดลอกชื่อรายงานและลิงก์แล้ว');
    else manualCopy(text);
    return ok;
  };
}

/**
 * Opens the phone's share sheet (LINE, Messages, …) with the same two lines as Copy.
 * Null where the browser has no share sheet, so callers can hide the button.
 */
export function useNativeShare() {
  const copyShare = useCopyShare();
  if (typeof navigator === 'undefined' || typeof navigator.share !== 'function') return null;
  return async (title: string, url: string) => {
    try {
      await navigator.share({ text: buildShareText(title, url) });
    } catch (err) {
      if ((err as Error)?.name !== 'AbortError') await copyShare(title, url);
    }
  };
}

/** Preview of exactly what will be pasted into the group, with Copy and Open-in-Drive. */
export default function ShareCard({ title, shareUrl, driveFolderUrl }: { title: string; shareUrl: string; driveFolderUrl: string }) {
  const copyShare = useCopyShare();
  const share = useNativeShare();
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    if (await copyShare(title, shareUrl)) {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  return (
    <div className="rounded-2xl bg-container p-4">
      <p className="text-xs font-medium text-muted">ข้อความที่จะคัดลอก</p>
      <div className="mt-2 select-all rounded-xl bg-surface px-4 py-3 text-sm">
        <p className="break-words font-medium text-ink">{title}</p>
        <a href={shareUrl} target="_blank" rel="noreferrer" className="break-all text-primary underline-offset-2 hover:underline">
          {shareUrl}
        </a>
      </div>
      <p className="mt-2 text-xs text-muted">ทุกคนที่มีลิงก์ดูรูปได้ โดยไม่ต้องเข้าสู่ระบบ</p>
      <div className="mt-4 flex flex-wrap gap-2">
        <Button onClick={copy} className="flex-1">
          {copied ? <Check size={18} aria-hidden /> : <Copy size={18} aria-hidden />}
          {copied ? 'คัดลอกแล้ว' : 'คัดลอกชื่อรายงาน + ลิงก์'}
        </Button>
        {share ? (
          <Button variant="outlined" onClick={() => share(title, shareUrl)}>
            <Share2 size={18} aria-hidden /> แชร์
          </Button>
        ) : null}
        <a
          href={driveFolderUrl}
          target="_blank"
          rel="noreferrer"
          className="inline-flex min-h-11 items-center justify-center gap-2 rounded-full border border-border px-5 text-sm font-medium text-primary transition hover:bg-primary/[0.08]"
        >
          <ExternalLink size={18} aria-hidden /> เปิดใน Google Drive
        </a>
      </div>
    </div>
  );
}
