import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { vi } from 'vitest';
import type { BlogSource } from '../../../core/blog/models/blog-article.model';
import { BlogService, type BlogError } from '../../../core/blog/services/blog.service';
import { BlogMigrationComponent, parseManifest } from './blog-migration.component';

const OPEN: BlogSource = {
  migrationRequired: true,
  cutoverCompletedAt: null,
  markedAt: '2026-11-17T10:00:00Z',
  manifest: [
    { slug: 'guia-islas', articleId: 'a1', published: true },
    { slug: 'playa-blanca', articleId: null, published: false },
  ],
  missing: ['playa-blanca'],
};

async function render(api: Partial<BlogService>) {
  TestBed.configureTestingModule({
    imports: [BlogMigrationComponent],
    providers: [
      provideRouter([]),
      { provide: BlogService, useValue: { getSource: vi.fn(async () => OPEN), ...api } },
    ],
  });
  const fixture = TestBed.createComponent(BlogMigrationComponent);
  await fixture.whenStable();
  fixture.detectChanges();
  return fixture;
}

describe('parseManifest', () => {
  it('trims, drops blank lines and repeats', () => {
    expect(parseManifest(' a \n\nb\na\n')).toEqual(['a', 'b']);
  });
});

describe('BlogMigrationComponent', () => {
  it('links each missing slug to a prefilled migrated article', async () => {
    const fixture = await render({});
    const link = [...fixture.nativeElement.querySelectorAll('a')].find((a: HTMLAnchorElement) =>
      a.textContent?.includes('Falta'),
    ) as HTMLAnchorElement;
    expect(link.getAttribute('href')).toContain('/cms/blog/new?migrated=1&slug=playa-blanca');
  });

  it('shows the missing slugs after BLOG_CUTOVER_INCOMPLETE', async () => {
    const incomplete: BlogError = {
      code: 'BLOG_CUTOVER_INCOMPLETE',
      message: 'Faltan artículos del blog anterior.',
      missingSlugs: ['playa-blanca', 'otra'],
    };
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    const fixture = await render({
      completeCutover: vi.fn(async () => Promise.reject(incomplete)),
    });

    const button = [...fixture.nativeElement.querySelectorAll('button')].find(
      (b: HTMLButtonElement) => b.textContent?.includes('Completar cambio de fuente'),
    ) as HTMLButtonElement;
    button.click();
    await fixture.whenStable();
    fixture.detectChanges();

    const text = fixture.nativeElement.textContent as string;
    expect(text).toContain('Faltan artículos del blog anterior.');
    expect(text).toContain('Faltan 2: playa-blanca, otra');
    vi.restoreAllMocks();
  });

  it('is read-only once the cutover is completed', async () => {
    const fixture = await render({
      getSource: vi.fn(async () => ({
        ...OPEN,
        cutoverCompletedAt: '2026-11-17T12:00:00Z',
        missing: [],
      })),
    });
    const text = fixture.nativeElement.textContent as string;
    expect(text).toContain('Cambio de fuente completado');
    expect(fixture.nativeElement.querySelector('input[type="checkbox"]')).toBeNull();
    expect(fixture.nativeElement.querySelector('textarea')).toBeNull();
  });
});
