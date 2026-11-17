import {
  isBodyEmpty,
  parseInlineMarkup,
  serializeInlineMarkup,
  type InlineRun,
} from '../../../core/blog/models/blog-blocks';
import {
  fromEditorBlocks,
  newBlock,
  type LocaleDraft,
  type LocaleField,
} from './blog-editor.model';

/**
 * Machine translation of one locale of a blog article into the other (spec 017, research R3).
 *
 * Each text becomes a minimal HTML segment with only `<b>`, `<i>` and `<a id="N">`. Link URLs are
 * never sent: they are replaced by their index and restored from the source runs. The result is
 * rebuilt with a strict tokenizer; if the marks of a segment come back different, that segment is
 * translated again run by run as plain text, so the structure is always preserved (FR-003).
 */

export type TranslationMode = 'fill' | 'replace';

/** Sends segments to the translator and returns them translated, same length and order. */
export type TranslateFn = (segments: string[]) => Promise<string[]>;

/** Size of one request; the Edge Function and the quota RPC enforce the same caps. */
export const TRANSLATION_PART_SEGMENTS = 40;
export const TRANSLATION_PART_CHARACTERS = 5000;

/** Splits segments into parts within the caps; a segment never spans two parts. */
export function splitIntoParts(segments: readonly string[]): string[][] {
  const parts: string[][] = [];
  let current: string[] = [];
  let size = 0;
  for (const segment of segments) {
    if (
      current.length > 0 &&
      (current.length >= TRANSLATION_PART_SEGMENTS ||
        size + segment.length > TRANSLATION_PART_CHARACTERS)
    ) {
      parts.push(current);
      current = [];
      size = 0;
    }
    current.push(segment);
    size += segment.length;
  }
  if (current.length > 0) {
    parts.push(current);
  }
  return parts;
}

/**
 * Wraps a one-request translator so long inputs go as sequential parts. `onProgress` gets
 * (parts done, total parts) before each part and at the end.
 */
export function inParts(
  translate: TranslateFn,
  onProgress: (done: number, total: number) => void = () => undefined,
): TranslateFn {
  return async (segments) => {
    const parts = splitIntoParts(segments);
    const out: string[] = [];
    for (const [index, part] of parts.entries()) {
      onProgress(index, parts.length);
      out.push(...(await translate(part)));
    }
    onProgress(parts.length, parts.length);
    return out;
  };
}

export const TRANSLATABLE_FIELDS: readonly LocaleField[] = [
  'title',
  'summary',
  'coverAlt',
  'seoTitle',
  'seoDescription',
];

type Slot =
  | { kind: 'field'; field: LocaleField }
  | { kind: 'text'; block: number }
  | { kind: 'item'; block: number; item: number }
  | { kind: 'alt'; block: number };

interface Segment {
  slot: Slot;
  runs: InlineRun[];
}

type Mark = 'b' | 'i' | `a${number}`;

// ---------------------------------------------------------------------------
// HTML segments
// ---------------------------------------------------------------------------

function escapeHtml(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function decodeEntities(text: string): string {
  return text.replace(/&(amp|lt|gt|quot|#39|nbsp);/gi, (_, name: string) => {
    switch (name.toLowerCase()) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'nbsp':
        return ' ';
      default:
        return "'";
    }
  });
}

function markOf(run: InlineRun, linkIndex: number): Mark | null {
  if (run.href) {
    return `a${linkIndex}`;
  }
  if (run.bold) {
    return 'b';
  }
  if (run.italic) {
    return 'i';
  }
  return null;
}

/** Marks of the source runs in order; links are numbered by position. */
function marksOf(runs: readonly InlineRun[]): Mark[] {
  const marks: Mark[] = [];
  let links = 0;
  for (const run of runs) {
    const mark = markOf(run, links);
    if (run.href) {
      links++;
    }
    if (mark) {
      marks.push(mark);
    }
  }
  return marks;
}

export function toSegmentHtml(runs: readonly InlineRun[]): string {
  let links = 0;
  return runs
    .map((run) => {
      const text = escapeHtml(run.text);
      if (run.href) {
        return `<a id="${links++}">${text}</a>`;
      }
      if (run.bold) {
        return `<b>${text}</b>`;
      }
      if (run.italic) {
        return `<i>${text}</i>`;
      }
      return text;
    })
    .join('');
}

const TAG = /<b>|<\/b>|<i>|<\/i>|<a id="(\d+)">|<\/a>/g;

/**
 * Rebuilds the runs of a translated segment. Returns null when the marks differ from the source
 * (missing, extra, reordered or nested tags), which triggers the run-by-run fallback.
 */
