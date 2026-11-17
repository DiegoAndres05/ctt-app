import { inject, Injectable } from '@angular/core';
import { toAppError, type AppError } from '../../error/error-handler';
import { AuthService } from '../../auth/services/auth.service';
import { SupabaseService } from '../../auth/services/supabase.service';
import {
  parseBlogArticleDetail,
  parseBlogArticleState,
  parseBlogArticleSummary,
  parseBlogSource,
  parsePublishErrors,
  type BlogArticleDetail,
  type BlogArticleState,
  type BlogArticleStatus,
  type BlogLocale,
  type BlogArticleSummary,
  type BlogPublishError,
  type BlogSavePayload,
  type BlogSource,
} from '../models/blog-article.model';

const CATALOG_MEDIA_BUCKET = 'catalog-media';
const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const IMAGE_TYPES: Readonly<Record<string, string>> = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/webp': 'webp',
};

/** An {@link AppError} that also carries the structured DETAIL of the RPC, when there is one. */
export interface BlogError extends AppError {
  publishErrors?: BlogPublishError[];
  missingSlugs?: string[];
  /** TRANSLATION_RATE_LIMITED: when the agency can translate again (ISO). */
  retryAt?: string | null;
}

/** The client gives up a little after the Edge Function's own 55 s translator timeout (FR-011). */
export const TRANSLATION_TIMEOUT_MS = 60_000;

/**
 * Blog articles and blog source (spec 013). The agency always comes from the session; the
 * SECURITY DEFINER RPCs re-check role and tenant, and RLS hides the tables from Agent.
 */
@Injectable({ providedIn: 'root' })
export class BlogService {
  private readonly supabase = inject(SupabaseService);
  private readonly auth = inject(AuthService);

  // -------------------------------------------------------------------------
  // Articles
  // -------------------------------------------------------------------------

  async listArticles(status?: BlogArticleStatus | null): Promise<BlogArticleSummary[]> {
    const data = await this.rpc<unknown>('list_blog_articles', { p_status: status ?? null });
    return Array.isArray(data) ? data.map(parseBlogArticleSummary) : [];
  }

  async getArticle(id: string): Promise<BlogArticleDetail> {
    return parseBlogArticleDetail(await this.rpc<unknown>('get_blog_article', { p_id: id }));
  }

  async saveArticle(payload: BlogSavePayload): Promise<BlogArticleState> {
    return parseBlogArticleState(
      await this.rpc<unknown>('save_blog_article', { p_payload: payload }),
    );
  }

  publishArticle(id: string, revision: number): Promise<BlogArticleState> {
    return this.transition('publish_blog_article', id, revision);
  }

  publishChanges(id: string, revision: number): Promise<BlogArticleState> {
    return this.transition('publish_blog_article_changes', id, revision);
  }

  discardChanges(id: string, revision: number): Promise<BlogArticleState> {
    return this.transition('discard_blog_article_changes', id, revision);
  }

  retire(id: string, revision: number): Promise<BlogArticleState> {
    return this.transition('retire_blog_article', id, revision);
  }

  republish(id: string, revision: number): Promise<BlogArticleState> {
    return this.transition('republish_blog_article', id, revision);
  }

  async deleteArticle(id: string, revision: number): Promise<void> {
    await this.rpc('delete_blog_article', { p_id: id, p_expected_revision: revision });
  }

  /**
   * Uploads an image into `{org}/blog/{articleId}/` of `catalog-media` and returns its storage
   * path. The article must exist first: the database only accepts refs inside its folder.
   */
  async uploadImage(articleId: string, file: File): Promise<string> {
    if (file.size > MAX_IMAGE_BYTES) {
      throw toAppError({ message: 'IMAGE_TOO_LARGE' });
    }
    const ext = IMAGE_TYPES[file.type.toLowerCase()];
    if (!ext) {
      throw toAppError({ message: 'IMAGE_TYPE_NOT_ALLOWED' });
    }
    const organizationId = this.auth.organizationId();
    if (!organizationId) {
      throw toAppError({ message: 'MISSING_TENANT_CONTEXT' });
    }

    const path = `${organizationId}/blog/${articleId}/${crypto.randomUUID()}.${ext}`;
    const { error } = await this.supabase.client.storage
      .from(CATALOG_MEDIA_BUCKET)
      .upload(path, file, { contentType: file.type, upsert: false });
    if (error) {
      throw toAppError(error);
    }
    return path;
  }

  mediaUrl(ref: string | null | undefined): string | null {
    if (!ref) {
      return null;
    }
    if (/^https:\/\//i.test(ref)) {
      return ref;
    }
    return this.supabase.client.storage.from(CATALOG_MEDIA_BUCKET).getPublicUrl(ref).data.publicUrl;
  }

