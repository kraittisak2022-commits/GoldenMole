import { useEffect, useMemo, useState } from 'react';
import { GalleryVerticalEnd, Plus, Search, X } from 'lucide-react';
import type { AlbumSummary } from '../../shared/types';
import AlbumCard from '../components/AlbumCard';
import CreateAlbumDialog from '../components/CreateAlbumDialog';
import TopBar from '../components/TopBar';
import Button from '../components/ui/Button';
import { EmptyState, ErrorState } from '../components/ui/States';
import { api } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { formatReportDate } from '../lib/format';

function SearchBox({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <label className="flex h-12 w-full max-w-xl items-center gap-2 rounded-full bg-container px-4 transition focus-within:bg-surface focus-within:shadow-e1">
      <Search size={20} className="shrink-0 text-muted" aria-hidden />
      <span className="sr-only">ค้นหาอัลบั้ม</span>
      <input
        type="search"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder="ค้นหาอัลบั้ม"
        className="min-w-0 flex-1 bg-transparent text-base text-ink outline-none placeholder:text-muted [&::-webkit-search-cancel-button]:hidden"
      />
      {value ? (
        <button type="button" onClick={() => onChange('')} aria-label="ล้างคำค้นหา" className="-mr-2 flex h-10 w-10 cursor-pointer items-center justify-center rounded-full text-muted hover:bg-ink/[0.08]">
          <X size={18} aria-hidden />
        </button>
      ) : null}
    </label>
  );
}

export default function AlbumsPage() {
  const [albums, setAlbums] = useState<AlbumSummary[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [creating, setCreating] = useState(false);

  const load = () => {
    setError(null);
    api<AlbumSummary[]>('/api/albums')
      .then(setAlbums)
      .catch((err) => setError(errorMessage(err)));
  };
  useEffect(load, []);

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!albums || !q) return albums;
    return albums.filter((a) => a.title.toLowerCase().includes(q) || formatReportDate(a.reportDate).includes(q));
  }, [albums, query]);

  return (
    <div className="min-h-[100dvh] pb-28">
      <TopBar center={<div className="hidden w-full justify-center md:flex"><SearchBox value={query} onChange={setQuery} /></div>} />
      <main className="mx-auto max-w-[1600px] px-4 sm:px-6">
        <div className="pt-3 md:hidden">
          <SearchBox value={query} onChange={setQuery} />
        </div>
        <div className="flex items-center justify-between gap-4 py-5">
          <h1 className="text-2xl font-normal text-ink">อัลบั้ม</h1>
          <Button variant="tonal" onClick={() => setCreating(true)} className="hidden sm:inline-flex">
            <Plus size={20} aria-hidden /> สร้างอัลบั้ม
          </Button>
        </div>

        {error ? (
          <ErrorState message={error} onRetry={load} />
        ) : !shown ? (
          <div className="grid grid-cols-2 gap-x-4 gap-y-6 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6" aria-busy="true">
            {Array.from({ length: 12 }, (_, i) => (
              <div key={i}>
                <div className="skeleton aspect-square rounded-xl" />
                <div className="skeleton mt-2 h-4 w-3/4 rounded" />
                <div className="skeleton mt-1.5 h-3 w-1/2 rounded" />
              </div>
            ))}
          </div>
        ) : shown.length === 0 ? (
          query ? (
            <EmptyState icon={<Search size={40} aria-hidden />} title="ไม่พบอัลบั้ม" body={`ไม่มีอัลบั้มที่ตรงกับ “${query}”`} />
          ) : (
            <EmptyState
              icon={<GalleryVerticalEnd size={44} strokeWidth={1.5} aria-hidden />}
              title="ยังไม่มีอัลบั้ม"
              body="สร้างอัลบั้มต่อหนึ่งรายงาน แล้วส่งลิงก์ให้ทีมเพิ่มรูปและวิดีโอได้เลย"
              action={
                <Button onClick={() => setCreating(true)}>
                  <Plus size={20} aria-hidden /> สร้างอัลบั้ม
                </Button>
              }
            />
          )
        ) : (
          <div className="grid grid-cols-2 gap-x-4 gap-y-6 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6">
            {shown.map((album) => (
              <AlbumCard key={album.id} album={album} />
            ))}
          </div>
        )}
      </main>

      <button
        type="button"
        onClick={() => setCreating(true)}
        aria-label="สร้างอัลบั้ม"
        className="fixed bottom-[max(1.25rem,env(safe-area-inset-bottom))] right-5 z-20 flex h-14 cursor-pointer items-center gap-2 rounded-2xl bg-primary-soft px-5 text-primary-soft-foreground shadow-e3 transition hover:brightness-95 sm:hidden"
      >
        <Plus size={24} aria-hidden />
        <span className="text-sm font-medium">สร้าง</span>
      </button>

      <CreateAlbumDialog
        open={creating}
        onClose={() => setCreating(false)}
        onCreated={(album) => setAlbums((list) => [album, ...(list ?? [])])}
      />
    </div>
  );
}