export function parseSegmentHtml(html: string, source: readonly InlineRun[]): InlineRun[] | null {
  const hrefs = source.filter((run) => run.href).map((run) => run.href as string);
  const runs: InlineRun[] = [];
  const marks: Mark[] = [];
  let open: Mark | null = null;
  let buffer = '';
  let last = 0;

  const flush = (): boolean => {
    const text = decodeEntities(buffer);
    buffer = '';
    if (open === null) {
      if (text) {
        runs.push({ text });
      }
      return true;
    }
    if (!text.trim()) {
      return false;
    }
    if (open === 'b') {
      runs.push({ text, bold: true });
    } else if (open === 'i') {
      runs.push({ text, italic: true });
    } else {
      const href = hrefs[Number(open.slice(1))];
      if (!href) {
        return false;
      }
      runs.push({ text, href });
    }
    return true;
  };

  for (const match of html.matchAll(TAG)) {
    buffer += html.slice(last, match.index);
    last = (match.index ?? 0) + match[0].length;
    const tag = match[0];
    if (tag.startsWith('</')) {
      const closing: string = tag === '</a>' ? 'a' : tag[2];
      if (open === null || open[0] !== closing || !flush()) {
        return null;
      }
      marks.push(open);
      open = null;
    } else {
      if (open !== null) {
        return null;
      }
      flush();
      open = tag === '<b>' ? 'b' : tag === '<i>' ? 'i' : (`a${match[1]}` as Mark);
    }
  }
  if (open !== null) {
    return null;
  }
  buffer += html.slice(last);
  flush();

  const expected = marksOf(source);
  if (expected.length !== marks.length || expected.some((mark, i) => mark !== marks[i])) {
    return null;
  }
  return runs;
}

// ---------------------------------------------------------------------------
// Planning: which texts of the source go to which slots of the target
// ---------------------------------------------------------------------------

function hasRunText(runs: readonly InlineRun[]): boolean {
  return runs.some((run) => run.text.trim() !== '');
}

function listItems(itemsMarkup: string): string[] {
  return itemsMarkup
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line !== '');
}

/** True when the locale has no text and no image in its body. */
export function isLocaleBodyBlank(locale: LocaleDraft): boolean {
  const blocks = fromEditorBlocks(locale.blocks);
  return isBodyEmpty(blocks) && !blocks.some((block) => block.type === 'image');
}

/** True when the locale has something to translate. */
export function hasTranslatableText(locale: LocaleDraft): boolean {
  return (
    TRANSLATABLE_FIELDS.some((field) => locale[field].trim() !== '') ||
    !isBodyEmpty(fromEditorBlocks(locale.blocks)) ||
    locale.blocks.some((b) => b.type === 'image' && !b.decorative && b.alt.trim() !== '')
  );
}

/** True when any field or the body of the target already has text (FR-008). */
export function hasExistingText(locale: LocaleDraft): boolean {
  return (
    TRANSLATABLE_FIELDS.some((field) => locale[field].trim() !== '') || !isLocaleBodyBlank(locale)
  );
}

function bodySegments(source: LocaleDraft): Segment[] {
  const segments: Segment[] = [];
  source.blocks.forEach((block, index) => {
    switch (block.type) {
      case 'paragraph':
      case 'heading':
      case 'quote': {
        const runs = parseInlineMarkup(block.markup);
        if (hasRunText(runs)) {
          segments.push({ slot: { kind: 'text', block: index }, runs });
        }
        break;
      }
      case 'list':
        listItems(block.itemsMarkup).forEach((item, itemIndex) => {
          const runs = parseInlineMarkup(item);
          if (hasRunText(runs)) {
            segments.push({ slot: { kind: 'item', block: index, item: itemIndex }, runs });
          }
        });
        break;
      case 'image':
        if (!block.decorative && block.alt.trim()) {
          segments.push({
            slot: { kind: 'alt', block: index },
            runs: [{ text: block.alt.trim() }],
          });
        }
        break;
    }
  });
  return segments;
}

interface Plan {
  segments: Segment[];
  includeBody: boolean;
}

function plan(source: LocaleDraft, target: LocaleDraft, mode: TranslationMode): Plan {
  const segments: Segment[] = [];
  for (const field of TRANSLATABLE_FIELDS) {
    const text = source[field].trim();
    if (text && (mode === 'replace' || target[field].trim() === '')) {
      segments.push({ slot: { kind: 'field', field }, runs: [{ text }] });
    }
  }
  const sourceHasBody = source.blocks.some((block) => {
    const one = fromEditorBlocks([block]);
    return one.length > 0 && (!isBodyEmpty(one) || one[0].type === 'image');
  });
  const includeBody = sourceHasBody && (mode === 'replace' || isLocaleBodyBlank(target));
  if (includeBody) {
    segments.push(...bodySegments(source));
  }
  return { segments, includeBody };
}