  // -------------------------------------------------------------------------
  // Blog source and migration (Administrator)
  // -------------------------------------------------------------------------

  async getSource(): Promise<BlogSource> {
    return parseBlogSource(await this.rpc<unknown>('get_blog_source'));
  }

  async setMigrationRequired(required: boolean): Promise<BlogSource> {
    return parseBlogSource(
      await this.rpc<unknown>('set_blog_migration_required', { p_required: required }),
    );
  }

  async replaceManifest(slugs: string[]): Promise<BlogSource> {
    return parseBlogSource(
      await this.rpc<unknown>('replace_blog_cutover_manifest', { p_slugs: slugs }),
    );
  }

  async completeCutover(): Promise<BlogSource> {
    return parseBlogSource(await this.rpc<unknown>('complete_blog_cutover'));
  }

  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // Translation (spec 017)
  // -------------------------------------------------------------------------

  /**
   * Translates minimal-HTML segments through the `translate-blog` Edge Function, which checks
   * role and hourly quota and forwards to the self-hosted translator. Same length and order.
   */
  async translate(source: BlogLocale, target: BlogLocale, segments: string[]): Promise<string[]> {
    let result: { data: unknown; error: unknown };
    try {
      result = await this.supabase.client.functions.invoke('translate-blog', {
        body: { source, target, segments },
        timeout: TRANSLATION_TIMEOUT_MS,
      });
    } catch (failure) {
      throw toBlogError({ code: 'TRANSLATION_UNAVAILABLE', cause: failure });
    }
    if (result.error) {
      throw await translationError(result.error, result.data);
    }
    const translated = (result.data as { segments?: unknown } | null)?.segments;
    if (
      !Array.isArray(translated) ||
      translated.length !== segments.length ||
      !translated.every((item) => typeof item === 'string')
    ) {
      throw toBlogError({ code: 'TRANSLATION_UNAVAILABLE' });
    }
    return translated as string[];
  }

  private async transition(name: string, id: string, revision: number): Promise<BlogArticleState> {
    return parseBlogArticleState(
      await this.rpc<unknown>(name, { p_id: id, p_expected_revision: revision }),
    );
  }

  private async rpc<T>(name: string, args?: Record<string, unknown>): Promise<T> {
    const { data, error } = await this.supabase.client.rpc(name, args);
    if (error) {
      throw toBlogError(error);
    }
    return data as T;
  }
}

/** Maps an RPC failure, decoding the JSON DETAIL of PUBLISH_INCOMPLETE and BLOG_CUTOVER_INCOMPLETE. */
export function toBlogError(error: unknown): BlogError {
  const appError: BlogError = toAppError(error);
  const details = (error as { details?: unknown } | null)?.details;
  if (typeof details !== 'string') {
    return appError;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(details);
  } catch {
    return appError;
  }
  if (appError.code === 'PUBLISH_INCOMPLETE') {
    appError.publishErrors = parsePublishErrors(parsed);
  } else if (appError.code === 'BLOG_CUTOVER_INCOMPLETE' && Array.isArray(parsed)) {
    appError.missingSlugs = parsed.map(String);
  }
  return appError;
}

const TRANSLATION_CODES = new Set([
  'VALIDATION_ERROR',
  'SESSION_EXPIRED',
  'FORBIDDEN',
  'TRANSLATION_TOO_LARGE',
  'TRANSLATION_RATE_LIMITED',
  'TRANSLATION_UNAVAILABLE',
]);

/**
 * Reads the contract body of a failed `translate-blog` call. `functions.invoke` leaves the
 * Response on `error.context`; anything unreadable is TRANSLATION_UNAVAILABLE.
 */
export async function translationError(error: unknown, data: unknown): Promise<BlogError> {
  let body: unknown = data;
  if (!readCode(body) && typeof error === 'object' && error !== null && 'context' in error) {
    const context = (error as { context?: unknown }).context;
    if (context instanceof Response) {
      try {
        body = await context.clone().json();
      } catch {
        body = null;
      }
    }
  }
  const code = readCode(body) ?? 'TRANSLATION_UNAVAILABLE';
  const blogError: BlogError = toAppError({ code });
  if (code === 'TRANSLATION_RATE_LIMITED') {
    const retryAt = (body as { retryAt?: unknown }).retryAt;
    blogError.retryAt = typeof retryAt === 'string' ? retryAt : null;
  }
  return blogError;
}

function readCode(body: unknown): string | null {
  const code = (body as { code?: unknown } | null)?.code;
  return typeof code === 'string' && TRANSLATION_CODES.has(code) ? code : null;
}
