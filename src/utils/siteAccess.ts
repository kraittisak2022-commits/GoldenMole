import type { AdminRole, OrderSourceLimit } from '../types';

/** admin_users.order_source — which ออเดอร์หิน-ทราย orders the account sees; read by apps/stone-sand. */
export const ORDER_SOURCE_OPTIONS: { value: OrderSourceLimit | null; label: string }[] = [
    { value: null, label: 'ทั้งหมด' },
    { value: 'shop', label: 'เฉพาะร้านวัสดุก่อสร้าง' },
    { value: 'pit', label: 'เฉพาะท่าทราย' },
];

export function parseOrderSourceLimit(raw: unknown): OrderSourceLimit | null {
    return raw === 'shop' || raw === 'pit' ? raw : null;
}

export type SiteKey = 'main' | 'order' | 'flowaccount';

export const SITES: { key: SiteKey; label: string; host: string }[] = [
    { key: 'main', label: 'ระบบหลัก', host: 'goldenmole.pro' },
    { key: 'order', label: 'ออเดอร์หิน-ทราย', host: 'order.goldenmole.pro' },
    { key: 'flowaccount', label: 'FlowAccount', host: 'flowaccount.goldenmole.pro' },
];

/** Same rule is copied into apps/stone-sand and apps/flowaccount (src/auth/siteAccess.ts). */
const ROLE_DEFAULTS: Record<SiteKey, AdminRole[]> = {
    main: ['SuperAdmin', 'Admin', 'Assistant'],
    order: ['SuperAdmin', 'Admin'],
    flowaccount: ['SuperAdmin'],
};

export interface SiteAccessSubject {
    role: AdminRole;
    allowedApps?: string[] | null;
}

export function canAccessSite(user: SiteAccessSubject, site: SiteKey): boolean {
    if (Array.isArray(user.allowedApps)) return user.allowedApps.includes(site);
    return ROLE_DEFAULTS[site].includes(user.role);
}

export function effectiveSites(user: SiteAccessSubject): SiteKey[] {
    return SITES.map(s => s.key).filter(key => canAccessSite(user, key));
}
