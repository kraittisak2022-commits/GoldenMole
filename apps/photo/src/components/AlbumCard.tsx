import { Link } from 'react-router-dom';
import { Copy, GalleryVerticalEnd, Pencil } from 'lucide-react';
import type { AlbumSummary } from '../../shared/types';
import { formatCount, formatReportDate } from '../lib/format';
import { useCopyShare } from './ShareCard';
import IconButton from './ui/IconButton';
import Thumb from './Thumb';

/** `onEdit` (SuperAdmin) adds a button that opens the album settings: rename, change date, new link, delete. */
export default function AlbumCard({ album, onEdit }: { album: AlbumSummary; onEdit?: (album: AlbumSummary) => void }) {
  const copyShare = useCopyShare();
  return (
    <div className="group min-w-0">
      <Link to={`/albums/${album.id}`} className="block overflow-hidden rounded-xl bg-container" aria-label={`อัลบั้ม ${album.title}`}>
        <div className="aspect-square transition duration-200 group-hover:brightness-95">
          {album.cover ? (
            <Thumb src={album.cover} alt="" className="h-full w-full object-cover" />
          ) : (
            <div className="flex h-full w-full items-center justify-center text-muted">
              <GalleryVerticalEnd size={40} strokeWidth={1.5} aria-hidden />
            </div>
          )}
        </div>
      </Link>
      <div className="mt-2 flex items-start gap-1">
        <Link to={`/albums/${album.id}`} className="min-w-0 flex-1 pt-0.5">
          <p className="line-clamp-2 break-words text-sm font-medium text-ink">{album.title}</p>
          <p className="mt-0.5 text-xs text-muted">
            {formatReportDate(album.reportDate)} · {formatCount(album.mediaCount)}
          </p>
        </Link>
        <div className="-mr-2 -mt-1 flex shrink-0">
          {onEdit ? (
            <IconButton label={`แก้ไขหรือลบอัลบั้ม ${album.title}`} onClick={() => onEdit(album)}>
              <Pencil size={18} aria-hidden />
            </IconButton>
          ) : null}
          <IconButton label={`คัดลอกชื่อรายงานและลิงก์ ${album.title}`} onClick={() => copyShare(album.title, album.shareUrl)}>
            <Copy size={18} aria-hidden />
          </IconButton>
        </div>
      </div>
    </div>
  );
}
