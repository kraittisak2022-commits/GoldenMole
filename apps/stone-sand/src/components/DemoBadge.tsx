import { GraduationCap } from 'lucide-react';

/** Marks tour data: DEMO- numbers, hidden from everyone else, deleted when the tour ends. */
export default function DemoBadge() {
  return (
    <span className="inline-flex items-center gap-1 whitespace-nowrap rounded-full border border-dashed border-violet-300 bg-violet-50 px-2.5 py-0.5 text-xs font-medium text-violet-700">
      <GraduationCap size={12} aria-hidden /> สาธิต
    </span>
  );
}
