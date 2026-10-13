import { Link } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';
import Logo from './Logo';

/** Back arrow plus the logo; both lead to the album list, so it is obvious on a phone where the other albums are. */
export default function AllAlbumsLink() {
  return (
    <div className="flex min-w-0 items-center">
      <Link
        to="/"
        aria-label="อัลบั้มทั้งหมด"
        title="อัลบั้มทั้งหมด"
        className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-ink transition hover:bg-ink/[0.08] active:bg-ink/[0.12]"
      >
        <ArrowLeft size={22} aria-hidden />
      </Link>
      <Logo />
    </div>
  );
}
