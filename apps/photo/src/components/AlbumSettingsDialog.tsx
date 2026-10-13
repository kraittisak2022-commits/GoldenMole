import { FormEvent, useEffect, useState } from 'react';
import { Link2, Trash2 } from 'lucide-react';
import { MAX_TITLE_LENGTH, normalizeTitle } from '../../shared/limits';
import type { AlbumDetail, AlbumSummary } from '../../shared/types';
import { api } from '../lib/api';
import { drivePathLabel } from '../lib/drivePath';
import { errorMessage } from '../lib/errors';
import Button from './ui/Button';
import Modal from './ui/Modal';
import TextField from './ui/TextField';
import { useToast } from './ui/Toast';

interface Props {
  album: AlbumSummary;
  open: boolean;
  onClose: () => void;
  onSaved: (album: AlbumDetail) => void;
  onDeleted: () => void;
}

type Confirm = null | 'regenerate' | 'delete';

export default function AlbumSettingsDialog({ album, open, onClose, onSaved, onDeleted }: Props) {
  const toast = useToast();
  const [title, setTitle] = useState(album.title);
  const [reportDate, setReportDate] = useState(album.reportDate);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [confirm, setConfirm] = useState<Confirm>(null);

  useEffect(() => {
    if (!open) return;
    setTitle(album.title);
    setReportDate(album.reportDate);
    setError(null);
    setConfirm(null);
  }, [open]);

  const patch = async (body: Record<string, unknown>, message: string) => {
    setBusy(true);
    setError(null);
    try {
      onSaved(await api<AlbumDetail>(`/api/albums/${album.id}`, { method: 'PATCH', body }));
      toast(message);
      onClose();
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  const save = (e: FormEvent) => {
    e.preventDefault();
    const clean = normalizeTitle(title);
    if (!clean) {
      setError('ตั้งชื่อรายงาน');
      return;
    }
    void patch({ title: clean, reportDate }, 'บันทึกแล้ว');
  };

  const remove = async () => {
    setBusy(true);
    try {
      await api(`/api/albums/${album.id}`, { method: 'DELETE' });
      toast('ลบอัลบั้มแล้ว โฟลเดอร์อยู่ในถังขยะของ Drive 30 วัน');
      onDeleted();
    } catch (err) {
      setError(errorMessage(err));
      setBusy(false);
    }
  };

  if (confirm) {
    const isDelete = confirm === 'delete';
    return (
      <Modal
        open={open}
        title={isDelete ? 'ลบอัลบั้มนี้?' : 'สร้างลิงก์ใหม่?'}
        onClose={() => setConfirm(null)}
        footer={
          <>
            <Button variant="text" onClick={() => setConfirm(null)}>
              ยกเลิก
            </Button>
            <Button
              variant={isDelete ? 'danger' : 'filled'}
              disabled={busy}
              onClick={isDelete ? remove : () => patch({ regenerateLink: true }, 'สร้างลิงก์ใหม่แล้ว คัดลอกไปแชร์อีกครั้ง')}
            >
              {isDelete ? 'ลบอัลบั้ม' : 'สร้างลิงก์ใหม่'}
            </Button>
          </>
        }
      >
        <p className="text-sm text-muted">
          {isDelete
            ? `“${album.title}” และไฟล์ทั้งหมด ${album.mediaCount} รายการจะถูกย้ายไปถังขยะของ Google Drive (กู้คืนได้ใน 30 วัน)`
            : 'ลิงก์เดิมที่แชร์ไปแล้วจะใช้ไม่ได้ทันที แต่คนที่เคยเปิดอัลบั้มหรือบันทึกลิงก์ Google Drive ไว้แล้ว ยังเปิดรูปผ่าน Drive ได้ ถ้าต้องการปิดทั้งหมดให้ลบอัลบั้ม'}
        </p>
        {error ? (
          <p role="alert" className="mt-3 text-sm text-destructive">
            {error}
          </p>
        ) : null}
      </Modal>
    );
  }

  return (
    <Modal
      open={open}
      title="ตั้งค่าอัลบั้ม"
      onClose={onClose}
      footer={
        <>
          <Button variant="text" onClick={onClose}>
            ยกเลิก
          </Button>
          <Button type="submit" form="album-settings" disabled={busy}>
            {busy ? 'กำลังบันทึก…' : 'บันทึก'}
          </Button>
        </>
      }
    >
      <form id="album-settings" onSubmit={save} noValidate className="space-y-5 pt-2">
        <TextField label="ชื่อรายงาน" value={title} maxLength={MAX_TITLE_LENGTH} onChange={(e) => setTitle(e.target.value)} error={error} />
        <TextField
          label="วันที่รายงาน"
          type="date"
          value={reportDate}
          onChange={(e) => setReportDate(e.target.value || album.reportDate)}
          hint={`เก็บใน ${drivePathLabel(reportDate)}${reportDate !== album.reportDate ? ' (ย้ายโฟลเดอร์ให้อัตโนมัติ)' : ''}`}
        />
      </form>
      <div className="mt-4 space-y-1 border-t border-border/70 pt-3">
        <button
          type="button"
          onClick={() => setConfirm('regenerate')}
          className="flex min-h-12 w-full cursor-pointer items-center gap-3 rounded-xl px-3 text-left text-sm text-ink hover:bg-ink/[0.06]"
        >
          <Link2 size={20} className="text-muted" aria-hidden /> สร้างลิงก์แชร์ใหม่ (ลิงก์เดิมใช้ไม่ได้)
        </button>
        <button
          type="button"
          onClick={() => setConfirm('delete')}
          className="flex min-h-12 w-full cursor-pointer items-center gap-3 rounded-xl px-3 text-left text-sm text-destructive hover:bg-destructive/[0.08]"
        >
          <Trash2 size={20} aria-hidden /> ลบอัลบั้ม
        </button>
      </div>
    </Modal>
  );
}
