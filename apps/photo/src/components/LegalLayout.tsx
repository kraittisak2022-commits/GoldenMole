import { ReactNode, useEffect } from 'react';
import { Link } from 'react-router-dom';
import Logo from './Logo';

export const CONTACT_EMAIL = 'kraittisak2022@gmail.com';
export const EFFECTIVE_DATE = '13 ตุลาคม 2569';

export function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="mt-8">
      <h2 className="text-lg font-medium text-ink">{title}</h2>
      <div className="mt-2 space-y-3 text-[0.9375rem] leading-7 text-muted [&_li]:ml-5 [&_li]:list-disc [&_strong]:font-medium [&_strong]:text-ink">
        {children}
      </div>
    </section>
  );
}

/** Public, sign-in free page for the privacy policy and terms (linked from the Google OAuth consent screen). */
export default function LegalLayout({ title, children }: { title: string; children: ReactNode }) {
  useEffect(() => {
    document.title = `${title} · GoldenMole Photos`;
  }, [title]);

  return (
    <div className="min-h-[100dvh] bg-page">
      <header className="sticky top-0 z-30 border-b border-border/60 bg-page/95 pt-[env(safe-area-inset-top)] backdrop-blur">
        <div className="mx-auto flex h-16 max-w-3xl items-center px-2 sm:px-4">
          <Logo />
        </div>
      </header>
      <main className="mx-auto max-w-3xl px-4 pb-16 pt-8 sm:px-6">
        <h1 className="text-[2rem] font-normal leading-tight text-ink">{title}</h1>
        <p className="mt-2 text-sm text-muted">มีผลตั้งแต่ {EFFECTIVE_DATE}</p>
        {children}
        <nav className="mt-12 flex flex-wrap gap-x-6 gap-y-2 border-t border-border pt-6 text-sm">
          <Link to="/privacy" className="text-primary hover:underline">นโยบายความเป็นส่วนตัว</Link>
          <Link to="/terms" className="text-primary hover:underline">ข้อกำหนดการใช้งาน</Link>
          <a href={`mailto:${CONTACT_EMAIL}`} className="text-primary hover:underline">{CONTACT_EMAIL}</a>
        </nav>
      </main>
    </div>
  );
}
