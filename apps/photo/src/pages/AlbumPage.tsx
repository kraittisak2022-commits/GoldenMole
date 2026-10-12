import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';
import { sortMedia } from '../../shared/mediaOrder';
import type { AlbumDetail, MediaItem } from '../../shared/types';
import AlbumSettingsDialog from '../components/AlbumSettingsDialog';
import AlbumView from '../components/AlbumView';
import TopBar from '../components/TopBar';
import { ErrorState, Spinner } from '../components/ui/States';
import { useToast } from '../components/ui/Toast';
import { api } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { useUploadedMedia } from '../lib/useUploadedMedia';

const backLink = (
  <Link to="/" aria-label="กลับไปหน้าอัลบั้ม" className="inline-flex h-11 w-11 items-center justify-center rounded-full text-muted hover:bg-ink/[0.08]">
    <ArrowLeft size={22} aria-hidden />
  </Link>
);

export default function AlbumPage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const toast = useToast();
  const [album, setAlbum] = useState<AlbumDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);

  const load = () => {
    setError(null);
    api<AlbumDetail>(`/api/albums/${id}`)
      .then(setAlbum)
      .catch((err) => setError(errorMessage(err)));
  };
  useEffect(load, [id]);

  const target = useMemo(() => (album ? { albumId: album.id } : null), [album?.id]);
  useUploadedMedia(target, (media: MediaItem) =>
    setAlbum((a) => (a && !a.media.some((m) => m.id === media.id) ? { ...a, media: sortMedia([...a.media, media]), mediaCount: a.mediaCount + 1 } : a)),
  );

  if (error) {
    return (
      <>
        <TopBar leading={backLink} />
        <ErrorState message={error} onRetry={load} />
      </>
    );
  }
  if (!album) {
    return (
      <>
        <TopBar leading={backLink} />
        <div className="flex justify-center py-24">
          <Spinner />
        </div>
      </>
    );
  }

  const removeMedia = async (ids: string[]) => {
    const failed: string[] = [];
    for (const mediaId of ids) {
      try {
        await api(`/api/media/${mediaId}`, { method: 'DELETE' });
      } catch {
        failed.push(mediaId);
      }
    }
    setAlbum((a) => (a ? { ...a, media: a.media.filter((m) => !ids.includes(m.id) || failed.includes(m.id)) } : a));
    toast(failed.length ? `ลบไม่สำเร็จ ${failed.length} รายการ` : `ลบ ${ids.length} รายการแล้ว`);
  };

  const setCover = async (mediaId: string) => {
    try {
      setAlbum(await api<AlbumDetail>(`/api/albums/${album.id}`, { method: 'PATCH', body: { coverMediaId: mediaId } }));
      toast('ตั้งเป็นภาพปกแล้ว');
    } catch (err) {
      toast(errorMessage(err));
    }
  };

  return (
    <>
      <AlbumView
        title={album.title}
        reportDate={album.reportDate}
        media={album.media}
        shareUrl={album.shareUrl}
        driveFolderUrl={album.driveFolderUrl}
        uploadTarget={target}
        staff={{ onDelete: removeMedia, onSetCover: setCover, onOpenSettings: () => setSettingsOpen(true) }}
        topBar={<TopBar leading={backLink} />}
      />
      <AlbumSettingsDialog
        album={album}
        open={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        onSaved={setAlbum}
        onDeleted={() => navigate('/', { replace: true })}
      />
    </>
  );
}
