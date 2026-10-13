import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { sortMedia } from '../../shared/mediaOrder';
import { useAuth } from '../auth/AuthProvider';
import type { AlbumDetail, MediaItem } from '../../shared/types';
import AlbumSettingsDialog from '../components/AlbumSettingsDialog';
import AllAlbumsLink from '../components/AllAlbumsLink';
import AlbumView from '../components/AlbumView';
import TopBar from '../components/TopBar';
import { ErrorState, Spinner } from '../components/ui/States';
import { useToast } from '../components/ui/Toast';
import { api } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { useUploadedMedia } from '../lib/useUploadedMedia';

function withMedia(album: AlbumDetail, added: MediaItem[]): AlbumDetail {
  const fresh = added.filter((m, i) => !album.media.some((x) => x.id === m.id) && added.findIndex((x) => x.id === m.id) === i);
  if (!fresh.length) return album;
  return { ...album, media: sortMedia([...album.media, ...fresh]), mediaCount: album.mediaCount + fresh.length };
}

const backLink = <AllAlbumsLink />;

export default function AlbumPage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const toast = useToast();
  const isSuperAdmin = useAuth().user?.role === 'SuperAdmin';
  const [album, setAlbum] = useState<AlbumDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);

  // Uploads started while creating the album can finish before it has loaded; keep them to merge in.
  const arrived = useRef<MediaItem[]>([]);

  const load = () => {
    setError(null);
    api<AlbumDetail>(`/api/albums/${id}`)
      .then((a) => setAlbum(withMedia(a, arrived.current)))
      .catch((err) => setError(errorMessage(err)));
  };
  useEffect(() => {
    arrived.current = [];
    load();
  }, [id]);

  const target = useMemo(() => ({ albumId: id }), [id]);
  useUploadedMedia(target, (media: MediaItem) => {
    arrived.current.push(media);
    setAlbum((a) => a && withMedia(a, [media]));
  });

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
    const gone = (m: MediaItem) => ids.includes(m.id) && !failed.includes(m.id);
    arrived.current = arrived.current.filter((m) => !gone(m));
    setAlbum((a) => (a ? { ...a, media: a.media.filter((m) => !gone(m)) } : a));
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
        staff={
          isSuperAdmin
            ? { onDelete: removeMedia, onSetCover: setCover, onOpenSettings: () => setSettingsOpen(true) }
            : {}
        }
        topBar={<TopBar leading={backLink} />}
      />
      <AlbumSettingsDialog
        album={album}
        open={settingsOpen && isSuperAdmin}
        onClose={() => setSettingsOpen(false)}
        onSaved={setAlbum}
        onDeleted={() => navigate('/', { replace: true })}
      />
    </>
  );
}
