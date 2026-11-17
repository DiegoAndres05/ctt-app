import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap, provideRouter, Router } from '@angular/router';
import { vi } from 'vitest';
import type { BlogArticleDetail, BlogContent } from '../../../core/blog/models/blog-article.model';
import { BlogService, type BlogError } from '../../../core/blog/services/blog.service';
import { BlogEditorComponent } from './blog-editor.component';
import { toSavePayload, emptyDraft, fromEditorBlocks, newBlock } from './blog-editor.model';

function content(title: string): BlogContent {
  return {
    coverRef: 'org/blog/a1/c.webp',
    updatedAt: null,
    es: {
      title,
      summary: 'Resumen',
      coverAlt: 'Portada',
      body: [{ type: 'paragraph', text: [{ text: 'Hola' }] }],
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
  };
}

function detail(overrides: Partial<BlogArticleDetail> = {}): BlogArticleDetail {
  return {
    id: 'a1',
    slug: 'cartagena',
    status: 'draft',
    migrated: false,
    originalPublishedAt: null,
    firstPublishedAt: null,
    publicUpdatedAt: null,
    updatedAt: '2026-11-17T10:00:00Z',
    revision: 4,
    requiredLocales: ['es', 'en'],
    migrationOpen: false,
    working: content('Cartagena'),
    published: null,
    publishErrors: [],
    ...overrides,
  };
}

async function render(id: string, api: Partial<BlogService>, query: Record<string, string> = {}) {
  TestBed.configureTestingModule({
    imports: [BlogEditorComponent],
    providers: [
      provideRouter([]),
      {
        provide: ActivatedRoute,
        useValue: {
          snapshot: {
            paramMap: convertToParamMap({ id }),
            queryParamMap: convertToParamMap(query),
          },
        },
      },
      {
        provide: BlogService,
        useValue: {
          mediaUrl: (ref: string | null) => (ref ? `https://cdn/${ref}` : null),
          getArticle: vi.fn(async () => detail()),
          ...api,
        },
      },
    ],
  });
  const router = TestBed.inject(Router);
  vi.spyOn(router, 'navigate').mockResolvedValue(true);
  const fixture = TestBed.createComponent(BlogEditorComponent);
  await fixture.whenStable();
  fixture.detectChanges();
  return fixture;
}

function el<T extends HTMLElement>(fixture: { nativeElement: HTMLElement }, selector: string): T {
  return fixture.nativeElement.querySelector(selector) as T;
}

function buttonByText(
  fixture: { nativeElement: HTMLElement },
  text: string,
): HTMLButtonElement | undefined {
  return [...fixture.nativeElement.querySelectorAll('button')].find(
    (b) => b.textContent?.trim() === text,
  ) as HTMLButtonElement | undefined;
}

describe('blog editor model', () => {
  it('creates with only a title and no revision', () => {
    const draft = emptyDraft();
    draft.es.title = 'Solo título';
    const payload = toSavePayload(draft, null, null);
    expect(payload.id).toBeNull();
    expect(payload.expectedRevision).toBeNull();
    expect(payload.es.title).toBe('Solo título');
    expect(payload.es.summary).toBeNull();
  });

  it('turns list lines into items and drops images without a file', () => {
    const list = { ...newBlock('list'), itemsMarkup: 'uno\n\n **dos** ' };
    const image = newBlock('image');
    expect(fromEditorBlocks([list, image])).toEqual([
      { type: 'list', ordered: false, items: [[{ text: 'uno' }], [{ text: 'dos', bold: true }]] },
    ]);
  });
});

describe('BlogEditorComponent', () => {
  it('saves a new draft with only the title and opens it', async () => {
    const saveArticle = vi.fn(async () => ({
      id: 'a1',
      revision: 1,
      status: 'draft' as const,
      hasPendingChanges: false,
      firstPublishedAt: null,
      publicUpdatedAt: null,
    }));
    const fixture = await render('new', { saveArticle });

    const title = el<HTMLInputElement>(fixture, '#blog-title-es');
    title.value = 'Qué ver en Cartagena';
    title.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    expect(el<HTMLInputElement>(fixture, '#blog-slug').value).toBe('que-ver-en-cartagena');

    buttonByText(fixture, 'Guardar borrador')?.click();
    await fixture.whenStable();

    expect(saveArticle).toHaveBeenCalledWith(
      expect.objectContaining({
        id: null,
        slug: 'que-ver-en-cartagena',
        es: expect.objectContaining({ title: 'Qué ver en Cartagena' }),
      }),
    );
    expect(TestBed.inject(Router).navigate).toHaveBeenCalledWith(['/cms/blog', 'a1'], {
      replaceUrl: true,
    });
  });

  it('shows the conflict choices when someone else saved first', async () => {
    const conflict: BlogError = {
      code: 'ARTICLE_CONFLICT',
      message: 'Otra persona guardó este artículo.',
    };
    const fixture = await render('a1', {
      saveArticle: vi.fn(async () => Promise.reject(conflict)),
    });

    buttonByText(fixture, 'Guardar borrador')?.click();
    await fixture.whenStable();
    fixture.detectChanges();

    expect(fixture.nativeElement.textContent).toContain('Otra persona guardó este artículo.');
    expect(buttonByText(fixture, 'Recargar')).toBeTruthy();
    expect(buttonByText(fixture, 'Sobrescribir')).toBeTruthy();
  });

  it('lists the missing fields per language when publishing is rejected', async () => {
    const incomplete: BlogError = {
      code: 'PUBLISH_INCOMPLETE',
      message: 'Faltan campos para publicar.',
      publishErrors: [
        { field: 'title', locale: 'en' },
        { field: 'body', locale: 'en' },
        { field: 'cover', locale: null },
      ],
    };
    const fixture = await render('a1', {
      publishArticle: vi.fn(async () => Promise.reject(incomplete)),
    });

    buttonByText(fixture, 'Publicar')?.click();
    await fixture.whenStable();
    fixture.detectChanges();

    const text = fixture.nativeElement.textContent as string;
    expect(text).toContain('Para publicar falta');
    expect(text).toContain('Título, Contenido del artículo');
    expect(text).toContain('Portada');

    buttonByText(fixture, 'Inglés')?.click();
    fixture.detectChanges();
    expect(el<HTMLInputElement>(fixture, '#blog-title-en')).toBeTruthy();
  });

  it('locks the slug and offers publish/discard for a pending revision', async () => {
    const fixture = await render('a1', {
      getArticle: vi.fn(async () =>
        detail({
          status: 'published',
          firstPublishedAt: '2026-11-01T00:00:00Z',
          published: content('Publicado'),
        }),
      ),
    });

    expect(el<HTMLInputElement>(fixture, '#blog-slug').readOnly).toBe(true);
    expect(fixture.nativeElement.textContent).toContain('Cambios sin publicar');
    expect(buttonByText(fixture, 'Publicar cambios')).toBeTruthy();
    expect(buttonByText(fixture, 'Descartar cambios')).toBeTruthy();
    expect(buttonByText(fixture, 'Eliminar borrador')).toBeUndefined();
  });

  it('asks for confirmation before discarding changes', async () => {
    const discardChanges = vi.fn();
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    const fixture = await render('a1', {
      discardChanges,
      getArticle: vi.fn(async () =>
        detail({
          status: 'published',
          firstPublishedAt: '2026-11-01T00:00:00Z',
          published: content('Publicado'),
        }),
      ),
    });

    buttonByText(fixture, 'Descartar cambios')?.click();
    await fixture.whenStable();

    expect(confirm).toHaveBeenCalled();
    expect(discardChanges).not.toHaveBeenCalled();
    confirm.mockRestore();
  });

  it('keeps pasted HTML as text in the preview', async () => {
    const fixture = await render('a1', {});
    const textarea = el<HTMLTextAreaElement>(fixture, '.block textarea');
    textarea.value = '<img src=x onerror=alert(1)> **ok**';
    textarea.dispatchEvent(new Event('input'));
    fixture.detectChanges();

    const preview = el<HTMLElement>(fixture, 'app-blog-preview');
    expect(preview.querySelector('img[onerror]')).toBeNull();
    expect(preview.textContent).toContain('<img src=x onerror=alert(1)>');
    expect(preview.querySelector('strong')?.textContent).toBe('ok');
  });

  it('offers the migrated options only when created from the migration screen', async () => {
    const fixture = await render('new', {}, { migrated: '1', slug: 'Mi_Post-2019' });
    expect(el<HTMLInputElement>(fixture, '#blog-original-date')).toBeTruthy();
    expect(el<HTMLInputElement>(fixture, '#blog-slug').value).toBe('Mi_Post-2019');
  });

  describe('translation (spec 017)', () => {
    const tabEnglish = (fixture: { nativeElement: HTMLElement; detectChanges(): void }) => {
      [...fixture.nativeElement.querySelectorAll('button')]
        .find((b) => b.textContent?.trim().startsWith('Inglés'))
        ?.click();
      fixture.detectChanges();
    };

    it('translates Spanish into the empty English tab and can undo it', async () => {
      const translate = vi.fn(async (_s: string, _t: string, segments: string[]) =>
        segments.map((x) => `EN:${x}`),
      );
      const fixture = await render('a1', { translate });
      tabEnglish(fixture);

      buttonByText(fixture, 'Traducir desde Español')?.click();
      await fixture.whenStable();
      fixture.detectChanges();

      expect(translate).toHaveBeenCalledWith('es', 'en', expect.arrayContaining(['Cartagena']));
      expect(el<HTMLInputElement>(fixture, '#blog-title-en').value).toBe('EN:Cartagena');
      expect(fixture.nativeElement.textContent).toContain('Traducción automática desde Español');

      buttonByText(fixture, 'Deshacer traducción')?.click();
      fixture.detectChanges();
      expect(el<HTMLInputElement>(fixture, '#blog-title-en').value).toBe('');
    });

    it('asks before touching existing text, and Cancel changes nothing (FR-008)', async () => {
      const translate = vi.fn(async (_s: string, _t: string, segments: string[]) => segments);
      const withEnglish = content('Cartagena');
      withEnglish.en.title = 'Mine';
      const fixture = await render('a1', {
        translate,
        getArticle: vi.fn(async () => detail({ working: withEnglish })),
      });
      tabEnglish(fixture);

      buttonByText(fixture, 'Traducir desde Español')?.click();
      fixture.detectChanges();
      expect(fixture.nativeElement.querySelector('[role="alertdialog"]')).not.toBeNull();

      buttonByText(fixture, 'Cancelar')?.click();
      await fixture.whenStable();
      fixture.detectChanges();
      expect(translate).not.toHaveBeenCalled();
      expect(el<HTMLInputElement>(fixture, '#blog-title-en').value).toBe('Mine');
    });

    it('keeps the target unchanged and explains when the translator fails (US3)', async () => {
      const failure: BlogError = {
        code: 'TRANSLATION_RATE_LIMITED',
        message: 'Tu agencia alcanzó el límite de traducciones de esta hora.',
        retryAt: '2026-11-17T15:00:00Z',
      };
      const fixture = await render('a1', { translate: vi.fn(async () => Promise.reject(failure)) });
      tabEnglish(fixture);

      buttonByText(fixture, 'Traducir desde Español')?.click();
      await fixture.whenStable();
      fixture.detectChanges();

      expect(fixture.nativeElement.textContent).toContain('Podrás volver a intentarlo a las');
      expect(el<HTMLInputElement>(fixture, '#blog-title-en').value).toBe('');
    });

    it('hides the button when the agency offers a single language', async () => {
      const fixture = await render('a1', {
        getArticle: vi.fn(async () => detail({ requiredLocales: ['es'] })),
      });
      tabEnglish(fixture);
      expect(buttonByText(fixture, 'Traducir desde Español')).toBeUndefined();
    });
  });
});
