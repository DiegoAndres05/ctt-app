import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { vi } from 'vitest';
import type { AppRole } from '../../../core/auth/models/user.model';
import { AuthService } from '../../../core/auth/services/auth.service';
import type { PublicTaxonomyValue } from '../../../core/catalog/models/public-agency-config.model';
import { PublicAgencyConfigService } from '../../../core/catalog/services/public-agency-config.service';
import { PublicTaxonomiesComponent } from './public-taxonomies.component';

function value(partial: Partial<PublicTaxonomyValue>): PublicTaxonomyValue {
  return {
    id: partial.code ?? 'x',
    kind: 'amenity',
    code: 'x',
    name_es: 'X',
    name_en: 'X',
    is_active: true,
    sort_order: 1,
    in_use: false,
    ...partial,
  };
}

const VALUES: PublicTaxonomyValue[] = [
  value({ kind: 'lodging_type', code: 'casa', name_es: 'Casa', name_en: 'House' }),
  value({ kind: 'lodging_type', code: 'hotel', name_es: 'Hotel', name_en: 'Hotel', in_use: true }),
  value({ kind: 'amenity', code: 'wifi', name_es: 'Wifi', name_en: 'Wi-Fi', in_use: true }),
  value({
    kind: 'amenity',
    code: 'bbq',
    name_es: 'Zona BBQ',
    name_en: 'BBQ area',
    is_active: false,
  }),
];

async function render(role: AppRole, api: Partial<PublicAgencyConfigService>) {
  TestBed.configureTestingModule({
    imports: [PublicTaxonomiesComponent],
    providers: [
      provideRouter([]),
      { provide: AuthService, useValue: { role: () => role } },
      { provide: PublicAgencyConfigService, useValue: api },
    ],
  });
  const fixture = TestBed.createComponent(PublicTaxonomiesComponent);
  await fixture.whenStable();
  fixture.detectChanges();
  return fixture;
}

function rows(fixture: { nativeElement: HTMLElement }): string[] {
  return [...fixture.nativeElement.querySelectorAll('tbody tr')].map(
    (row) => row.textContent?.replace(/\s+/g, ' ').trim() ?? '',
  );
}

function codes(fixture: { nativeElement: HTMLElement }): string[] {
  return [...fixture.nativeElement.querySelectorAll('tbody tr code')].map(
    (cell) => cell.textContent?.trim() ?? '',
  );
}

function clickTab(
  fixture: { nativeElement: HTMLElement; detectChanges(): void },
  label: string,
): void {
  const tab = [...fixture.nativeElement.querySelectorAll('[role="tab"]')].find((item) =>
    item.textContent?.includes(label),
  ) as HTMLButtonElement;
  tab.click();
  fixture.detectChanges();
}

describe('PublicTaxonomiesComponent', () => {
  beforeEach(() => vi.spyOn(window, 'confirm').mockReturnValue(true));
  afterEach(() => {
    vi.restoreAllMocks();
    TestBed.resetTestingModule();
  });

  it('lists lodging types first and switches to amenities', async () => {
    const fixture = await render('operator', { listTaxonomy: vi.fn(async () => VALUES) });
    expect(codes(fixture)).toEqual(['casa', 'hotel']);

    clickTab(fixture, 'Amenidades');
    expect(codes(fixture)).toEqual(['wifi', 'bbq']);
  });

  it('only offers deletion for values no listing uses', async () => {
    const fixture = await render('operator', { listTaxonomy: vi.fn(async () => VALUES) });
    const [casa, hotel] = rows(fixture);
    expect(casa).toContain('Eliminar');
    expect(hotel).toContain('En uso');
    expect(hotel).not.toContain('Eliminar');
  });

  it('deactivates a value in use instead of deleting it', async () => {
    const saveTaxonomyValue = vi.fn(async () => VALUES[1]);
    const fixture = await render('operator', {
      listTaxonomy: vi.fn(async () => VALUES),
      saveTaxonomyValue,
    });
    const hotelRow = fixture.nativeElement.querySelectorAll('tbody tr')[1] as HTMLElement;
    const deactivate = [...hotelRow.querySelectorAll('button')].find((item) =>
      item.textContent?.includes('Desactivar'),
    ) as HTMLButtonElement;
    deactivate.click();
    await fixture.whenStable();
    fixture.detectChanges();

    expect(saveTaxonomyValue).toHaveBeenCalledWith(
      expect.objectContaining({ kind: 'lodging_type', code: 'hotel', is_active: false }),
    );
    expect(fixture.nativeElement.textContent).toContain('siguen mostrando');
  });

  it('gives an agent a read-only view', async () => {
    const fixture = await render('agent', { listTaxonomy: vi.fn(async () => VALUES) });
    expect(fixture.nativeElement.querySelector('form')).toBeNull();
    expect(rows(fixture).join(' ')).not.toMatch(/Editar|Desactivar|Eliminar/);
  });
});
