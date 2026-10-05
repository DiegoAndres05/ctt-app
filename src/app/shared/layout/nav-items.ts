import { hasRoleAtLeast, type AppRole } from '../../core/auth/models/user.model';

/**
 * Static navigation tree for the authenticated shell (feature 010).
 *
 * Visibility here is an affordance only. Every `path` is also protected by `roleGuard`
 * at an equal or stricter rank, and Row Level Security remains the data boundary.
 */
export interface NavItem {
  id: string;
  label: string;
  path: string | null;
  minRole: AppRole;
  adminOnly?: boolean;
  hideForAgent?: boolean;
  children?: NavItem[];
}

export const NAV_TREE: readonly NavItem[] = [
  {
    id: 'dashboard',
    label: 'Dashboard',
    path: '/dashboard',
    minRole: 'agent',
  },
  {
    id: 'sales',
    label: 'Comercial',
    path: null,
    minRole: 'agent',
    children: [
      {
        id: 'sales-requests',
        label: 'Solicitudes',
        path: '/sales/requests',
        minRole: 'agent',
      },
      {
        id: 'sales-customers',
        label: 'Clientes',
        path: '/sales/customers',
        minRole: 'agent',
      },
    ],
  },
  {
    id: 'settings',
    label: 'Configuración',
    path: null,
    minRole: 'admin',
    adminOnly: true,
    children: [
      {
        id: 'users',
        label: 'Usuarios',
        path: '/settings/users',
        minRole: 'admin',
        adminOnly: true,
      },
      {
        id: 'roles',
        label: 'Roles y permisos',
        path: '/settings/roles',
        minRole: 'admin',
        adminOnly: true,
      },
      {
        id: 'audit',
        label: 'Auditoría',
        path: '/settings/audit',
        minRole: 'admin',
        adminOnly: true,
      },
    ],
  },
  {
    id: 'cms',
    label: 'CMS',
    path: null,
    minRole: 'agent',
    children: [
      {
        id: 'experiences',
        label: 'Experiencias',
        path: '/cms/experiences',
        minRole: 'agent',
      },
      {
        id: 'accommodations',
        label: 'Alojamientos',
        path: '/cms/accommodations',
        minRole: 'agent',
      },
      {
        id: 'packages',
        label: 'Paquetes',
        path: '/cms/packages',
        minRole: 'agent',
      },
      {
        id: 'cms-settings',
        label: 'Ajustes del catálogo',
        path: '/cms/settings',
        minRole: 'operator',
        hideForAgent: true,
      },
    ],
  },
];

export function isNavItemVisible(item: NavItem, role: AppRole | null): boolean {
  if (!role) {
    return false;
  }
  if (item.adminOnly && role !== 'admin') {
    return false;
  }
  if (item.hideForAgent && role === 'agent') {
    return false;
  }
  return hasRoleAtLeast(role, item.minRole);
}

/** Role-filtered copy of the tree. Groups with no visible children are omitted. */
export function visibleNavItems(
  role: AppRole | null,
  items: readonly NavItem[] = NAV_TREE,
): NavItem[] {
  const visible: NavItem[] = [];
  for (const item of items) {
    if (!isNavItemVisible(item, role)) {
      continue;
    }
    if (!item.children) {
      visible.push({ ...item });
      continue;
    }
    const children = visibleNavItems(role, item.children);
    if (children.length === 0) {
      continue;
    }
    visible.push({ ...item, children });
  }
  return visible;
}

/** Longest menu path that is the current URL or a prefix of it. */
export function activeNavItemId(items: readonly NavItem[], url: string): string | null {
  const path = url.split('?')[0]?.split('#')[0] ?? '';
  let bestId: string | null = null;
  let bestLength = -1;

  const walk = (nodes: readonly NavItem[]): void => {
    for (const node of nodes) {
      if (node.path && pathMatches(path, node.path) && node.path.length > bestLength) {
        bestId = node.id;
        bestLength = node.path.length;
      }
      if (node.children) {
        walk(node.children);
      }
    }
  };

  walk(items);
  return bestId;
}

/** Ancestor group ids that should stay expanded for the active item. */
export function parentIdsForActive(items: readonly NavItem[], activeId: string | null): string[] {
  if (!activeId) {
    return [];
  }
  const found: string[] = [];
  const walk = (nodes: readonly NavItem[], parents: string[]): boolean => {
    for (const node of nodes) {
      if (node.id === activeId) {
        found.push(...parents);
        return true;
      }
      if (node.children && walk(node.children, [...parents, node.id])) {
        return true;
      }
    }
    return false;
  };
  walk(items, []);
  return found;
}

function pathMatches(urlPath: string, itemPath: string): boolean {
  return urlPath === itemPath || urlPath.startsWith(`${itemPath}/`);
}
