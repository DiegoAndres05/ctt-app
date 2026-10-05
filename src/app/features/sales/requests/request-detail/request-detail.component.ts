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
          <p>La pre-reserva se crea desde el módulo de pre-reservas.</p>
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
  protected readonly statusLabel = (status: RequestDetail['status']) =>
    REQUEST_STATUS_LABELS[status];
  protected readonly channelLabel = (channel: RequestDetail['channel']) =>
    REQUEST_CHANNEL_LABELS[channel];

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
    } catch (failure) {
      this.loadError.set(toAppError(failure));
    } finally {
      this.loading.set(false);
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
