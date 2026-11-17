import { parseBlocks, type BlogBlock } from './blog-blocks';

/**
 * Panel-side types for the blog (spec 013, contracts/management.md). The backend is the
 * authority; these parsers only guard the UI against malformed responses.
 */

export type BlogArticleStatus = 'draft' | 'published' | 'retired';
export type BlogLocale = 'es' | 'en';

export const BLOG_LOCALES: readonly BlogLocale[] = ['es', 'en'];

export const BLOG_LOCALE_LABELS: Readonly<Record<BlogLocale, string>> = {
  es: 'Español',
  en: 'Inglés',
};

export const BLOG_STATUS_LABELS: Readonly<Record<BlogArticleStatus, string>> = {
  draft: 'Borrador',
  published: 'Publicado',
  retired: 'Retirado',
};

/** Field limits, same as the CHECK constraints of blog_article_contents (FR-006). */
export const BLOG_LIMITS = {
  title: 120,
  summary: 300,
  coverAlt: 250,
  seoTitle: 70,
  seoDescription: 160,
  slug: 120,
} as const;

export const BLOG_SLUG_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;

export interface BlogArticleSummary {
  id: string;
  slug: string;
  status: BlogArticleStatus;
  hasPendingChanges: boolean;
  completeLocales: BlogLocale[];
  title: string | null;
  firstPublishedAt: string | null;
  updatedAt: string;
  migrated: boolean;
  revision: number;
}

export interface BlogLocaleContent {
  title: string | null;
  summary: string | null;
  coverAlt: string | null;
  body: BlogBlock[];
  seoTitle: string | null;
  seoDescription: string | null;
}

export interface BlogContent {
  coverRef: string | null;
  updatedAt: string | null;
  es: BlogLocaleContent;
  en: BlogLocaleContent;
}

export interface BlogPublishError {
  field: 'content' | 'cover' | 'title' | 'summary' | 'coverAlt' | 'body' | 'imageAlt' | string;
  locale: BlogLocale | null;
}

export const BLOG_FIELD_LABELS: Readonly<Record<string, string>> = {
  content: 'Contenido',
  cover: 'Portada',
  title: 'Título',
  summary: 'Resumen',
  coverAlt: 'Texto alternativo de la portada',
  body: 'Contenido del artículo',
  imageAlt: 'Texto alternativo de una imagen',
};

export interface BlogArticleDetail {
  id: string;
  slug: string;
  status: BlogArticleStatus;
  migrated: boolean;
  originalPublishedAt: string | null;
  firstPublishedAt: string | null;
  publicUpdatedAt: string | null;
  updatedAt: string;
  revision: number;
  requiredLocales: BlogLocale[];
  migrationOpen: boolean;
  working: BlogContent | null;
  published: BlogContent | null;
  publishErrors: BlogPublishError[];
}

export interface BlogArticleState {
  id: string;
  revision: number;
  status: BlogArticleStatus;
  hasPendingChanges: boolean;
  firstPublishedAt: string | null;
  publicUpdatedAt: string | null;
}

export interface BlogLocalePayload {
  title: string | null;
  summary: string | null;
  coverAlt: string | null;
  body: BlogBlock[];
  seoTitle: string | null;
  seoDescription: string | null;
}

export interface BlogSavePayload {
  id: string | null;
  expectedRevision: number | null;
  slug: string | null;
  coverRef: string | null;
  es: BlogLocalePayload;
  en: BlogLocalePayload;
  migrated?: boolean;
  originalPublishedAt?: string | null;
}

export interface BlogSourceItem {
  slug: string;
  articleId: string | null;
  published: boolean;
}

export interface BlogSource {
  migrationRequired: boolean;
  cutoverCompletedAt: string | null;
  markedAt: string | null;
  manifest: BlogSourceItem[];
  missing: string[];
}

// ---------------------------------------------------------------------------
// Parsers
// ---------------------------------------------------------------------------

type Json = Record<string, unknown>;

function asObject(value: unknown): Json {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error('Respuesta inesperada del servidor.');
  }
  return value as Json;
}

