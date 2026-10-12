import {
  LIST_SEARCH_DEBOUNCE_MS,
  debounce,
  emptyListQuery,
  hasActiveListFilters,
  listQueryToParams,
  pageSlice,
  parseListQuery,
  withListFilterChange,
} from './list-query';

describe('parseListQuery / listQueryToParams', () => {
  it('round-trips a shared list link', () => {
    const params = parseListQuery({
      get: (name) =>
        ({
          q: '  snorkel ',
          page: '2',
          role: 'operator',
          status: 'active',
          publicStatus: 'published',
          placement: 'yacht',
          categoryId: 'cat-1',
        })[name] ?? null,
    });

    expect(params.q).toBe('snorkel');
    expect(params.page).toBe(2);
    expect(listQueryToParams(params)).toEqual({
      q: 'snorkel',
      page: '2',
      role: 'operator',
      status: 'active',
      publicStatus: 'published',
      placement: 'yacht',
      categoryId: 'cat-1',
    });
  });

  it('drops defaults and rejects an invalid page', () => {
    const params = parseListQuery({ get: (name) => (name === 'page' ? '0' : null) });
    expect(params).toEqual(emptyListQuery());
    expect(listQueryToParams(params)).toEqual({});
    expect(hasActiveListFilters(params)).toBe(false);
  });
});

describe('withListFilterChange', () => {
  it('resets the page when a filter changes', () => {
    const current = { ...emptyListQuery(), page: 4, q: 'mar' };
    expect(withListFilterChange(current, { status: 'draft' }).page).toBe(1);
    expect(withListFilterChange(current, { q: 'mar' }).page).toBe(4);
    expect(withListFilterChange(current, { page: 3 }).page).toBe(3);
    expect(withListFilterChange(current, { channel: 'web' }).page).toBe(1);
    expect(withListFilterChange(current, { assignee: 'none' }).page).toBe(1);
  });

  it('parses channel and assignee and omits them when empty', () => {
    const params = parseListQuery({
      get: (name) => ({ channel: 'whatsapp', assignee: 'none', page: '1' })[name] ?? null,
    });
    expect(params.channel).toBe('whatsapp');
    expect(params.assignee).toBe('none');
    expect(listQueryToParams(params)).toEqual({ channel: 'whatsapp', assignee: 'none' });
    expect(hasActiveListFilters(params)).toBe(true);
    expect(listQueryToParams(emptyListQuery())).toEqual({});
  });

  it('parses providerId and group and omits them when empty', () => {
    const params = parseListQuery({
      get: (name) => ({ providerId: 'prov-1', group: 'provider', page: '1' })[name] ?? null,
    });
    expect(params.providerId).toBe('prov-1');
    expect(params.group).toBe('provider');
    expect(listQueryToParams(params)).toEqual({ providerId: 'prov-1', group: 'provider' });
    expect(hasActiveListFilters(params)).toBe(true);
    expect(hasActiveListFilters({ ...emptyListQuery(), group: '' })).toBe(false);
  });

  it('resets the page when providerId or group changes', () => {
    const current = { ...emptyListQuery(), page: 4, providerId: 'prov-1', group: 'provider' };
    expect(withListFilterChange(current, { providerId: 'prov-2' }).page).toBe(1);
    expect(withListFilterChange(current, { group: '' }).page).toBe(1);
    expect(withListFilterChange(current, { providerId: 'prov-1' }).page).toBe(4);
    expect(withListFilterChange(current, { group: 'provider' }).page).toBe(4);
  });
});

describe('pageSlice', () => {
  it('returns 20 rows for the requested page', () => {
    const rows = Array.from({ length: 45 }, (_, index) => index + 1);
    expect(pageSlice(rows, 1)).toEqual(rows.slice(0, 20));
    expect(pageSlice(rows, 3)).toEqual(rows.slice(40, 45));
  });
});

describe('debounce', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('fires once after the list search pause', () => {
    vi.useFakeTimers();
    const seen: string[] = [];
    const commit = debounce((value: string) => seen.push(value), LIST_SEARCH_DEBOUNCE_MS);
    commit('a');
    commit('ab');
    vi.advanceTimersByTime(LIST_SEARCH_DEBOUNCE_MS - 1);
    expect(seen).toEqual([]);
    vi.advanceTimersByTime(1);
    expect(seen).toEqual(['ab']);
    expect(LIST_SEARCH_DEBOUNCE_MS).toBe(300);
  });
});
