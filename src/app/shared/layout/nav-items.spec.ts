import {
  activeNavItemId,
  parentIdsForActive,
  visibleNavItems,
  type NavItem,
} from './nav-items';

function ids(items: readonly NavItem[]): string[] {
  return items.flatMap((item) => [item.id, ...(item.children ? ids(item.children) : [])]);
}

describe('visibleNavItems', () => {
  it('shows the full tree to an admin', () => {
    expect(ids(visibleNavItems('admin'))).toEqual([
      'dashboard',
      'settings',
      'users',
      'roles',
      'audit',
      'cms',
      'experiences',
      'accommodations',
      'packages',
      'cms-settings',
    ]);
  });

  it('hides Configuración from an operator and keeps CMS settings', () => {
    const visible = ids(visibleNavItems('operator'));
    expect(visible).not.toContain('settings');
    expect(visible).not.toContain('users');
    expect(visible).toContain('cms-settings');
    expect(visible).toContain('experiences');
  });

  it('hides Configuración and catalog settings from an agent', () => {
    expect(ids(visibleNavItems('agent'))).toEqual([
      'dashboard',
      'cms',
      'experiences',
      'accommodations',
      'packages',
    ]);
  });

  it('returns nothing without a role', () => {
    expect(visibleNavItems(null)).toEqual([]);
  });
});

describe('activeNavItemId', () => {
  const items = visibleNavItems('admin');

  it('highlights the longest matching prefix', () => {
    expect(activeNavItemId(items, '/cms/experiences/abc')).toBe('experiences');
    expect(activeNavItemId(items, '/cms/settings/addons?q=snorkel')).toBe('cms-settings');
    expect(activeNavItemId(items, '/settings/users/new')).toBe('users');
    expect(activeNavItemId(items, '/dashboard')).toBe('dashboard');
  });

  it('does not treat a sibling path as active', () => {
    expect(activeNavItemId(items, '/cms/accommodations')).toBe('accommodations');
    expect(activeNavItemId(items, '/settings/audit')).not.toBe('users');
  });

  it('keeps the parent group of the active child', () => {
    expect(parentIdsForActive(items, 'experiences')).toEqual(['cms']);
    expect(parentIdsForActive(items, 'audit')).toEqual(['settings']);
    expect(parentIdsForActive(items, 'dashboard')).toEqual([]);
  });
});
