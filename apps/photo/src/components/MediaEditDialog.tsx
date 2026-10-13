import { FormEvent, useEffect, useState } from 'react';
import { MAX_UPLOADER_NAME_LENGTH, splitExtension } from '../../shared/limits';
import type { MediaItem } from '../../shared/types';
import { api } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { fromBangkokInput, toBangkokInput } from '../lib/format';
import Button from './ui/Button';
import Modal from './ui/Modal';
import TextField from './ui/TextField';
import { useToast } from './ui/Toast';

interface Props {
  item: MediaItem | null;
  onClose: () => void;
  onSaved: (item: MediaItem) => void;
}

/** SuperAdmin: rename a photo or video (in Drive too), and correct who sent it and when it was taken. */
export default function MediaEditDialog({ item, onClose, onSaved }: Props) {
  const toast = useToast();
  const [base, setBase] = useState('');
  const [uploader, setUploader] = useState('');
  const [takenAt, setTakenAt] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const ext = item ? splitExtension(item.name)[1] : '';

  useEffect(() => {
    if (!item) return;
    setBase(splitExtension(item.name)[0]);
    setUploader(item.uploadedByName ?? '');
    setTakenAt(toBangkokInput(item.takenAt));
    setError(null);
  }, [item?.id]);

  if (!item) return null;

  const save = async (e: FormEvent) => {
    e.preventDefault();
    if (!base.trim()) {
      setError('ตั้งชื่อไฟล์');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const saved = await api<MediaItem>(`/api/media/${item.id}`, {
        method: 'PATCH',
        body: { name: base.trim() + ext, uploadedByName: uploader.trim() || null, takenAt: fromBangkokInput(takenAt) },
      });
      onSaved(saved);
      toast('บันทึกแล้ว');
      onClose();
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal
      open
      title={item.kind === 'video' ? 'แก้ไขวิดีโอ' : 'แก้ไขรูป'}
      onClose={onClose}
      footer={
        <>
          <Button variant="text" onClick={onClose}>
            ยกเลิก
          </Button>
          <Button type="submit" form="media-edit" disabled={busy}>
            {busy ? 'กำลังบันทึก…' : 'บันทึก'}
          </Button>
        </>
      }
    >
      <form id="media-edit" onSubmit={save} noValidate className="space-y-5 pt-2">
        <TextField
          label="ชื่อไฟล์"
          value={base}
          onChange={(e) => setBase(e.target.value)}
          error={error}
          hint="เปลี่ยนชื่อใน Google Drive ด้วย"
          trailing={ext ? <span className="pr-4 text-base text-muted">{ext}</span> : undefined}
        />
        <TextField
          label="ผู้ส่ง"
          placeholder="ไม่ระบุ"
          value={uploader}
          maxLength={MAX_UPLOADER_NAME_LENGTH}
          onChange={(e) => setUploader(e.target.value)}
        />
        <TextField
          label="วันที่ถ่าย"
          type="datetime-local"
          value={takenAt}
          onChange={(e) => setTakenAt(e.target.value)}
          hint="ใช้เรียงรูปและจัดกลุ่มตามวัน เว้นว่างได้"
        />
      </form>
    </Modal>
  );
}
