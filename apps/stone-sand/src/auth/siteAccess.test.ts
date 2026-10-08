import { canAccessSite } from './siteAccess';

describe('canAccessSite', () => {
  it('keeps the old role rule when no list is set', () => {
    expect(canAccessSite({ role: 'Admin', allowed_apps: null }, 'order')).toBe(true);
    expect(canAccessSite({ role: 'Assistant' }, 'order')).toBe(false);
  });

  it('follows the list when the SuperAdmin set one', () => {
    expect(canAccessSite({ role: 'Assistant', allowed_apps: ['order'] }, 'order')).toBe(true);
    expect(canAccessSite({ role: 'SuperAdmin', allowed_apps: ['main'] }, 'order')).toBe(false);
  });
});
