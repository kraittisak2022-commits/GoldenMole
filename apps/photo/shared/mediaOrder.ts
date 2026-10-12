interface Orderable {
  takenAt?: string | null;
  createdAt?: string;
  taken_at?: string | null;
  created_at?: string;
}

const timeOf = (m: Orderable) => Date.parse(m.takenAt ?? m.taken_at ?? m.createdAt ?? m.created_at ?? '') || 0;
const createdOf = (m: Orderable) => m.createdAt ?? m.created_at ?? '';

/** Oldest capture first, like an album in Google Photos; undated files fall back to upload time. */
export function sortMedia<T extends Orderable>(media: T[]): T[] {
  return [...media].sort((a, b) => timeOf(a) - timeOf(b) || createdOf(a).localeCompare(createdOf(b)));
}
