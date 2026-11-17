import { TestBed } from '@angular/core/testing';
import { vi } from 'vitest';
import { AuthService } from '../../auth/services/auth.service';
import { SupabaseService } from '../../auth/services/supabase.service';
import { BlogService, toBlogError, translationError } from './blog.service';

function setup(
  rpc: ReturnType<typeof vi.fn>,
  upload = vi.fn(async () => ({ error: null })),
  invoke = vi.fn(),
) {
  TestBed.configureTestingModule({
    providers: [
      { provide: AuthService, useValue: { organizationId: () => 'org-1' } },
      {
        provide: SupabaseService,
        useValue: {
          client: {
            rpc,
            functions: { invoke },
            storage: {
              from: () => ({
                upload,
                getPublicUrl: (p: string) => ({ data: { publicUrl: `https://cdn/${p}` } }),
              }),
            },
          },
        },
      },
    ],
  });
  return { service: TestBed.inject(BlogService), upload };
}

describe('BlogService', () => {
  it('maps a stale save to ARTICLE_CONFLICT', async () => {
    const rpc = vi.fn(async () => ({
      data: null,
      error: { message: 'ARTICLE_CONFLICT', code: 'P0001' },
    }));
    const { service } = setup(rpc);
    await expect(
      service.saveArticle({
        id: 'a',
        expectedRevision: 1,
        slug: null,
        coverRef: null,
        es: {
          title: 'x',
          summary: null,
          coverAlt: null,
          body: [],
          seoTitle: null,
          seoDescription: null,
        },
        en: {
          title: null,
          summary: null,
          coverAlt: null,
          body: [],
          seoTitle: null,
          seoDescription: null,
        },
      }),
    ).rejects.toMatchObject({ code: 'ARTICLE_CONFLICT' });
  });

  it('maps a taken slug to SLUG_TAKEN, not to the listing PUBLIC_SLUG_TAKEN', () => {
    expect(toBlogError({ message: 'SLUG_TAKEN' }).code).toBe('SLUG_TAKEN');
    expect(toBlogError({ message: 'PUBLIC_SLUG_TAKEN' }).code).toBe('PUBLIC_SLUG_TAKEN');
  });

  it('decodes the per-language missing fields of PUBLISH_INCOMPLETE', async () => {
    const rpc = vi.fn(async () => ({
      data: null,
      error: {
        message: 'PUBLISH_INCOMPLETE',
        details: '[{"field":"title","locale":"en"},{"field":"cover","locale":null}]',
      },
    }));
    const { service } = setup(rpc);
    await expect(service.publishArticle('a', 3)).rejects.toMatchObject({
      code: 'PUBLISH_INCOMPLETE',
      publishErrors: [
        { field: 'title', locale: 'en' },
        { field: 'cover', locale: null },
      ],
    });
    expect(rpc).toHaveBeenCalledWith('publish_blog_article', { p_id: 'a', p_expected_revision: 3 });
  });

  it('decodes the missing slugs of BLOG_CUTOVER_INCOMPLETE', () => {
    expect(toBlogError({ message: 'BLOG_CUTOVER_INCOMPLETE', details: '["a","b"]' })).toMatchObject(
      {
        code: 'BLOG_CUTOVER_INCOMPLETE',
        missingSlugs: ['a', 'b'],
      },
    );
  });

  it('uploads into the agency and article folder', async () => {
    const { service, upload } = setup(vi.fn());
    const path = await service.uploadImage(
      'art-9',
      new File(['x'], 'foto.webp', { type: 'image/webp' }),
    );
    expect(path).toMatch(/^org-1\/blog\/art-9\/[0-9a-f-]{36}\.webp$/);
    expect(upload).toHaveBeenCalledOnce();
  });

  it('rejects a file type that is not allowed before uploading', async () => {
    const { service, upload } = setup(vi.fn());
    await expect(
      service.uploadImage('art-9', new File(['<svg/>'], 'x.svg', { type: 'image/svg+xml' })),
    ).rejects.toMatchObject({ code: 'IMAGE_TYPE_NOT_ALLOWED' });
    expect(upload).not.toHaveBeenCalled();
  });

  it('returns external migrated images as they are', () => {
    const { service } = setup(vi.fn());
    expect(service.mediaUrl('https://blog-anterior.example/x.jpg')).toBe(
      'https://blog-anterior.example/x.jpg',
    );
    expect(service.mediaUrl('org-1/blog/a/b.webp')).toBe('https://cdn/org-1/blog/a/b.webp');
  });

  it('translates through the translate-blog Edge Function', async () => {
    const invoke = vi.fn(async () => ({ data: { segments: ['Hello'] }, error: null }));
    const { service } = setup(vi.fn(), undefined, invoke);
    await expect(service.translate('es', 'en', ['Hola'])).resolves.toEqual(['Hello']);
    expect(invoke).toHaveBeenCalledWith('translate-blog', {
      body: { source: 'es', target: 'en', segments: ['Hola'] },
      timeout: 60_000,
    });
  });

  it('treats a malformed answer or a network failure as TRANSLATION_UNAVAILABLE', async () => {
    const bad = vi.fn(async () => ({ data: { segments: [] }, error: null }));
    await expect(
      setup(vi.fn(), undefined, bad).service.translate('es', 'en', ['a']),
    ).rejects.toMatchObject({ code: 'TRANSLATION_UNAVAILABLE' });
    TestBed.resetTestingModule();
    const down = vi.fn(async () => Promise.reject(new TypeError('fetch failed')));
    await expect(
      setup(vi.fn(), undefined, down).service.translate('es', 'en', ['a']),
    ).rejects.toMatchObject({ code: 'TRANSLATION_UNAVAILABLE' });
  });

  it('reads the contract code and retryAt from the function response', async () => {
    const response = new Response(
      JSON.stringify({ code: 'TRANSLATION_RATE_LIMITED', retryAt: '2026-11-17T15:00:00Z' }),
      { status: 429 },
    );
    const error = await translationError({ context: response }, null);
    expect(error).toMatchObject({
      code: 'TRANSLATION_RATE_LIMITED',
      retryAt: '2026-11-17T15:00:00Z',
    });
    expect((await translationError({ context: new Response('oops') }, null)).code).toBe(
      'TRANSLATION_UNAVAILABLE',
    );
    expect((await translationError({}, { code: 'FORBIDDEN' })).code).toBe('FORBIDDEN');
  });
});
