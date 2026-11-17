import {
  parseInlineMarkup,
  serializeInlineMarkup,
  type BlogBlock,
  type BlogBlockType,
} from '../../../core/blog/models/blog-blocks';
import type {
  BlogContent,
  BlogLocale,
  BlogLocaleContent,
  BlogLocalePayload,
  BlogSavePayload,
} from '../../../core/blog/models/blog-article.model';

/**
 * Editor state of the blog article screen. Text blocks are edited as plain text with three
 * marks; lists as one item per line. Pasting into a textarea always inserts plain text.
 */

export interface EditorBlock {
  key: number;
  type: BlogBlockType;
  level: 2 | 3;
  markup: string;
  ordered: boolean;
  /** List items, one per line. */
  itemsMarkup: string;
  ref: string;
  alt: string;
  decorative: boolean;
}

export interface LocaleDraft {
  title: string;
  summary: string;
  coverAlt: string;
  seoTitle: string;
  seoDescription: string;
  blocks: EditorBlock[];
}

export type LocaleField = 'title' | 'summary' | 'coverAlt' | 'seoTitle' | 'seoDescription';

export interface ArticleDraft {
  slug: string;
  coverRef: string | null;
  es: LocaleDraft;
  en: LocaleDraft;
  migrated: boolean;
  /** yyyy-mm-dd, migrated articles only. */
  originalPublishedAt: string;
}

let nextKey = 1;

export function newBlock(type: BlogBlockType, ref = ''): EditorBlock {
  return {
    key: nextKey++,
    type,
    level: 2,
    markup: '',
    ordered: false,
    itemsMarkup: '',
    ref,
    alt: '',
    decorative: false,
  };
}

export function emptyLocale(): LocaleDraft {
  return {
    title: '',
    summary: '',
    coverAlt: '',
    seoTitle: '',
    seoDescription: '',
    blocks: [newBlock('paragraph')],
  };
}

export function emptyDraft(): ArticleDraft {
  return {
    slug: '',
    coverRef: null,
    es: emptyLocale(),
    en: emptyLocale(),
    migrated: false,
    originalPublishedAt: '',
  };
}

export function toEditorBlocks(blocks: readonly BlogBlock[]): EditorBlock[] {
  return blocks.map((block) => {
    const editor = newBlock(block.type);
    switch (block.type) {
      case 'paragraph':
      case 'quote':
        editor.markup = serializeInlineMarkup(block.text);
        break;
      case 'heading':
        editor.level = block.level;
        editor.markup = serializeInlineMarkup(block.text);
        break;
      case 'list':
        editor.ordered = block.ordered;
        editor.itemsMarkup = block.items.map(serializeInlineMarkup).join('\n');
        break;
      case 'image':
        editor.ref = block.ref;
        editor.alt = block.alt ?? '';
        editor.decorative = block.decorative;
        break;
    }
    return editor;
  });
}

export function fromEditorBlocks(blocks: readonly EditorBlock[]): BlogBlock[] {
  const out: BlogBlock[] = [];
  for (const block of blocks) {
    switch (block.type) {
      case 'paragraph':
      case 'quote':
        out.push({ type: block.type, text: parseInlineMarkup(block.markup) });
        break;
      case 'heading':
        out.push({ type: 'heading', level: block.level, text: parseInlineMarkup(block.markup) });
        break;
      case 'list': {
        const items = block.itemsMarkup
          .split('\n')
          .map((line) => line.trim())
          .filter((line) => line !== '')
          .map(parseInlineMarkup);
        if (items.length > 0) {
          out.push({ type: 'list', ordered: block.ordered, items });
        }
        break;
      }
      case 'image':
        if (block.ref) {
          out.push({
            type: 'image',
            ref: block.ref,
            alt: block.alt.trim() || null,
            decorative: block.decorative,
          });
        }
        break;
    }
  }
  return out;
}

function localeFrom(content: BlogLocaleContent): LocaleDraft {
  const blocks = toEditorBlocks(content.body);
  return {
    title: content.title ?? '',
    summary: content.summary ?? '',
    coverAlt: content.coverAlt ?? '',
    seoTitle: content.seoTitle ?? '',
    seoDescription: content.seoDescription ?? '',
    blocks: blocks.length > 0 ? blocks : [newBlock('paragraph')],
  };
}

export function draftFrom(
  slug: string,
  content: BlogContent | null,
  migrated: boolean,
): ArticleDraft {
  if (!content) {
    return { ...emptyDraft(), slug, migrated };
  }
  return {
    slug,
    coverRef: content.coverRef,
    es: localeFrom(content.es),
    en: localeFrom(content.en),
    migrated,
    originalPublishedAt: '',
  };
}

function nullable(value: string): string | null {
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function localePayload(locale: LocaleDraft): BlogLocalePayload {
  return {
    title: nullable(locale.title),
    summary: nullable(locale.summary),
    coverAlt: nullable(locale.coverAlt),
    body: fromEditorBlocks(locale.blocks),
    seoTitle: nullable(locale.seoTitle),
    seoDescription: nullable(locale.seoDescription),
  };
}

/** Builds the save payload. `id` null creates the article. */
export function toSavePayload(
  draft: ArticleDraft,
  id: string | null,
  revision: number | null,
): BlogSavePayload {
  const payload: BlogSavePayload = {
    id,
    expectedRevision: id ? revision : null,
    slug: nullable(draft.slug),
    coverRef: draft.coverRef,
    es: localePayload(draft.es),
    en: localePayload(draft.en),
  };
  if (!id && draft.migrated) {
    payload.migrated = true;
    payload.originalPublishedAt = draft.originalPublishedAt
      ? `${draft.originalPublishedAt}T12:00:00Z`
      : null;
  }
  return payload;
}

export function localeOf(draft: ArticleDraft, locale: BlogLocale): LocaleDraft {
  return locale === 'en' ? draft.en : draft.es;
}

/** JSON snapshot without the volatile block keys, for the unsaved-changes check. */
export function snapshotOf(draft: ArticleDraft): string {
  return JSON.stringify(toSavePayload(draft, null, null)) + draft.slug + draft.originalPublishedAt;
}
