import { Link } from 'react-router-dom';

export function LogoMark({ size = 28 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" aria-hidden>
      <path d="M32 8a12 12 0 0 1 12 12v12H32a12 12 0 0 1 0-24Z" fill="#FBBC04" />
      <path d="M56 32a12 12 0 0 1-12 12H32V32a12 12 0 0 1 24 0Z" fill="#34A853" />
      <path d="M32 56a12 12 0 0 1-12-12V32h12a12 12 0 0 1 0 24Z" fill="#EA4335" />
      <path d="M8 32a12 12 0 0 1 12-12h12v12a12 12 0 0 1-24 0Z" fill="#4285F4" />
    </svg>
  );
}

export default function Logo({ to = '/' }: { to?: string }) {
  return (
    <Link to={to} className="flex min-h-11 min-w-0 items-center gap-2 rounded-full pr-2" aria-label="GoldenMole Photos หน้าแรก">
      <LogoMark />
      <span className="text-[1.375rem] leading-none text-muted">
        <span className="font-medium text-ink">GoldenMole</span> Photos
      </span>
    </Link>
  );
}
