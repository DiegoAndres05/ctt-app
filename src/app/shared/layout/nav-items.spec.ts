import { activeNavItemId, parentIdsForActive, visibleNavItems, type NavItem } from './nav-items';

function ids(items: readonly NavItem[]): string[] {
  return items.flatMap((item) => [item.id, ...(item.children ? ids(item.children) : [])]);
}

describe('visibleNavItems', () => {
  it('shows the full tree to an admin', () => {
    expect(ids(visibleNavItems('admin'))).toEqual([
      'dashboard',
      'sales',
      'sales-requests',
      'sales-pre-reservations',
      'sales-quotations',
      'sales-verification',
      'sales-customers',
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
    expect(visible).toContain('sales-requests');
    expect(visible).toContain('sales-pre-reservations');
    expect(visible).toContain('sales-quotations');
    expect(visible).toContain('sales-verification');
    expect(visible).toContain('sales-customers');
  });

  it('hides Configuración and catalog settings from an agent', () => {
    expect(ids(visibleNavItems('agent'))).toEqual([
      'dashboard',
      'sales',
      'sales-requests',
      'sales-pre-reservations',
      'sales-quotations',
      'sales-customers',
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
    expect(activeNavItemId(items, '/sales/requests/abc')).toBe('sales-requests');
    expect(activeNavItemId(items, '/sales/pre-reservations/abc')).toBe('sales-pre-reservations');
    expect(activeNavItemId(items, '/sales/quotations/abc')).toBe('sales-quotations');
    expect(activeNavItemId(items, '/sales/verification')).toBe('sales-verification');
    expect(activeNavItemId(items, '/sales/customers/abc')).toBe('sales-customers');
  });

  it('does not treat a sibling path as active', () => {
    expect(activeNavItemId(items, '/cms/accommodations')).toBe('accommodations');
    expect(activeNavItemId(items, '/settings/audit')).not.toBe('users');
  });

  it('keeps the parent group of the active child', () => {
    expect(parentIdsForActive(items, 'experiences')).toEqual(['cms']);
    expect(parentIdsForActive(items, 'audit')).toEqual(['settings']);
    expect(parentIdsForActive(items, 'dashboard')).toEqual([]);
    expect(parentIdsForActive(items, 'sales-requests')).toEqual(['sales']);
    expect(parentIdsForActive(items, 'sales-pre-reservations')).toEqual(['sales']);
    expect(parentIdsForActive(items, 'sales-verification')).toEqual(['sales']);
    expect(parentIdsForActive(items, 'sales-customers')).toEqual(['sales']);
  });
});
