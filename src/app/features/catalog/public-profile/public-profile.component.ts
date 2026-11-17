import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { form, FormField, required, submit } from '@angular/forms/signals';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import {
  SOCIAL_NETWORK_LABELS,
  SOCIAL_NETWORKS,
  validatePublicProfile,
  type PublicLanguage,
  type PublicProfile,
  type PublicProfileField,
  type SavePublicProfilePayload,
  type SocialNetwork,
} from '../../../core/catalog/models/public-agency-config.model';
import { PublicAgencyConfigService } from '../../../core/catalog/services/public-agency-config.service';
import { AuthService } from '../../../core/auth/services/auth.service';
import { hasRoleAtLeast } from '../../../core/auth/models/user.model';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';
import type { UnsavedChangesHost } from '../../../shared/components/unsaved-changes.guard';

type SocialDraft = Record<SocialNetwork, string>;

interface ProfileDraft {
  commercialName: string;
  primaryColor: string;
  contactEmail: string;
  contactPhone: string;
  whatsapp: string;
  currency: string;
  langEs: boolean;
  langEn: boolean;
  social: SocialDraft;
}

const EMPTY_SOCIAL = Object.fromEntries(
  SOCIAL_NETWORKS.map((network) => [network, '']),
) as SocialDraft;

function toDraft(profile: PublicProfile): ProfileDraft {
  const social = { ...EMPTY_SOCIAL };
  for (const network of SOCIAL_NETWORKS) {
    social[network] = profile.social_links?.[network] ?? '';
  }
  return {
    commercialName: profile.commercial_name,
    primaryColor: profile.primary_color ?? '',
    contactEmail: profile.contact_email ?? '',
    contactPhone: profile.contact_phone ?? '',
    whatsapp: profile.whatsapp ?? '',
    currency: profile.currency,
    langEs: profile.languages.includes('es'),
    langEn: profile.languages.includes('en'),
    social,
  };
}

