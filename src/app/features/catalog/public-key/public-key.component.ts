import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import {
  KEY_ROTATION_GRACE_DAYS,
  KEY_STATUS_LABELS,
  type GeneratedPublicAccessKey,
  type PublicAccessKey,
} from '../../../core/catalog/models/public-agency-config.model';
import { PublicAgencyConfigService } from '../../../core/catalog/services/public-agency-config.service';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';

/**
 * Public access key (feature 016, US2). Administrator only: the route guard and the RPCs both
 * enforce it. The clear key is shown once, right after generating it, and is never stored here.
 */
@Component({
  selector: 'app-public-key',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <header class="page-head">
        <a routerLink="/cms/settings">Ajustes del catálogo</a>
        <h1>Clave pública</h1>
        <p class="hint">
          Tu página web o cualquier vitrina usa esta clave para leer tu catálogo publicado y enviar
          solicitudes de viajeros. No da acceso al panel ni a datos internos.
        </p>
      </header>

      @if (generated(); as fresh) {
        <section class="card reveal" aria-live="polite">
          <h2>Copia tu clave ahora</h2>
          <p>Por seguridad no la volveremos a mostrar. Si la pierdes, genera una nueva.</p>
          <div class="key-row">
            <code class="key">{{ fresh.key }}</code>
            <button type="button" class="primary" (click)="copy(fresh.key)">
              {{ copied() ? 'Copiada' : 'Copiar' }}
            </button>
          </div>
          @if (fresh.previous_key_expires_at) {
            <app-alert kind="info">
              La clave anterior seguirá funcionando hasta el
              {{ fresh.previous_key_expires_at | date: 'd MMM y, h:mm a' }}
              ({{ graceDays }} días). Actualiza tu página antes de esa fecha.
            </app-alert>
          }
          <div class="form-actions">
            <button type="button" (click)="dismiss()">Ya la guardé</button>
          </div>
        </section>
      }

      @if (loading()) {
        <app-spinner label="Cargando claves…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else {
        <section class="card">
          <h2>Claves</h2>
          @if (keys().length === 0) {
            <p>Tu agencia aún no tiene clave pública. Genérala para conectar tu página.</p>
          } @else {
            <div class="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Clave</th>
                    <th>Estado</th>
                    <th>Creada</th>
                    <th>Último uso</th>
                    <th><span class="visually-hidden">Acciones</span></th>
                  </tr>
                </thead>
                <tbody>
                  @for (key of keys(); track key.id) {
                    <tr [class.muted]="key.status === 'expired' || key.status === 'revoked'">
                      <td>
                        <code>{{ key.key_prefix }}…</code>
                      </td>
                      <td>
                        <span class="status" [attr.data-status]="key.status">{{
                          statusLabel[key.status]
                        }}</span>
                        @if (key.status === 'grace' && key.expires_at) {
                          <div class="hint">
                            Funciona hasta el {{ key.expires_at | date: 'd MMM, h:mm a' }}
                          </div>
                        }
                        @if (key.status === 'revoked' && key.revoked_at) {
                          <div class="hint">
                            {{ key.revoked_at | date: 'd MMM y' }}
                            @if (key.revoked_by_name) {
                              · {{ key.revoked_by_name }}
                            }
                          </div>
                        }
                      </td>
                      <td>
                        {{ key.created_at | date: 'd MMM y' }}
                        @if (key.created_by_name) {
                          <div class="hint">{{ key.created_by_name }}</div>
                        }
                      </td>
                      <td>
                        {{ key.last_used_at ? (key.last_used_at | date: 'd MMM, h:mm a') : '—' }}
                      </td>
                      <td class="row-actions">
                        @if (key.status === 'current' || key.status === 'grace') {
                          <button
                            type="button"
                            class="link danger"
                            [disabled]="busy()"
                            (click)="onRevoke(key)"
                          >
                            Revocar
                          </button>
                        }
                      </td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
          }

          <div class="form-actions">
            <button type="button" class="primary" [disabled]="busy()" (click)="onGenerate()">
              {{ busy() ? 'Procesando…' : hasCurrent() ? 'Regenerar clave' : 'Generar clave' }}
            </button>
          </div>
          <p class="hint">
            Regenerar crea una clave nueva; la anterior sigue funcionando {{ graceDays }} días para
            que actualices tu página. Revocar corta una clave de inmediato.
          </p>
        </section>
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

    .reveal {
      border-color: var(--color-primary-border);
      background: var(--color-primary-tint);
    }

    .key-row {
      display: flex;
      flex-wrap: wrap;
      gap: 0.5rem;
      align-items: center;
      margin: 0.5rem 0;
    }

    .key {
      flex: 1 1 18rem;
      min-width: 0;
      padding: 0.6rem 0.75rem;
      border: 1px solid var(--color-border);
      border-radius: 0.5rem;
      background: var(--color-surface);
      font-size: 0.9rem;
      overflow-wrap: anywhere;
    }

    table {
      width: 100%;
      border-collapse: collapse;
    }

    th,
    td {
      text-align: left;
      padding: 0.5rem;
      border-bottom: 1px solid var(--color-border);
      vertical-align: top;
    }

    tr.muted td {
      color: var(--color-text-muted);
    }

    .status {
      font-weight: 600;
    }

    .status[data-status='current'] {
      color: var(--color-primary);
    }

    .status[data-status='revoked'] {
      color: var(--color-danger);
    }

    .row-actions {
      text-align: right;
      white-space: nowrap;
    }
  `,
})
export class PublicKeyComponent {
  private readonly api = inject(PublicAgencyConfigService);

  protected readonly graceDays = KEY_ROTATION_GRACE_DAYS;
  protected readonly statusLabel = KEY_STATUS_LABELS;

  protected readonly keys = signal<PublicAccessKey[]>([]);
  protected readonly generated = signal<GeneratedPublicAccessKey | null>(null);
  protected readonly loading = signal(true);
  protected readonly busy = signal(false);
  protected readonly copied = signal(false);
  protected readonly error = signal<AppError | null>(null);
  protected readonly actionError = signal<AppError | null>(null);
  protected readonly notice = signal<string | null>(null);

  protected readonly hasCurrent = computed(() =>
    this.keys().some((key) => key.status === 'current'),
  );

  constructor() {
    void this.refresh();
  }

  protected async onGenerate(): Promise<void> {
    if (
      this.hasCurrent() &&
      !confirm(
        `Se creará una clave nueva. La actual seguirá funcionando ${KEY_ROTATION_GRACE_DAYS} días y luego dejará de servir. ¿Continuar?`,
      )
    ) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);
    this.busy.set(true);
    try {
      this.copied.set(false);
      this.generated.set(await this.api.generateKey());
      await this.refresh();
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.busy.set(false);
    }
  }

  protected async onRevoke(key: PublicAccessKey): Promise<void> {
    if (
      !confirm(
        `¿Revocar la clave ${key.key_prefix}…? Deja de funcionar de inmediato y no se puede deshacer.`,
      )
    ) {
      return;
    }
    this.actionError.set(null);
    this.notice.set(null);
    this.busy.set(true);
    try {
      await this.api.revokeKey(key.id);
      if (this.generated()?.id === key.id) {
        this.generated.set(null);
      }
      await this.refresh();
      this.notice.set(`La clave ${key.key_prefix}… quedó revocada.`);
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.busy.set(false);
    }
  }

  protected async copy(value: string): Promise<void> {
    try {
      await navigator.clipboard.writeText(value);
      this.copied.set(true);
    } catch {
      this.copied.set(false);
    }
  }

  protected dismiss(): void {
    this.generated.set(null);
    this.copied.set(false);
  }

  private async refresh(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.keys.set(await this.api.listKeys());
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
