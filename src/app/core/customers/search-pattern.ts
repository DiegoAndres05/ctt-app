const UNSAFE = /[,()*\\%:"']/g;

/**
 * Builds a PostgREST `or` filter from a free-text query.
 * Strips characters that would change the filter shape, collapses whitespace, and
 * caps the term at 80 characters. Phone columns search digits only.
 */
export function toSearchOrFilter(
  q: string,
  columns: readonly string[],
  phoneColumns: readonly string[] = [],
): string | null {
  const term = q.replace(UNSAFE, '').replace(/\s+/g, ' ').trim().slice(0, 80);
  if (!term) {
    return null;
  }

  const phones = new Set(phoneColumns);
  const digits = term.replace(/\D/g, '');
  const parts: string[] = [];

  for (const column of columns) {
    if (phones.has(column)) {
      continue;
    }
    parts.push(`${column}.ilike.*${term}*`);
  }

  if (digits) {
    for (const column of phoneColumns) {
      parts.push(`${column}.ilike.*${digits}*`);
    }
  }

  return parts.length > 0 ? parts.join(',') : null;
}
