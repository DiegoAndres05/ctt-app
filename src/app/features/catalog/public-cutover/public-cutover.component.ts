import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import type { CutoverStatus } from '../../../core/catalog/models/public-listing.model';
import {
  isIdentifierAccessOpen,
  type PublicSourceConfig,
} from '../../../core/catalog/models/public-agency-config.model';
import { PublicListingService } from '../../../core/catalog/services/public-listing.service';
import { PublicAgencyConfigService } from '../../../core/catalog/services/public-agency-config.service';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';

/**
 * Public site source (features 009 and 016). Administrator only (route guard + RPCs).
 *
 * An agency migrating an existing site must publish every manifest item before the cutover; a new
 * agency publishes directly. A migrated agency (CTT) may also have the temporary
 * organization-identifier access, which the administrator closes here.
 */
@Component({
  selector: 'app-public-cutover',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <header class="page-head">
        <a routerLink="/cms/settings">Ajustes del catálogo</a>
        <h1>Publicación del sitio</h1>
      </header>

      @if (loading()) {
        <app-spinner label="Cargando estado del sitio…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (status(); as current) {
        <section class="card">
          <h2>Cómo llega tu catálogo al sitio</h2>
          <dl class="facts">
            <div>
              <dt>Modo</dt>
              <dd>
                {{
                  migrationRequired() ? 'Migración desde un sitio existente' : 'Publicación directa'
                }}
              </dd>
            </div>
            <div>
              <dt>Fuente</dt>
              <dd>
                @if (isPanel()) {
                  Panel desde el {{ current.site?.cutover_completed_at | date: 'd MMM y' }}
                } @else if (migrationRequired()) {
                  Contenido del sitio anterior (aún no se completa el cambio)
                } @else {
                  Panel: lo que publicas aparece en el sitio
                }
              </dd>
            </div>
          </dl>

          @if (!isPanel()) {
            <p class="hint">
              @if (migrationRequired()) {
                Tu sitio ya tenía contenido. Mientras falte publicar alguna ficha del manifiesto, el
                sitio sigue mostrando el contenido anterior.
              } @else {
                Tu agencia no viene de otro sitio: las fichas publicadas se muestran sin pasos de
                copia.
              }
            </p>
            <div class="form-actions">
              <button type="button" [disabled]="busy()" (click)="onToggleMigration()">
                {{
                  migrationRequired()
                    ? 'Cambiar a publicación directa'
                    : 'Marcar como migración desde un sitio existente'
                }}
              </button>
            </div>
          }
        </section>

        @if (migrationRequired() && !isPanel()) {
          <section class="card">
            <h2>Manifiesto del sitio anterior</h2>
            <dl class="facts">
              <div>
                <dt>Fichas a publicar</dt>
                <dd>{{ current.items.length }}</dd>
              </div>
              <div>
                <dt>Faltan</dt>
                <dd>{{ current.missing_slugs.length }}</dd>
              </div>
            </dl>

            @if (current.missing_slugs.length > 0) {
              <p class="hint">Publica una ficha con cada uno de estos identificadores:</p>
              <ul class="slugs">
                @for (slug of current.missing_slugs; track slug) {
                  <li>
                    <code>{{ slug }}</code>
                  </li>
                }
              </ul>
            } @else {
              <app-alert kind="info">
                Todas las fichas del manifiesto están publicadas y activas. Ya puedes completar el
                cambio.
              </app-alert>
            }

            <div class="form-actions">
              <button
                type="button"
                class="primary"
                [disabled]="busy() || current.missing_slugs.length > 0"
                (click)="onComplete()"
              >
                {{ busy() ? 'Completando…' : 'Completar cambio de fuente' }}
              </button>
            </div>
          </section>
        }

        @if (sourceConfig()?.migration_required && sourceConfig()?.organization_identifier_until) {
          <section class="card">
            <h2>Acceso por identificador de organización</h2>
            @if (identifierOpen()) {
              <p>
                Mientras tu página pasa a la clave pública, puede seguir usando el identificador de
                organización hasta el
                <strong>{{
                  sourceConfig()!.organization_identifier_until | date: 'd MMM y'
                }}</strong
                >.
              </p>
              <p class="hint">
                Cuando tu página ya use la
                <a routerLink="/cms/settings/public-key">clave pública</a>, cierra este acceso.
              </p>
              <div class="form-actions">
                <button
                  type="button"
                  class="danger"
                  [disabled]="busy()"
                  (click)="onEndTransition()"
                >
                  Cerrar acceso por identificador
                </button>
              </div>
            } @else {
              <p>
                Cerrado desde el
                {{ sourceConfig()!.organization_identifier_until | date: 'd MMM y' }}. Tu página
                solo funciona con la clave pública.
              </p>
            }
          </section>
        }
      }

      @if (actionError(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      }
      @if (notice(); as message) {
        <app-alert kind="success">{{ message }}</app-alert>
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

    .card h2 {
      margin: 0 0 0.5rem;
    }

    .slugs {
      margin: 0;
      padding-left: 1.25rem;
      columns: 2;
    }

    @media (max-width: 640px) {
      .slugs {
        columns: 1;
      }
    }
  `,
})
export class PublicCutoverComponent {
  private readonly api = inject(PublicListingService);
  private readonly config = inject(PublicAgencyConfigService);

  protected readonly status = signal<CutoverStatus | null>(null);
  protected readonly sourceConfig = signal<PublicSourceConfig | null>(null);
  protected readonly loading = signal(true);
  protected readonly busy = signal(false);
  protected readonly error = signal<AppError | null>(null);
  protected readonly actionError = signal<AppError | null>(null);
  protected readonly notice = signal<string | null>(null);

  protected readonly migrationRequired = computed(
    () => this.sourceConfig()?.migration_required ?? false,
  );
  protected readonly isPanel = computed(() => this.status()?.site?.source === 'panel');
  protected readonly identifierOpen = computed(() => isIdentifierAccessOpen(this.sourceConfig()));

  constructor() {
    void this.refresh();
  }

  protected async onToggleMigration(): Promise<void> {
    const next = !this.migrationRequired();
    const message = next
      ? 'El sitio dejará de mostrar el catálogo del panel hasta que se publiquen todas las fichas del manifiesto. ¿Continuar?'
      : 'Las fichas publicadas se mostrarán de inmediato, sin esperar el manifiesto. ¿Continuar?';
    if (!confirm(message)) {
      return;
    }
    await this.run(async () => {
      await this.config.setMigrationRequired(next);
      return next ? 'Tu agencia quedó en modo migración.' : 'Tu agencia publica directamente.';
    });
  }

  protected async onComplete(): Promise<void> {
    await this.run(async () => {
      await this.api.completeCutover();
      return 'El sitio ahora muestra solo lo publicado en el panel.';
    });
  }

  protected async onEndTransition(): Promise<void> {
    if (
      !confirm(
        'Tu página dejará de funcionar si todavía usa el identificador de organización. Este cambio no se puede deshacer. ¿Cerrar el acceso?',
      )
    ) {
      return;
    }
    await this.run(async () => {
      await this.config.endIdentifierTransition();
      return 'El acceso por identificador quedó cerrado. Solo funciona la clave pública.';
    });
  }

  private async run(action: () => Promise<string>): Promise<void> {
    this.actionError.set(null);
    this.notice.set(null);
    this.busy.set(true);
    try {
      const message = await action();
      await this.refresh();
      this.notice.set(message);
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.busy.set(false);
    }
  }

  private async refresh(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      const [status, config] = await Promise.all([
        this.api.getCutoverStatus(),
        this.config.getSourceConfig(),
      ]);
      this.status.set(status);
      this.sourceConfig.set(config);
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
