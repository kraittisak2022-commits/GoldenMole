import { describe, expect, it } from 'vitest';
import { canAccessSite, effectiveSites, SITES } from './siteAccess';

describe('site access', () => {
    it('falls back to role defaults when no list is set', () => {
        expect(canAccessSite({ role: 'Assistant' }, 'main')).toBe(true);
        expect(canAccessSite({ role: 'Assistant', allowedApps: null }, 'order')).toBe(false);
        expect(canAccessSite({ role: 'Admin' }, 'order')).toBe(true);
        expect(canAccessSite({ role: 'Admin' }, 'flowaccount')).toBe(false);
        expect(canAccessSite({ role: 'SuperAdmin' }, 'flowaccount')).toBe(true);
    });

    it('uses the explicit list over the role', () => {
        expect(canAccessSite({ role: 'SuperAdmin', allowedApps: ['order'] }, 'main')).toBe(false);
        expect(canAccessSite({ role: 'Assistant', allowedApps: ['order'] }, 'order')).toBe(true);
        expect(canAccessSite({ role: 'Admin', allowedApps: [] }, 'main')).toBe(false);
    });

    it('lists the sites an account can use, in display order', () => {
        expect(SITES.map(s => s.key)).toEqual(['main', 'order', 'flowaccount']);
        expect(effectiveSites({ role: 'Admin' })).toEqual(['main', 'order']);
        expect(effectiveSites({ role: 'Admin', allowedApps: ['flowaccount', 'main'] })).toEqual(['main', 'flowaccount']);
    });
});
