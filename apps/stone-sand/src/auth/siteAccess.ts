import type { AdminRole } from './session';

/** Copy of src/utils/siteAccess.ts in the main app — keep the rule in sync. */
export type SiteKey = 'main' | 'order' | 'flowaccount';

const ROLE_DEFAULTS: Record<SiteKey, AdminRole[]> = {
  main: ['SuperAdmin', 'Admin', 'Assistant'],
  order: ['SuperAdmin', 'Admin'],
  flowaccount: ['SuperAdmin'],
};

export function canAccessSite(user: { role: AdminRole; allowed_apps?: string[] | null }, site: SiteKey): boolean {
  if (Array.isArray(user.allowed_apps)) return user.allowed_apps.includes(site);
  return ROLE_DEFAULTS[site].includes(user.role);
}
