import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { form, FormField } from '@angular/forms/signals';
import { toAppError, type AppError } from '../../../core/error/error-handler';
import {
  AUDIT_PAGE_SIZE_DEFAULT,
  type AuditEventType,
  type AuditLogEntry,
} from '../../../core/audit/models/audit-event.model';
import { AuditService } from '../../../core/audit/services/audit.service';
import type { UserProfile } from '../../../core/auth/models/user.model';
import { UserService } from '../../users/services/user.service';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';

const EVENT_TYPES: readonly AuditEventType[] = [
  'login_success',
  'login_failure',
  'logout',
  'session_expired',
  'user_created',
  'user_updated',
  'user_activated',
  'user_deactivated',
  'role_changed',
  'password_changed',
  'password_reset_forced',
  'organization_created',
  'account_locked',
  'account_unlocked',
];

const EVENT_TYPE_LABELS: Readonly<Record<AuditEventType, string>> = {
  login_success: 'Inicio de sesión',
  login_failure: 'Intento fallido',
  logout: 'Cierre de sesión',
  session_expired: 'Sesión expirada',
  user_created: 'Usuario creado',
  user_updated: 'Usuario actualizado',
  user_activated: 'Usuario activado',
  user_deactivated: 'Usuario desactivado',
  role_changed: 'Cambio de rol',
  password_changed: 'Contraseña cambiada',
  password_reset_forced: 'Contraseña temporal forzada',
  organization_created: 'Organización creada',
  account_locked: 'Cuenta bloqueada',
  account_unlocked: 'Cuenta desbloqueada',
};

/**
 * Immutable security log viewer (User Story 4). Admin-only via `roleGuard` and RLS.
 */
@Component({
  selector: 'app-audit-log',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, FormField, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <header>
        <h1>Auditoría</h1>
      </header>

      <form class="filters" (submit)="onFilter($event)" novalidate>
        <label for="event-type">Tipo de evento</label>
        <select id="event-type" [formField]="filterForm.eventType">
          <option value="">Todos</option>
          @for (type of eventTypes; track type) {
            <option [value]="type">{{ eventLabel(type) }}</option>
          }
        </select>

        <label for="actor">Actor</label>
        <select id="actor" [formField]="filterForm.actorId">
          <option value="">Todos</option>
          @for (actor of actors(); track actor.id) {
            <option [value]="actor.id">{{ actor.full_name }}</option>
          }
        </select>

        <label for="from">Desde</label>
        <input id="from" type="date" [formField]="filterForm.from" />

        <label for="to">Hasta</label>
        <input id="to" type="date" [formField]="filterForm.to" />

        <button type="submit">Filtrar</button>
      </form>

      @if (loading()) {
        <app-spinner />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (events().length === 0) {
        <p>No hay eventos para los filtros seleccionados.</p>
      } @else {
        <table>
          <thead>
            <tr>
              <th>Fecha</th>
              <th>Evento</th>
              <th>Actor</th>
              <th>Resultado</th>
              <th>Recurso</th>
            </tr>
          </thead>
          <tbody>
            @for (event of events(); track event.id) {
              <tr>
                <td>{{ event.created_at | date: 'short' }}</td>
                <td>{{ eventLabel(event.event_type) }}</td>
                <td>{{ event.actor_name ?? 'Sistema' }}</td>
                <td>{{ event.result }}</td>
                <td>{{ event.resource_type ?? '—' }}</td>
              </tr>
            }
          </tbody>
        </table>

        <nav class="pager">
          <button type="button" [disabled]="offset() === 0" (click)="goTo(offset() - limit())">
            Anterior
          </button>
          <span>{{ pageLabel() }}</span>
          <button
            type="button"
            [disabled]="offset() + events().length >= total()"
            (click)="goTo(offset() + limit())"
          >
            Siguiente
          </button>
        </nav>
      }
    </main>
  `,
  styles: `
    .page {
      padding: 1.5rem;
      display: grid;
      gap: 1rem;
    }

    header {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 1rem;
    }

    h1 {
      margin: 0.25rem 0 0;
    }

    .filters {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
      gap: 0.5rem 1rem;
      align-items: end;
    }

    label {
      font-weight: 600;
    }

    table {
      width: 100%;
      border-collapse: collapse;
    }

    th,
    td {
      text-align: left;
      padding: 0.4rem 0.5rem;
      border-bottom: 1px solid #ddd;
    }

    .pager {
      display: flex;
      gap: 1rem;
      align-items: center;
    }
  `,
})
export class AuditLogComponent {
  private readonly audit = inject(AuditService);
  private readonly usersApi = inject(UserService);

  protected readonly eventTypes = EVENT_TYPES;

  protected readonly filters = signal({
    eventType: '',
    actorId: '',
    from: '',
    to: '',
  });

  protected readonly filterForm = form(this.filters);

  protected readonly events = signal<AuditLogEntry[]>([]);
  protected readonly actors = signal<UserProfile[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);
  protected readonly total = signal(0);
  protected readonly offset = signal(0);
  protected readonly limit = signal(AUDIT_PAGE_SIZE_DEFAULT);

  constructor() {
    void this.bootstrap();
  }

  protected eventLabel(type: AuditEventType): string {
    return EVENT_TYPE_LABELS[type];
  }

  protected pageLabel(): string {
    const start = this.total() === 0 ? 0 : this.offset() + 1;
    const end = this.offset() + this.events().length;
    return `${start}–${end} de ${this.total()}`;
  }

  protected onFilter(event: Event): void {
    event.preventDefault();
    this.offset.set(0);
    void this.load();
  }

  protected goTo(nextOffset: number): void {
    this.offset.set(Math.max(0, nextOffset));
    void this.load();
  }

  private async bootstrap(): Promise<void> {
    try {
      this.actors.set(await this.usersApi.list());
    } catch (failure) {
      this.error.set(toAppError(failure));
      this.loading.set(false);
      return;
    }
    await this.load();
  }

  private async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    const current = this.filters();
    try {
      const page = await this.audit.list({
        eventType: (current.eventType || undefined) as AuditEventType | undefined,
        actorId: current.actorId || undefined,
        from: current.from ? startOfDay(current.from) : undefined,
        to: current.to ? endOfDay(current.to) : undefined,
        limit: this.limit(),
        offset: this.offset(),
      });
      this.events.set(page.events);
      this.total.set(page.count);
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}

function startOfDay(isoDate: string): string {
  return `${isoDate}T00:00:00.000`;
}

function endOfDay(isoDate: string): string {
  return `${isoDate}T23:59:59.999`;
}
