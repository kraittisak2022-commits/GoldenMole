import { canAccessSite } from './siteAccess';

describe('canAccessSite photo', () => {
  it('lets SuperAdmin and Admin in by default, not Assistant', () => {
    expect(canAccessSite({ role: 'SuperAdmin' }, 'photo')).toBe(true);
    expect(canAccessSite({ role: 'Admin', allowed_apps: null }, 'photo')).toBe(true);
    expect(canAccessSite({ role: 'Assistant' }, 'photo')).toBe(false);
  });

  it('follows the explicit list', () => {
    expect(canAccessSite({ role: 'Assistant', allowed_apps: ['photo'] }, 'photo')).toBe(true);
    expect(canAccessSite({ role: 'SuperAdmin', allowed_apps: ['main'] }, 'photo')).toBe(false);
  });
});
