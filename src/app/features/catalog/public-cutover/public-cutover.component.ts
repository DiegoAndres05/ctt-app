import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import type { CutoverStatus } from '../../../core/catalog/models/public-listing.model';
import { PublicListingService } from '../../../core/catalog/services/public-listing.service';
import { AuthService } from '../../../core/auth/services/auth.service';
import { hasRoleAtLeast } from '../../../core/auth/models/user.model';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';

/**
 * Public site source cutover (feature 009). Completing the switch is admin-only.
 */
@Component({
  selector: 'app-public-cutover',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <header>
        <div>
          <a routerLink="/catalog">Catálogo</a>
          <h1>Cambio de fuente</h1>
        </div>
      </header>

      <p class="notice">
        Mientras la fuente sea «legacy», la página pública sigue su contenido embebido. Al
        completar el cambio, pasa a leer solo fichas publicadas del panel.
      </p>

      @if (loading()) {
        <app-spinner label="Cargando estado del cambio…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (status(); as current) {
        <dl>
          <dt>Fuente actual</dt>
          <dd>{{ current.site?.source === 'panel' ? 'Panel' : 'Legacy (contenido embebido)' }}</dd>
          @if (current.site?.cutover_completed_at) {
            <dt>Completado</dt>
            <dd>{{ current.site.cutover_completed_at | date: 'short' }}</dd>
          }
          <dt>Ítems del manifiesto</dt>
          <dd>{{ current.items.length }}</dd>
          <dt>Faltantes</dt>
          <dd>{{ current.missing_slugs.length }}</dd>
        </dl>

        @if (current.missing_slugs.length > 0) {
          <section class="card">
            <h2>Slugs pendientes de publicar</h2>
            <ul>
              @for (slug of current.missing_slugs; track slug) {
                <li>{{ slug }}</li>
              }
            </ul>
          </section>
        } @else if (current.site?.source !== 'panel') {
          <app-alert kind="info">
            Todos los ítems del manifiesto están publicados y activos. Un administrador puede
            completar el cambio.
          </app-alert>
        }

        @if (canComplete() && current.site?.source !== 'panel') {
          <button type="button" [disabled]="busy()" (click)="onComplete()">
            {{ busy() ? 'Completando…' : 'Completar cambio de fuente' }}
          </button>
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
      justify-items: start;
    }

    h1,
    h2 {
      margin: 0.25rem 0 0;
    }

    .notice {
      margin: 0;
    }

    dl {
      display: grid;
      grid-template-columns: auto 1fr;
      gap: 0.25rem 1rem;
    }

    dt {
      font-weight: 600;
    }

    dd {
      margin: 0;
    }

    .card {
      display: grid;
      gap: 0.5rem;
    }

    ul {
      margin: 0;
      padding-left: 1.25rem;
      columns: 2;
    }

    button {
      padding: 0.6rem 1rem;
    }
  `,
})
export class PublicCutoverComponent {
  private readonly api = inject(PublicListingService);
  private readonly auth = inject(AuthService);

  protected readonly status = signal<CutoverStatus | null>(null);
  protected readonly loading = signal(true);
  protected readonly busy = signal(false);
  protected readonly error = signal<AppError | null>(null);
  protected readonly actionError = signal<AppError | null>(null);
  protected readonly notice = signal<string | null>(null);

  constructor() {
    void this.refresh();
  }

  protected canComplete(): boolean {
    return hasRoleAtLeast(this.auth.role(), 'admin');
  }

  protected async onComplete(): Promise<void> {
    this.actionError.set(null);
    this.notice.set(null);
    this.busy.set(true);
    try {
      await this.api.completeCutover();
      await this.refresh();
      this.notice.set('La página pública ahora lee del panel.');
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
      this.status.set(await this.api.getCutoverStatus());
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
