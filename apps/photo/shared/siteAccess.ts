import type { AdminRole } from './types';

/** Copy of src/utils/siteAccess.ts in the main app — keep the rule in sync. */
export type SiteKey = 'main' | 'order' | 'flowaccount' | 'photo';

const ROLE_DEFAULTS: Record<SiteKey, AdminRole[]> = {
  main: ['SuperAdmin', 'Admin', 'Assistant'],
  order: ['SuperAdmin', 'Admin'],
  flowaccount: ['SuperAdmin'],
  photo: ['SuperAdmin', 'Admin'],
};

export function canAccessSite(user: { role: AdminRole; allowed_apps?: string[] | null }, site: SiteKey): boolean {
  if (Array.isArray(user.allowed_apps)) return user.allowed_apps.includes(site);
  return ROLE_DEFAULTS[site].includes(user.role);
}
