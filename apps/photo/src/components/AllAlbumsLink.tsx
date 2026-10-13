import { Link } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';

/** Back to the album list, labelled so it is obvious on a phone where the other albums are. */
export default function AllAlbumsLink() {
  return (
    <Link
      to="/"
      className="inline-flex h-11 items-center gap-2 rounded-full pl-3 pr-4 text-sm font-medium text-ink transition hover:bg-ink/[0.08] active:bg-ink/[0.12]"
    >
      <ArrowLeft size={22} aria-hidden />
      อัลบั้มทั้งหมด
    </Link>
  );
}
