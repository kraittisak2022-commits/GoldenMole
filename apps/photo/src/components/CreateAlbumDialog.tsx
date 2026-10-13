import { FormEvent, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { todayInBangkok } from '../../shared/folderPath';
import { MAX_TITLE_LENGTH, normalizeTitle } from '../../shared/limits';
import type { AlbumSummary } from '../../shared/types';
import { api } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { formatReportDateLong } from '../lib/format';
import { drivePathLabel } from '../lib/drivePath';
import MediaPicker from './MediaPicker';
import ShareCard from './ShareCard';
import Button from './ui/Button';
import Modal from './ui/Modal';
import TextField from './ui/TextField';
import { useToast } from './ui/Toast';
import { useUploads } from './uploads/UploadProvider';

interface Props {
  open: boolean;
  onClose: () => void;
  onCreated: (album: AlbumSummary) => void;
}

export default function CreateAlbumDialog({ open, onClose, onCreated }: Props) {
  const navigate = useNavigate();
  const toast = useToast();
  const { enqueue } = useUploads();
  const [title, setTitle] = useState('');
  const [reportDate, setReportDate] = useState(todayInBangkok());
  const [files, setFiles] = useState<File[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [created, setCreated] = useState<AlbumSummary | null>(null);

  useEffect(() => {
    if (!open) return;
    setTitle('');
    setReportDate(todayInBangkok());
    setFiles([]);
    setError(null);
    setCreated(null);
  }, [open]);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const clean = normalizeTitle(title);
    if (!clean) {
      setError('ตั้งชื่อรายงาน');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const album = await api<AlbumSummary>('/api/albums', { method: 'POST', body: { title: clean, reportDate } });
      onCreated(album);
      if (files.length) {
        enqueue(files, { albumId: album.id });
        onClose();
        navigate(`/albums/${album.id}`);
        toast(`สร้างอัลบั้มแล้ว กำลังอัปโหลด ${files.length} รายการ`);
      } else {
        setCreated(album);
      }
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  if (created) {
    return (
      <Modal
        open={open}
        title="สร้างอัลบั้มแล้ว"
        onClose={onClose}
        footer={
          <>
            <Button variant="text" onClick={onClose}>
              ปิด
            </Button>
            <Button variant="tonal" onClick={() => navigate(`/albums/${created.id}`)}>
              เปิดอัลบั้มและเพิ่มรูป
            </Button>
          </>
        }
      >
        <ShareCard title={created.title} shareUrl={created.shareUrl} driveFolderUrl={created.driveFolderUrl} />
      </Modal>
    );
  }

  return (
    <Modal
      open={open}
      title="อัลบั้มใหม่"
      onClose={onClose}
      footer={
        <>
          <Button variant="text" onClick={onClose}>
            ยกเลิก
          </Button>
          <Button type="submit" form="create-album" disabled={busy}>
            {busy ? 'กำลังสร้าง…' : files.length ? `สร้างและอัปโหลด ${files.length} รายการ` : 'สร้าง'}
          </Button>
        </>
      }
    >
      <form id="create-album" onSubmit={submit} noValidate className="space-y-5 pt-2">
        <TextField
          label="ชื่อรายงาน"
          placeholder="เช่น เทปูนชั้น 2 อาคาร A"
          value={title}
          maxLength={MAX_TITLE_LENGTH}
          onChange={(e) => setTitle(e.target.value)}
          error={error}
          autoFocus={window.matchMedia('(hover: hover)').matches}
        />
        <MediaPicker files={files} onChange={setFiles} />
        <TextField
          label="วันที่รายงาน"
          type="date"
          value={reportDate}
          onChange={(e) => setReportDate(e.target.value || todayInBangkok())}
          hint={`${formatReportDateLong(reportDate)} · เก็บใน ${drivePathLabel(reportDate)} · คนที่มีลิงก์เพิ่มรูปได้`}
        />
      </form>
    </Modal>
  );
}
