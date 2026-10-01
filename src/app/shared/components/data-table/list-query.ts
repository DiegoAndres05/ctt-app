/** Fixed list page size (FR-017). */
export const LIST_PAGE_SIZE = 20;

/** Pause before a search keystroke rewrites the query string. */
export const LIST_SEARCH_DEBOUNCE_MS = 300;

export interface ListQuery {
  q: string;
  page: number;
  role: string;
  status: string;
  publicStatus: string;
  placement: string;
  categoryId: string;
}

export function emptyListQuery(): ListQuery {
  return {
    q: '',
    page: 1,
    role: '',
    status: '',
    publicStatus: '',
    placement: '',
    categoryId: '',
  };
}

/** Reads the shared list contract from a router `ParamMap`. */
export function parseListQuery(params: { get(name: string): string | null }): ListQuery {
  const pageRaw = Number(params.get('page') ?? '1');
  const page = Number.isFinite(pageRaw) && pageRaw >= 1 ? Math.floor(pageRaw) : 1;
  return {
    q: (params.get('q') ?? '').trim(),
    page,
    role: params.get('role') ?? '',
    status: params.get('status') ?? '',
    publicStatus: params.get('publicStatus') ?? '',
    placement: params.get('placement') ?? '',
    categoryId: params.get('categoryId') ?? '',
  };
}

/** Omits defaults so a shared link only carries what the user changed. */
export function listQueryToParams(query: ListQuery): Record<string, string> {
  const params: Record<string, string> = {};
  if (query.q) {
    params['q'] = query.q;
  }
  if (query.page > 1) {
    params['page'] = String(query.page);
  }
  if (query.role) {
    params['role'] = query.role;
  }
  if (query.status) {
    params['status'] = query.status;
  }
  if (query.publicStatus) {
    params['publicStatus'] = query.publicStatus;
  }
  if (query.placement) {
    params['placement'] = query.placement;
  }
  if (query.categoryId) {
    params['categoryId'] = query.categoryId;
  }
  return params;
}

const FILTER_KEYS = [
  'q',
  'role',
  'status',
  'publicStatus',
  'placement',
  'categoryId',
] as const satisfies readonly (keyof ListQuery)[];

/** Changing a search or filter returns to the first page unless `page` is set explicitly. */
export function withListFilterChange(query: ListQuery, patch: Partial<ListQuery>): ListQuery {
  const next: ListQuery = { ...query, ...patch };
  const changed = FILTER_KEYS.some((key) => patch[key] !== undefined && patch[key] !== query[key]);
  if (changed && patch.page === undefined) {
    next.page = 1;
  }
  return next;
}

export function hasActiveListFilters(query: ListQuery): boolean {
  return Boolean(
    query.q ||
      query.role ||
      query.status ||
      query.publicStatus ||
      query.placement ||
      query.categoryId,
  );
}

export function pageCount(total: number, pageSize = LIST_PAGE_SIZE): number {
  if (total <= 0) {
    return 1;
  }
  return Math.ceil(total / pageSize);
}

export function pageSlice<T>(rows: readonly T[], page: number, pageSize = LIST_PAGE_SIZE): T[] {
  const start = (Math.max(1, page) - 1) * pageSize;
  return rows.slice(start, start + pageSize);
}

export function debounce<T extends (...args: never[]) => void>(
  fn: T,
  waitMs: number,
): T & { cancel: () => void } {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const wrapped = ((...args: Parameters<T>) => {
    if (timer) {
      clearTimeout(timer);
    }
    timer = setTimeout(() => fn(...args), waitMs);
  }) as T & { cancel: () => void };
  wrapped.cancel = () => {
    if (timer) {
      clearTimeout(timer);
    }
  };
  return wrapped;
}
