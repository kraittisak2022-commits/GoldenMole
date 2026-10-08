export default function Skeleton({ className = '' }: { className?: string }) {
  return <span aria-hidden className={`block animate-pulse rounded-[9px] bg-border ${className}`} />;
}
