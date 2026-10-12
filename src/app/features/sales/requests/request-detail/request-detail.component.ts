import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, effect, inject, input, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../../../core/auth/services/auth.service';
import { customerDisplayName } from '../../../../core/customers/models/customer.model';
import {
  REQUEST_CHANNEL_LABELS,
  REQUEST_STATUS_LABELS,
  availableStatusActions,
  isRequestClosed,
  type InboundMessage,
  type ManualRequestStatus,
  type RequestDetail,
} from '../../../../core/customers/models/request.model';
import {
  PRE_RESERVATION_STATUS_LABELS,
  type PreReservationListRow,
} from '../../../../core/pre-reservations/models/pre-reservation.model';
import { PreReservationService } from '../../../../core/pre-reservations/services/pre-reservation.service';
import {
  RequestService,
  type AssigneeOption,
} from '../../../../core/customers/services/request.service';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { NotesSectionComponent } from '../../shared/notes-section.component';

@Component({
  selector: 'app-request-detail',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, AlertComponent, SpinnerComponent, NotesSectionComponent],
  template: `
    <div class="stack">
      <button type="button" class="button-link" (click)="goBack()">Volver a solicitudes</button>

      @if (loading()) {
        <app-spinner label="Cargando solicitud…" />
      } @else if (loadError(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (request(); as current) {
        @if (deduplicated()) {
          <app-alert kind="info">Ya existía una solicitud igual; se abrió la existente.</app-alert>
        }
        @if (actionError(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        }

        <header class="heading">
          <h1>{{ current.reference }}</h1>
          <p>{{ statusLabel(current.status) }}</p>
        </header>

        <section class="section">
          <h2>Resumen</h2>
          <p>Canal: {{ channelLabel(current.channel) }}</p>
          <p>Recibida: {{ current.created_at | date: 'short' }}</p>
          <p>Fechas de viaje: {{ travelDates(current) }}</p>
          <p>Adultos: {{ current.adults }} · Niños: {{ current.children }}</p>
          <p>Consentimiento registrado: {{ current.privacy_consent_at ? 'Sí' : 'No' }}</p>
          <p>Página de origen: {{ current.source_page || '—' }}</p>
        </section>

        <section class="section">
          <h2>Cliente</h2>
          <p>
            <a [routerLink]="['/sales/customers', current.customer_id]">{{ name(current) }}</a>
          </p>
          <p>Correo: {{ current.customer.email || '—' }}</p>
          <p>Teléfono: {{ current.customer.phone_e164 || '—' }}</p>
          @if (current.contact_review_required) {
            <app-alert kind="warning">
              Datos de contacto a revisar.
              @if (current.submitted_contact; as submitted) {
                {{ submitted.first_name }}
                {{ submitted.last_name }}
                {{ submitted.email }}
                {{ submitted.phone_e164 }}
              }
            </app-alert>
          }
        </section>

        <section class="section">
          <h2>Intereses</h2>
          @if (current.items.length === 0) {
            <p>—</p>
          } @else {
            <ul>
              @for (item of current.items; track item.id) {
                <li>
                  {{ item.product?.name || item.free_text || '—' }}
                  · cantidad {{ item.quantity }}
                  @if (item.public_slug) {
                    · {{ item.public_slug }}
                  }
                </li>
              }
            </ul>
          }
        </section>

        <section class="section">
          <h2>Requerimientos del cliente</h2>
          <p>{{ current.special_requirements || '—' }}</p>
        </section>

        @if (current.channel === 'whatsapp') {
          <section class="section">
            <h2>Conversación</h2>
            @if (messages().length === 0) {
              <p>No hay mensajes recibidos por WhatsApp para esta solicitud.</p>
            } @else {
              <ul class="messages">
                @for (message of messages(); track message.id) {
                  <li>
                    <strong>{{ message.profile_name || 'Contacto WhatsApp' }}</strong>
                    <time [attr.datetime]="message.provider_timestamp">
                      {{ message.provider_timestamp | date: 'short' }}
                    </time>
                    <p>{{ message.body }}</p>
                  </li>
                }
              </ul>
            }
          </section>
        }

        <section class="section" [class.is-disabled]="closed()">
          <h2>Gestión</h2>
          <p>Responsable: {{ current.assignee?.full_name || '—' }}</p>
          @if (!closed()) {
            <label for="assignee">Asignar a</label>
            <select id="assignee" (change)="onAssign($event)">
              <option value="">Sin asignar</option>
              @for (person of assignees(); track person.id) {
                <option [value]="person.id" [selected]="person.id === current.assigned_to">
                  {{ person.full_name }}
                </option>
              }
            </select>
            <div class="actions">
              <button type="button" (click)="assignToMe()" [disabled]="busy()">Asignarme</button>
              @for (action of actions(); track action) {
                @if (action === 'in_review') {
                  <button type="button" class="primary" (click)="setReview()" [disabled]="busy()">
                    Pasar a En gestión
                  </button>
                }
              }
            </div>
            @if (actions().includes('discarded')) {
              <label class="req" for="discard-reason">Motivo del descarte</label>
              <textarea
                id="discard-reason"
                rows="2"
                [value]="discardReason()"
                (input)="onReason($event)"
              ></textarea>
              <button type="button" (click)="discard()" [disabled]="busy()">Descartar</button>
            }
          }
          @if (canCreatePreReservation()) {
            <div class="actions">
              <a
                class="primary button-link"
                routerLink="/sales/pre-reservations/new"
                [queryParams]="{ requestId: current.id }"
              >
                Crear pre-reserva
              </a>
            </div>
          } @else {
            <p>La pre-reserva se crea desde el módulo de pre-reservas.</p>
          }
        </section>

        <section class="section">
          <h2>Pre-reservas</h2>
          @if (preReservationsError(); as failure) {
            <app-alert kind="error">{{ failure }}</app-alert>
          } @else if (linkedPreReservations().length === 0) {
            <p>Esta solicitud todavía no tiene pre-reservas.</p>
          } @else {
            <table class="data">
              <thead>
                <tr>
                  <th>Referencia</th>
                  <th>Estado</th>
                  <th>Creada</th>
                </tr>
              </thead>
              <tbody>
                @for (preReservation of linkedPreReservations(); track preReservation.id) {
                  <tr>
                    <td>
                      <a [routerLink]="['/sales/pre-reservations', preReservation.id]">
                        {{ preReservation.reference }}
                      </a>
                    </td>
                    <td>{{ preReservationStatusLabel(preReservation.status) }}</td>
                    <td>{{ preReservation.created_at | date: 'short' }}</td>
                  </tr>
                }
              </tbody>
            </table>
          }
        </section>

        <app-notes-section [target]="{ requestId: current.id }" />
      } @else {
        <p>No encontramos esta solicitud.</p>
      }
    </div>
  `,
  styles: `
    .stack {
      display: grid;
      gap: 0.85rem;
    }

    .heading {
      display: flex;
      align-items: baseline;
      gap: 1rem;
    }

    .heading h1,
    .heading p {
      margin: 0;
    }

    .messages {
      list-style: none;
      margin: 0;
      padding: 0;
      display: grid;
      gap: 0.75rem;
    }
  `,
})
export class RequestDetailComponent {
  private readonly requests = inject(RequestService);
  private readonly preReservations = inject(PreReservationService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  readonly id = input.required<string>();

  protected readonly loading = signal(true);
  protected readonly busy = signal(false);
  protected readonly loadError = signal<AppError | null>(null);
  protected readonly actionError = signal<AppError | null>(null);
  protected readonly request = signal<RequestDetail | null>(null);
  protected readonly messages = signal<InboundMessage[]>([]);
  protected readonly assignees = signal<AssigneeOption[]>([]);
  protected readonly discardReason = signal('');
  protected readonly deduplicated = signal(readDeduplicated());
  protected readonly linkedPreReservations = signal<PreReservationListRow[]>([]);
  protected readonly preReservationsError = signal<string | null>(null);
  protected readonly statusLabel = (status: RequestDetail['status']) =>
    REQUEST_STATUS_LABELS[status];
  protected readonly channelLabel = (channel: RequestDetail['channel']) =>
    REQUEST_CHANNEL_LABELS[channel];
  protected readonly preReservationStatusLabel = (status: PreReservationListRow['status']) =>
    PRE_RESERVATION_STATUS_LABELS[status];

  constructor() {
    effect(() => {
      const id = this.id();
      void this.load(id);
    });
    void this.loadAssignees();
  }

  protected closed(): boolean {
    const current = this.request();
    return current ? isRequestClosed(current.status) : false;
  }

  /** The «Crear pre-reserva» CTA: open requests with a real (non-anonymized) customer. */
  protected canCreatePreReservation(): boolean {
    const current = this.request();
    if (!current || current.customer.is_anonymized) {
      return false;
    }
    return (
      current.status === 'received' ||
      current.status === 'in_review' ||
      current.status === 'pre_reservation'
    );
  }

  protected actions(): ManualRequestStatus[] {
    const current = this.request();
    return current ? availableStatusActions(current.status) : [];
  }

  protected name(current: RequestDetail): string {
    return customerDisplayName(current.customer);
  }

  protected travelDates(current: RequestDetail): string {
    const start = formatDay(current.travel_start_date);
    const end = formatDay(current.travel_end_date);
    if (start === '—' && end === '—') {
      return '—';
    }
    if (end === '—') {
      return start;
    }
    if (start === '—') {
      return end;
    }
    return `${start} – ${end}`;
  }

  protected goBack(): void {
    const state = history.state as { navigationId?: number } | null;
    if (state && typeof state.navigationId === 'number' && state.navigationId > 1) {
      history.back();
      return;
    }
    void this.router.navigate(['/sales/requests']);
  }

  protected async onAssign(event: Event): Promise<void> {
    const value = (event.target as HTMLSelectElement).value;
    await this.run(() => this.requests.assign(this.id(), value || null));
  }

  protected async assignToMe(): Promise<void> {
    const userId = this.auth.user()?.id;
    if (!userId) {
      return;
    }
    await this.run(() => this.requests.assign(this.id(), userId));
  }

  protected async setReview(): Promise<void> {
    await this.run(() => this.requests.setStatus(this.id(), 'in_review'));
  }

  protected onReason(event: Event): void {
    this.discardReason.set((event.target as HTMLTextAreaElement).value);
  }

  protected async discard(): Promise<void> {
    const reason = this.discardReason().trim();
    if (!reason) {
      this.actionError.set(toAppError({ message: 'DISCARD_REASON_REQUIRED' }));
      return;
    }
    if (!window.confirm('¿Descartar esta solicitud?')) {
      return;
    }
    await this.run(() => this.requests.setStatus(this.id(), 'discarded', reason));
  }

  private async run(action: () => Promise<void>): Promise<void> {
    this.busy.set(true);
    this.actionError.set(null);
    try {
      await action();
      await this.load(this.id());
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.busy.set(false);
    }
  }

  private async load(id: string): Promise<void> {
    this.loading.set(true);
    this.loadError.set(null);
    try {
      const detail = await this.requests.getById(id);
      this.request.set(detail);
      if (detail?.channel === 'whatsapp') {
        this.messages.set(await this.requests.listMessages(id));
      } else {
        this.messages.set([]);
      }
      await this.loadPreReservations(id);
    } catch (failure) {
      this.loadError.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }

  private async loadPreReservations(id: string): Promise<void> {
    try {
      this.linkedPreReservations.set(await this.preReservations.listForRequest(id));
      this.preReservationsError.set(null);
    } catch (failure) {
      // Secondary read: the request detail stays usable even if this one fails.
      this.linkedPreReservations.set([]);
      this.preReservationsError.set(toAppError(failure).message);
    }
  }

  private async loadAssignees(): Promise<void> {
    try {
      this.assignees.set(await this.requests.listAssignees());
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    }
  }
}

function formatDay(value: string | null): string {
  if (!value) {
    return '—';
  }
  const [year, month, day] = value.slice(0, 10).split('-');
  if (!year || !month || !day) {
    return value;
  }
  return `${day}/${month}/${year}`;
}

function readDeduplicated(): boolean {
  const state = history.state as { deduplicated?: boolean } | null;
  return Boolean(state?.deduplicated);
}
