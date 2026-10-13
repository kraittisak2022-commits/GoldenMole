import { useEffect, useMemo, useState } from 'react';
import { useParams } from 'react-router-dom';
import { ImageOff } from 'lucide-react';
import { sortMedia } from '../../shared/mediaOrder';
import type { MediaItem, SharedAlbum } from '../../shared/types';
import { useAuth } from '../auth/AuthProvider';
import AlbumView from '../components/AlbumView';
import AllAlbumsLink from '../components/AllAlbumsLink';
import Logo from '../components/Logo';
import { EmptyState, ErrorState, Spinner } from '../components/ui/States';
import { api, errorCode } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { useUploadedMedia } from '../lib/useUploadedMedia';

/** Signed-in staff who open a share link get a way back to every album; link visitors only see this one. */
function PublicTopBar({ token }: { token: string }) {
  const { user } = useAuth();
  return (
    <header className="sticky top-0 z-30 border-b border-border/60 bg-page/95 pt-[env(safe-area-inset-top)] backdrop-blur">
      <div className="mx-auto flex h-16 max-w-[1600px] items-center px-2 sm:px-4">{user ? <AllAlbumsLink /> : <Logo to={`/a/${token}`} />}</div>
    </header>
  );
}

/** What anyone with the link sees: no sign-in, view and download, add photos when the album allows it. */
export default function SharedAlbumPage() {
  const { token = '' } = useParams();
  const [album, setAlbum] = useState<SharedAlbum | null>(null);
  const [error, setError] = useState<{ message: string; notFound: boolean } | null>(null);

  const load = () => {
    setError(null);
    api<SharedAlbum>(`/api/share/${encodeURIComponent(token)}`)
      .then((a) => {
        setAlbum(a);
        document.title = `${a.title} · GoldenMole Photos`;
      })
      .catch((err) => setError({ message: errorMessage(err), notFound: errorCode(err) === 'not_found' }));
  };
  useEffect(load, [token]);

  const target = useMemo(() => (album?.allowLinkUpload ? { shareToken: token } : null), [album?.allowLinkUpload, token]);
  useUploadedMedia(target, (media: MediaItem) =>
    setAlbum((a) => (a && !a.media.some((m) => m.id === media.id) ? { ...a, media: sortMedia([...a.media, media]) } : a)),
  );

  if (error) {
    return (
      <>
        <PublicTopBar token={token} />
        {error.notFound ? (
          <EmptyState icon={<ImageOff size={40} strokeWidth={1.5} aria-hidden />} title="ไม่พบอัลบั้มนี้" body="ลิงก์อาจถูกเปลี่ยนหรืออัลบั้มถูกลบแล้ว ขอลิงก์ใหม่จากผู้ส่ง" />
        ) : (
          <ErrorState message={error.message} onRetry={load} />
        )}
      </>
    );
  }
  if (!album) {
    return (
      <>
        <PublicTopBar token={token} />
        <div className="flex justify-center py-24">
          <Spinner />
        </div>
      </>
    );
  }

  return (
    <AlbumView
      title={album.title}
      reportDate={album.reportDate}
      media={album.media}
      shareUrl={album.shareUrl}
      driveFolderUrl={album.driveFolderUrl}
      uploadTarget={target}
      askUploaderName
      topBar={<PublicTopBar token={token} />}
    />
  );
}