function blankToNull(value: string): string | null {
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

/** Builds the RPC payload from the form draft and the separately managed logo. */
export function toProfilePayload(
  draft: ProfileDraft,
  logoRef: string | null,
): SavePublicProfilePayload {
  const languages: PublicLanguage[] = [];
  if (draft.langEs) {
    languages.push('es');
  }
  if (draft.langEn) {
    languages.push('en');
  }
  const social_links: Partial<Record<SocialNetwork, string>> = {};
  for (const network of SOCIAL_NETWORKS) {
    const url = draft.social[network].trim();
    if (url) {
      social_links[network] = url;
    }
  }
  return {
    commercial_name: draft.commercialName.trim(),
    logo_ref: logoRef,
    primary_color: blankToNull(draft.primaryColor)?.toUpperCase() ?? null,
    contact_email: blankToNull(draft.contactEmail),
    contact_phone: blankToNull(draft.contactPhone),
    whatsapp: blankToNull(draft.whatsapp),
    social_links,
    languages,
    currency: draft.currency,
  };
}

/**
 * Public agency profile (feature 016, US3): what a showcase shows about the agency. Operator and
 * Administrator edit it; nothing here is internal data.
 */
@Component({
  selector: 'app-public-profile',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, FormField, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <header class="page-head">
        <a routerLink="/cms/settings">Ajustes del catálogo</a>
        <h1>Perfil público</h1>
        <p class="hint">
          Lo que tu página o vitrina muestra de la agencia junto al catálogo. Los campos vacíos no
          se muestran.
        </p>
      </header>

      @if (loading()) {
        <app-spinner label="Cargando perfil…" />
      } @else if (loadError(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else {
        <form class="card" (submit)="onSubmit($event)" novalidate>
          <fieldset class="plain" [disabled]="!canEdit()">
            <section class="section">
              <h3>Identidad</h3>
              <div class="form-grid">
                <div class="field req span-all" [class.has-error]="fieldError('commercial_name')">
                  <label for="pp-name">Nombre comercial</label>
                  <input id="pp-name" type="text" [formField]="profileForm.commercialName" />
                  @if (fieldError('commercial_name'); as message) {
                    <p class="field-error">{{ message }}</p>
                  }
                </div>

                <div class="field">
                  <span class="label">Logo</span>
                  <div class="logo-row">
                    @if (logoUrl(); as url) {
                      <img class="logo" [src]="url" alt="Logo actual" />
                    } @else {
                      <span class="logo empty" aria-hidden="true">Sin logo</span>
                    }
                    <div class="logo-actions">
                      <label class="button-like" for="pp-logo">
                        {{ uploading() ? 'Subiendo…' : logoRef() ? 'Cambiar logo' : 'Subir logo' }}
                      </label>
                      <input
                        id="pp-logo"
                        class="visually-hidden"
                        type="file"
                        accept="image/png,image/jpeg,image/webp"
                        [disabled]="uploading()"
                        (change)="onLogoSelected($event)"
                      />
                      @if (logoRef()) {
                        <button type="button" class="link danger" (click)="removeLogo()">
                          Quitar
                        </button>
                      }
                    </div>
                  </div>
                  <p class="hint">PNG, JPG o WebP de hasta 2 MB.</p>
                </div>

                <div class="field" [class.has-error]="fieldError('primary_color')">
                  <label for="pp-color">Color principal</label>
                  <div class="color-row">
                    <span
                      class="swatch"
                      [style.background]="validColor() ?? 'transparent'"
                      aria-hidden="true"
                    ></span>
                    <input
                      id="pp-color"
                      type="text"
                      placeholder="#0F766E"
                      [formField]="profileForm.primaryColor"
                    />
                  </div>
                  @if (fieldError('primary_color'); as message) {
                    <p class="field-error">{{ message }}</p>
                  } @else {
                    <p class="hint">Formato #RRGGBB.</p>
                  }
                </div>
              </div>
            </section>

            <section class="section">
              <h3>Contacto</h3>
              <div class="form-grid">
                <div class="field" [class.has-error]="fieldError('contact_email')">
                  <label for="pp-email">Correo</label>
                  <input id="pp-email" type="email" [formField]="profileForm.contactEmail" />
                  @if (fieldError('contact_email'); as message) {
                    <p class="field-error">{{ message }}</p>
                  }
                </div>
                <div class="field" [class.has-error]="fieldError('contact_phone')">
                  <label for="pp-phone">Teléfono</label>
                  <input id="pp-phone" type="tel" [formField]="profileForm.contactPhone" />
                  @if (fieldError('contact_phone'); as message) {
                    <p class="field-error">{{ message }}</p>
                  }
                </div>
                <div class="field" [class.has-error]="fieldError('whatsapp')">
                  <label for="pp-wa">WhatsApp</label>
                  <input
                    id="pp-wa"
                    type="tel"
                    placeholder="+57 300 000 0000"
                    [formField]="profileForm.whatsapp"
                  />
                  @if (fieldError('whatsapp'); as message) {
                    <p class="field-error">{{ message }}</p>
                  }
                </div>
              </div>
            </section>

            <section class="section">
              <h3>Redes sociales</h3>
              <div class="form-grid" [class.has-error]="fieldError('social_links')">
                @for (network of networks; track network) {
                  <div class="field">
                    <label [for]="'pp-' + network">{{ networkLabels[network] }}</label>
                    <input
                      [id]="'pp-' + network"
                      type="url"
                      placeholder="https://"
                      [formField]="profileForm.social[network]"
                    />
                  </div>
                }
              </div>
              @if (fieldError('social_links'); as message) {
                <p class="field-error">{{ message }}</p>
              }
            </section>

            <section class="section">
              <h3>Idiomas y moneda</h3>
              <div class="form-grid">
                <div class="field" [class.has-error]="fieldError('languages')">
                  <span class="label">Idiomas que ofreces</span>
                  <div class="chips">
                    <label class="chip"
                      ><input type="checkbox" [formField]="profileForm.langEs" /> Español</label
                    >
                    <label class="chip"
                      ><input type="checkbox" [formField]="profileForm.langEn" /> Inglés</label
                    >
                  </div>
                  @if (fieldError('languages'); as message) {
                    <p class="field-error">{{ message }}</p>
                  }
                </div>
                <div class="field req" [class.has-error]="fieldError('currency')">
                  <label for="pp-currency">Moneda de los precios</label>
                  <select id="pp-currency" [formField]="profileForm.currency">
                    @for (currency of currencies(); track currency) {
                      <option [value]="currency">{{ currency }}</option>
                    }
                  </select>
                  @if (fieldError('currency'); as message) {
                    <p class="field-error">{{ message }}</p>
                  } @else {
                    <p class="hint">
                      Solo cambia cómo se presentan los precios; no convierte montos.
                    </p>
                  }
                </div>
              </div>
            </section>
          </fieldset>

          @if (saveError(); as failure) {
            <app-alert kind="error">{{ failure.message }}</app-alert>
          }
          @if (notice(); as message) {
            <app-alert kind="success">{{ message }}</app-alert>
          }

          @if (canEdit()) {
            <div class="form-actions">
              <button
                class="primary"
                type="submit"
                [disabled]="profileForm().submitting() || uploading()"
              >
                {{ profileForm().submitting() ? 'Guardando…' : 'Guardar perfil' }}
              </button>
              @if (updatedAt(); as at) {
                <span class="hint">
                  Última edición {{ at | date: 'd MMM y, h:mm a' }}
                  @if (updatedBy(); as who) {
                    · {{ who }}
                  }
                </span>
              }
            </div>
          } @else {
            <p class="hint">Solo operadores y administradores pueden editar el perfil.</p>
          }
        </form>
      }
    </main>
  `,
  styles: `
    .page {
      padding: 1.5rem;
      display: grid;
      gap: 1rem;
      max-width: 56rem;
    }

    .label {
      display: block;
      font-size: 0.875rem;
      font-weight: 600;
      margin-bottom: 0.35rem;
    }

    .logo-row,
    .color-row {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      flex-wrap: wrap;
    }

    .logo {
      width: 4rem;
      height: 4rem;
      object-fit: contain;
      border: 1px solid var(--color-border);
      border-radius: 0.5rem;
      background: var(--color-surface);
    }

    .logo.empty {
      display: grid;
      place-items: center;
      font-size: 0.75rem;
      color: var(--color-text-muted);
    }

    .logo-actions {
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }

    .button-like {
      display: inline-flex;
      align-items: center;
      min-height: 2.5rem;
      padding: 0 0.9rem;
      border: 1px solid var(--color-border);
      border-radius: 0.5rem;
      background: var(--color-surface);
      font-weight: 600;
      cursor: pointer;
      margin: 0;
    }

    .swatch {
      width: 2.5rem;
      height: 2.5rem;
      flex: none;
      border: 1px solid var(--color-border);
      border-radius: 0.5rem;
    }

    .color-row input {
      flex: 1 1 8rem;
      min-width: 0;
    }
  `,
})
export class PublicProfileComponent implements UnsavedChangesHost {
  private readonly api = inject(PublicAgencyConfigService);
  private readonly auth = inject(AuthService);

  protected readonly networks = SOCIAL_NETWORKS;
  protected readonly networkLabels = SOCIAL_NETWORK_LABELS;

  protected readonly loading = signal(true);
  protected readonly uploading = signal(false);
  protected readonly loadError = signal<AppError | null>(null);
  protected readonly saveError = signal<AppError | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly currencies = signal<string[]>(['COP']);
  protected readonly logoRef = signal<string | null>(null);
  protected readonly updatedAt = signal<string | null>(null);
  protected readonly updatedBy = signal<string | null>(null);
  protected readonly errors = signal<Partial<Record<PublicProfileField, string>>>({});

  protected readonly canEdit = computed(() => hasRoleAtLeast(this.auth.role(), 'operator'));
  protected readonly logoUrl = computed(() => this.api.mediaUrl(this.logoRef()));

  protected readonly draft = signal<ProfileDraft>({
    commercialName: '',
    primaryColor: '',
    contactEmail: '',
    contactPhone: '',
    whatsapp: '',
    currency: 'COP',
    langEs: true,
    langEn: true,
    social: { ...EMPTY_SOCIAL },
  });

  protected readonly profileForm = form(this.draft, (fields) => {
    required(fields.commercialName);
  });

  protected readonly validColor = computed(() => {
    const color = this.draft().primaryColor.trim().toUpperCase();
    return /^#[0-9A-F]{6}$/.test(color) ? color : null;
  });

  private baseline = '';

  constructor() {
    void this.load();
  }

  hasUnsavedChanges(): boolean {
    return !this.loading() && this.snapshot() !== this.baseline;
  }

  protected fieldError(field: PublicProfileField): string | null {
    return this.errors()[field] ?? null;
  }

  protected async onLogoSelected(event: Event): Promise<void> {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file) {
      return;
    }
    this.saveError.set(null);
    this.uploading.set(true);
    try {
      this.logoRef.set(await this.api.uploadLogo(file));
      this.notice.set('Logo cargado. Guarda el perfil para publicarlo.');
    } catch (failure) {
      this.saveError.set(toAppError(failure));
    } finally {
      this.uploading.set(false);
    }
  }

  protected removeLogo(): void {
    this.logoRef.set(null);
  }

  protected async onSubmit(event: Event): Promise<void> {
    event.preventDefault();
    this.saveError.set(null);
    this.notice.set(null);

    const payload = toProfilePayload(this.draft(), this.logoRef());
    const errors = validatePublicProfile(payload, this.currencies());
    this.errors.set(errors);
    if (Object.keys(errors).length > 0) {
      return;
    }

    await submit(this.profileForm, async () => {
      try {
        const saved = await this.api.saveProfile(payload);
        this.apply(saved);
        this.notice.set('El perfil público se guardó.');
      } catch (failure) {
        this.saveError.set(toAppError(failure));
        const field = serverField(failure);
        if (field) {
          this.errors.set({ [field]: 'Revisa este campo.' });
        }
      }
      return undefined;
    });
  }

  private async load(): Promise<void> {
    this.loading.set(true);
    this.loadError.set(null);
    try {
      const settings = await this.api.getProfile();
      this.currencies.set(settings.supported_currencies ?? ['COP']);
      this.apply(settings);
    } catch (failure) {
      this.loadError.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }

  private apply(profile: PublicProfile): void {
    this.draft.set(toDraft(profile));
    this.logoRef.set(profile.logo_ref);
    this.updatedAt.set(profile.updated_at);
    this.updatedBy.set(profile.updated_by_name);
    this.errors.set({});
    this.baseline = this.snapshot();
  }

  private snapshot(): string {
    return JSON.stringify({ draft: this.draft(), logo: this.logoRef() });
  }
}

/** The RPC names the offending field in the error detail. */
function serverField(failure: unknown): PublicProfileField | null {
  const source = (failure as { cause?: unknown } | null)?.cause ?? failure;
  const details = (source as { details?: unknown } | null)?.details;
  const known: PublicProfileField[] = [
    'commercial_name',
    'logo_ref',
    'primary_color',
    'contact_email',
    'contact_phone',
    'whatsapp',
    'social_links',
    'languages',
    'currency',
  ];
  return typeof details === 'string' && (known as string[]).includes(details)
    ? (details as PublicProfileField)
    : null;
}