// ---------------------------------------------------------------------------
// Translation with fallback
// ---------------------------------------------------------------------------

/** Keeps the source's leading and trailing spaces, which translators drop on short texts. */
function keepSpacing(source: string, translated: string): string {
  const lead = /^\s*/.exec(source)?.[0] ?? '';
  const trail = /\s*$/.exec(source)?.[0] ?? '';
  return lead + translated.trim() + trail;
}

async function translateRunByRun(
  failed: readonly Segment[],
  translate: TranslateFn,
): Promise<InlineRun[][]> {
  const texts: string[] = [];
  for (const segment of failed) {
    for (const run of segment.runs) {
      if (run.text.trim()) {
        texts.push(escapeHtml(run.text.trim()));
      }
    }
  }
  const translated = texts.length > 0 ? await translate(texts) : [];
  let cursor = 0;
  return failed.map((segment) =>
    segment.runs.map((run) => {
      if (!run.text.trim()) {
        return { ...run };
      }
      const text = decodeEntities((translated[cursor++] ?? '').replace(TAG, ''));
      return { ...run, text: keepSpacing(run.text, text) };
    }),
  );
}

async function translateSegments(
  segments: readonly Segment[],
  translate: TranslateFn,
): Promise<InlineRun[][]> {
  if (segments.length === 0) {
    return [];
  }
  const translated = await translate(segments.map((segment) => toSegmentHtml(segment.runs)));
  const results: (InlineRun[] | null)[] = segments.map((segment, i) =>
    parseSegmentHtml(translated[i] ?? '', segment.runs),
  );
  const failedIndexes = results.flatMap((result, i) => (result === null ? [i] : []));
  if (failedIndexes.length > 0) {
    const retried = await translateRunByRun(
      failedIndexes.map((i) => segments[i]),
      translate,
    );
    failedIndexes.forEach((index, i) => (results[index] = retried[i]));
  }
  return results as InlineRun[][];
}

function plainText(runs: readonly InlineRun[]): string {
  return runs
    .map((run) => run.text)
    .join('')
    .trim();
}

/**
 * Translates `source` into a new version of `target`. All or nothing (FR-006): it either resolves
 * with the complete new locale or rejects without side effects. `translate` receives every
 * segment at once (wrap it with {@link inParts}); a second call happens only for the run-by-run
 * fallback.
 */
export async function translateLocale(
  source: LocaleDraft,
  target: LocaleDraft,
  mode: TranslationMode,
  translate: TranslateFn,
): Promise<LocaleDraft> {
  const { segments, includeBody } = plan(source, target, mode);
  const translated = await translateSegments(segments, translate);

  const next: LocaleDraft = { ...target };
  const bodyText = new Map<number, InlineRun[]>();
  const bodyItems = new Map<number, Map<number, InlineRun[]>>();
  const bodyAlt = new Map<number, string>();

  segments.forEach((segment, i) => {
    const runs = translated[i];
    const slot = segment.slot;
    switch (slot.kind) {
      case 'field':
        next[slot.field] = plainText(runs);
        break;
      case 'text':
        bodyText.set(slot.block, runs);
        break;
      case 'item': {
        const items = bodyItems.get(slot.block) ?? new Map<number, InlineRun[]>();
        items.set(slot.item, runs);
        bodyItems.set(slot.block, items);
        break;
      }
      case 'alt':
        bodyAlt.set(slot.block, plainText(runs));
        break;
    }
  });

  if (includeBody) {
    next.blocks = source.blocks.map((block, index) => {
      const copy = { ...newBlock(block.type, block.ref), level: block.level };
      copy.ordered = block.ordered;
      copy.decorative = block.decorative;
      switch (block.type) {
        case 'paragraph':
        case 'heading':
        case 'quote': {
          const runs = bodyText.get(index);
          copy.markup = runs ? serializeInlineMarkup(runs) : block.markup;
          break;
        }
        case 'list': {
          const items = bodyItems.get(index);
          copy.itemsMarkup = listItems(block.itemsMarkup)
            .map((item, itemIndex) => {
              const runs = items?.get(itemIndex);
              return runs ? serializeInlineMarkup(runs) : item;
            })
            .join('\n');
          break;
        }
        case 'image':
          copy.alt = block.decorative ? '' : (bodyAlt.get(index) ?? '');
          break;
      }
      return copy;
    });
  }
  return next;
}
