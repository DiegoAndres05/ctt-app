import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { vi } from 'vitest';
import type { AppRole } from '../../../core/auth/models/user.model';
import { AuthService } from '../../../core/auth/services/auth.service';
import type { PublicProfileSettings } from '../../../core/catalog/models/public-agency-config.model';
import { PublicAgencyConfigService } from '../../../core/catalog/services/public-agency-config.service';
import { PublicProfileComponent, toProfilePayload } from './public-profile.component';

const SETTINGS: PublicProfileSettings = {
  commercial_name: 'Agencia Uno',
  logo_ref: null,
  primary_color: null,
  contact_email: null,
  contact_phone: null,
  whatsapp: null,
  social_links: {},
  languages: ['es', 'en'],
  currency: 'COP',
  updated_at: null,
  updated_by_name: null,
  supported_currencies: ['COP', 'USD', 'EUR'],
  social_networks: ['instagram', 'facebook'],
};

async function render(role: AppRole, api: Partial<PublicAgencyConfigService>) {
  TestBed.configureTestingModule({
    imports: [PublicProfileComponent],
    providers: [
      provideRouter([]),
      { provide: AuthService, useValue: { role: () => role, organizationId: () => 'org' } },
      {
        provide: PublicAgencyConfigService,
        useValue: { mediaUrl: () => null, getProfile: vi.fn(async () => SETTINGS), ...api },
      },
    ],
  });
  const fixture = TestBed.createComponent(PublicProfileComponent);
  await fixture.whenStable();
  fixture.detectChanges();
  return fixture;
}

function input(fixture: { nativeElement: HTMLElement }, id: string): HTMLInputElement {
  return fixture.nativeElement.querySelector(`#${id}`) as HTMLInputElement;
}

function type(el: HTMLInputElement, value: string): void {
  el.value = value;
  el.dispatchEvent(new Event('input'));
}

describe('toProfilePayload', () => {
  it('drops empty optional fields and empty networks, and upper-cases the color', () => {
    const payload = toProfilePayload(
      {
        commercialName: '  Agencia  ',
        primaryColor: '#0f766e',
        contactEmail: ' ',
        contactPhone: '',
        whatsapp: '+57 300',
        currency: 'USD',
        langEs: false,
        langEn: true,
        social: {
          instagram: 'https://instagram.com/a',
          facebook: '',
          tiktok: '',
          youtube: '',
          x: '',
          linkedin: '',
          tripadvisor: '',
        },
      },
      'org/profile/logo.png',
    );
    expect(payload).toEqual({
      commercial_name: 'Agencia',
      logo_ref: 'org/profile/logo.png',
      primary_color: '#0F766E',
      contact_email: null,
      contact_phone: null,
      whatsapp: '+57 300',
      social_links: { instagram: 'https://instagram.com/a' },
      languages: ['en'],
      currency: 'USD',
    });
  });
});

describe('PublicProfileComponent', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    TestBed.resetTestingModule();
  });

  it('loads the profile and saves the edited fields', async () => {
    const saveProfile = vi.fn(async () => ({ ...SETTINGS, commercial_name: 'Agencia Uno Travel' }));
    const fixture = await render('operator', { saveProfile });

    expect(input(fixture, 'pp-name').value).toBe('Agencia Uno');
    type(input(fixture, 'pp-name'), 'Agencia Uno Travel');
    type(input(fixture, 'pp-email'), 'hola@agencia.test');
    fixture.nativeElement.querySelector('form').dispatchEvent(new Event('submit'));
    await fixture.whenStable();
    fixture.detectChanges();

    expect(saveProfile).toHaveBeenCalledWith(
      expect.objectContaining({
        commercial_name: 'Agencia Uno Travel',
        contact_email: 'hola@agencia.test',
        languages: ['es', 'en'],
        currency: 'COP',
      }),
    );
    expect(fixture.nativeElement.textContent).toContain('El perfil público se guardó.');
  });

  it('blocks the save and points at the invalid field', async () => {
    const saveProfile = vi.fn();
    const fixture = await render('operator', { saveProfile });

    type(input(fixture, 'pp-color'), 'verde');
    fixture.nativeElement.querySelector('form').dispatchEvent(new Event('submit'));
    await fixture.whenStable();
    fixture.detectChanges();

    expect(saveProfile).not.toHaveBeenCalled();
    expect(fixture.nativeElement.textContent).toContain('Usa un color en formato #RRGGBB.');
  });

  it('is read-only for an agent', async () => {
    const fixture = await render('agent', {});
    const fieldset = fixture.nativeElement.querySelector('fieldset') as HTMLFieldSetElement;
    expect(fieldset.disabled).toBe(true);
    expect(fixture.nativeElement.textContent).not.toContain('Guardar perfil');
  });
});