function str(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function status(value: unknown): BlogArticleStatus {
  return value === 'published' || value === 'retired' ? value : 'draft';
}

function locales(value: unknown): BlogLocale[] {
  return Array.isArray(value) ? value.filter((l): l is BlogLocale => l === 'es' || l === 'en') : [];
}

function localeContent(value: unknown): BlogLocaleContent {
  const json = typeof value === 'object' && value !== null ? (value as Json) : {};
  return {
    title: str(json['title']),
    summary: str(json['summary']),
    coverAlt: str(json['coverAlt']),
    body: parseBlocks(json['body']),
    seoTitle: str(json['seoTitle']),
    seoDescription: str(json['seoDescription']),
  };
}

export function parseBlogContent(value: unknown): BlogContent | null {
  if (value === null || value === undefined) {
    return null;
  }
  const json = asObject(value);
  return {
    coverRef: str(json['coverRef']),
    updatedAt: str(json['updatedAt']),
    es: localeContent(json['es']),
    en: localeContent(json['en']),
  };
}

export function parseBlogArticleSummary(value: unknown): BlogArticleSummary {
  const json = asObject(value);
  return {
    id: String(json['id']),
    slug: String(json['slug']),
    status: status(json['status']),
    hasPendingChanges: json['hasPendingChanges'] === true,
    completeLocales: locales(json['completeLocales']),
    title: str(json['title']),
    firstPublishedAt: str(json['firstPublishedAt']),
    updatedAt: String(json['updatedAt']),
    migrated: json['migrated'] === true,
    revision: Number(json['revision']),
  };
}

export function parsePublishErrors(value: unknown): BlogPublishError[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .filter((item): item is Json => typeof item === 'object' && item !== null)
    .map((item) => ({
      field: String(item['field']),
      locale: item['locale'] === 'es' || item['locale'] === 'en' ? item['locale'] : null,
    }));
}

export function parseBlogArticleDetail(value: unknown): BlogArticleDetail {
  const json = asObject(value);
  return {
    id: String(json['id']),
    slug: String(json['slug']),
    status: status(json['status']),
    migrated: json['migrated'] === true,
    originalPublishedAt: str(json['originalPublishedAt']),
    firstPublishedAt: str(json['firstPublishedAt']),
    publicUpdatedAt: str(json['publicUpdatedAt']),
    updatedAt: String(json['updatedAt']),
    revision: Number(json['revision']),
    requiredLocales: locales(json['requiredLocales']),
    migrationOpen: json['migrationOpen'] === true,
    working: parseBlogContent(json['working']),
    published: parseBlogContent(json['published']),
    publishErrors: parsePublishErrors(json['publishErrors']),
  };
}

export function parseBlogArticleState(value: unknown): BlogArticleState {
  const json = asObject(value);
  return {
    id: String(json['id']),
    revision: Number(json['revision']),
    status: status(json['status']),
    hasPendingChanges: json['hasPendingChanges'] === true,
    firstPublishedAt: str(json['firstPublishedAt']),
    publicUpdatedAt: str(json['publicUpdatedAt']),
  };
}

export function parseBlogSource(value: unknown): BlogSource {
  const json = asObject(value);
  const manifest = Array.isArray(json['manifest']) ? json['manifest'] : [];
  return {
    migrationRequired: json['migrationRequired'] === true,
    cutoverCompletedAt: str(json['cutoverCompletedAt']),
    markedAt: str(json['markedAt']),
    manifest: manifest
      .filter((item): item is Json => typeof item === 'object' && item !== null)
      .map((item) => ({
        slug: String(item['slug']),
        articleId: str(item['articleId']),
        published: item['published'] === true,
      })),
    missing: Array.isArray(json['missing']) ? json['missing'].map(String) : [],
  };
}

/** Proposed slug from a title, same rule as `blog_slugify` in the database. */
export function slugify(title: string): string {
  const base = title
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 110)
    .replace(/-+$/g, '');
  return base || 'articulo';
}
