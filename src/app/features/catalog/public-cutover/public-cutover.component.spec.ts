import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { vi } from 'vitest';
import type { CutoverStatus } from '../../../core/catalog/models/public-listing.model';
import type { PublicSourceConfig } from '../../../core/catalog/models/public-agency-config.model';
import { PublicListingService } from '../../../core/catalog/services/public-listing.service';
import { PublicAgencyConfigService } from '../../../core/catalog/services/public-agency-config.service';
import { PublicCutoverComponent } from './public-cutover.component';

const legacySite = {
  organization_id: 'org',
  source: 'legacy' as const,
  cutover_completed_at: null,
  cutover_completed_by: null,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
};

function status(missing: string[]): CutoverStatus {
  return {
    site: legacySite,
    items: missing.map((slug) => ({
      organization_id: 'org',
      public_slug: slug,
      placement: 'catalog' as const,
      listing_id: null,
      created_at: '2026-01-01T00:00:00Z',
    })),
    missing_slugs: missing,
  };
}

async function render(cutover: CutoverStatus, config: PublicSourceConfig) {
  TestBed.configureTestingModule({
    imports: [PublicCutoverComponent],
    providers: [
      provideRouter([]),
      {
        provide: PublicListingService,
        useValue: { getCutoverStatus: vi.fn(async () => cutover), completeCutover: vi.fn() },
      },
      {
        provide: PublicAgencyConfigService,
        useValue: { getSourceConfig: vi.fn(async () => config) },
      },
    ],
  });
  const fixture = TestBed.createComponent(PublicCutoverComponent);
  await fixture.whenStable();
  fixture.detectChanges();
  return fixture;
}

function text(fixture: { nativeElement: HTMLElement }): string {
  return fixture.nativeElement.textContent?.replace(/\s+/g, ' ') ?? '';
}

describe('PublicCutoverComponent', () => {
  afterEach(() => TestBed.resetTestingModule());

  it('tells a new agency it publishes directly, with no manifest step', async () => {
    const fixture = await render(status([]), {
      organization_id: 'org',
      migration_required: false,
      organization_identifier_until: null,
    });
    expect(text(fixture)).toContain('Publicación directa');
    expect(text(fixture)).not.toContain('Manifiesto del sitio anterior');
    expect(text(fixture)).not.toContain('Acceso por identificador');
  });

  it('blocks the cutover of a migrating agency while manifest items are missing', async () => {
    const fixture = await render(status(['islas-capri-premium']), {
      organization_id: 'org',
      migration_required: true,
      organization_identifier_until: '2099-01-01T00:00:00Z',
    });
    expect(text(fixture)).toContain('Migración desde un sitio existente');
    expect(text(fixture)).toContain('islas-capri-premium');
    const complete = [...fixture.nativeElement.querySelectorAll('button')].find((item) =>
      item.textContent?.includes('Completar cambio de fuente'),
    ) as HTMLButtonElement;
    expect(complete.disabled).toBe(true);
    expect(text(fixture)).toContain('Cerrar acceso por identificador');
  });

  it('reports a closed organization-identifier access', async () => {
    const fixture = await render(status([]), {
      organization_id: 'org',
      migration_required: true,
      organization_identifier_until: '2020-01-01T00:00:00Z',
    });
    expect(text(fixture)).toContain('solo funciona con la clave pública');
    expect(text(fixture)).not.toContain('Cerrar acceso por identificador');
  });
});
