import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { vi } from 'vitest';
import type {
  GeneratedPublicAccessKey,
  PublicAccessKey,
} from '../../../core/catalog/models/public-agency-config.model';
import { PublicAgencyConfigService } from '../../../core/catalog/services/public-agency-config.service';
import { toAppError } from '../../../core/error/error-handler';
import { PublicKeyComponent } from './public-key.component';

const current: PublicAccessKey = {
  id: 'k1',
  key_prefix: 'pk_1a2b3c4d',
  status: 'current',
  created_at: '2026-11-01T10:00:00Z',
  created_by_name: 'Admin',
  expires_at: null,
  revoked_at: null,
  revoked_by_name: null,
  last_used_at: null,
};

const rotated: GeneratedPublicAccessKey = {
  key: 'pk_' + 'f'.repeat(48),
  id: 'k2',
  key_prefix: 'pk_ffffffff',
  created_at: '2026-11-13T10:00:00Z',
  previous_key_id: 'k1',
  previous_key_expires_at: '2026-11-20T10:00:00Z',
};

async function render(api: Partial<PublicAgencyConfigService>) {
  TestBed.configureTestingModule({
    imports: [PublicKeyComponent],
    providers: [provideRouter([]), { provide: PublicAgencyConfigService, useValue: api }],
  });
  const fixture = TestBed.createComponent(PublicKeyComponent);
  await fixture.whenStable();
  fixture.detectChanges();
  return fixture;
}

function text(fixture: { nativeElement: HTMLElement }): string {
  return fixture.nativeElement.textContent?.replace(/\s+/g, ' ') ?? '';
}

function button(fixture: { nativeElement: HTMLElement }, label: string): HTMLButtonElement {
  const found = [...fixture.nativeElement.querySelectorAll('button')].find((item) =>
    item.textContent?.includes(label),
  );
  if (!found) {
    throw new Error(`button «${label}» not found`);
  }
  return found as HTMLButtonElement;
}

describe('PublicKeyComponent', () => {
  beforeEach(() => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    TestBed.resetTestingModule();
  });

  it('offers to generate the first key when the agency has none', async () => {
    const fixture = await render({ listKeys: vi.fn(async () => []) });
    expect(text(fixture)).toContain('aún no tiene clave pública');
    expect(button(fixture, 'Generar clave')).toBeTruthy();
  });

  it('shows the new key once, with the 7-day expiry of the previous one', async () => {
    const listKeys = vi
      .fn()
      .mockResolvedValueOnce([current])
      .mockResolvedValue([
        {
          ...rotated,
          status: 'current',
          created_by_name: null,
          expires_at: null,
          revoked_at: null,
          revoked_by_name: null,
          last_used_at: null,
        },
        { ...current, status: 'grace', expires_at: rotated.previous_key_expires_at },
      ]);
    const generateKey = vi.fn(async () => rotated);
    const fixture = await render({ listKeys, generateKey });

    button(fixture, 'Regenerar clave').click();
    await fixture.whenStable();
    fixture.detectChanges();

    expect(generateKey).toHaveBeenCalledOnce();
    expect(text(fixture)).toContain(rotated.key);
    expect(text(fixture)).toContain('(7 días)');
    expect(text(fixture)).toContain('En transición');

    button(fixture, 'Ya la guardé').click();
    fixture.detectChanges();
    expect(text(fixture)).not.toContain(rotated.key);
  });

  it('never renders anything but the prefix of listed keys', async () => {
    const fixture = await render({ listKeys: vi.fn(async () => [current]) });
    expect(text(fixture)).toContain('pk_1a2b3c4d…');
    expect(text(fixture)).not.toMatch(/pk_[0-9a-f]{48}/);
  });

  it('revokes a key after confirmation', async () => {
    const revokeKey = vi.fn(async () => undefined);
    const listKeys = vi
      .fn()
      .mockResolvedValueOnce([current])
      .mockResolvedValue([{ ...current, status: 'revoked', revoked_at: '2026-11-13T10:00:00Z' }]);
    const fixture = await render({ listKeys, revokeKey });

    button(fixture, 'Revocar').click();
    await fixture.whenStable();
    fixture.detectChanges();

    expect(revokeKey).toHaveBeenCalledWith('k1');
    expect(text(fixture)).toContain('Revocada');
  });

  it('shows a permission error to roles the backend rejects', async () => {
    const fixture = await render({
      listKeys: vi.fn(async () => {
        throw toAppError({ code: '42501', message: 'FORBIDDEN' });
      }),
    });
    expect(text(fixture)).toContain('No tienes permisos');
    expect(fixture.nativeElement.querySelector('button.primary')).toBeNull();
  });
});
