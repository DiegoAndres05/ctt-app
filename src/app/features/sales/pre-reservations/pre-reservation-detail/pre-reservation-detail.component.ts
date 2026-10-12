import { DatePipe } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  computed,
  effect,
  inject,
  input,
  signal,
} from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { hasRoleAtLeast } from '../../../../core/auth/models/user.model';
import { AuthService } from '../../../../core/auth/services/auth.service';
import type { AssigneeOption } from '../../../../core/customers/services/request.service';
import { customerDisplayName } from '../../../../core/customers/models/customer.model';
import {
  PRE_RESERVATION_STATUS_LABELS,
  quoteEligibilityReason,
  type PreReservation,
  type PreReservationDetail,
  type PreReservationItem,
  type VerificationTimes,
} from '../../../../core/pre-reservations/models/pre-reservation.model';
import {
  AVAILABILITY_EVENT_KIND_LABELS,
  AVAILABILITY_STATUS_LABELS,
  CONTACT_METHOD_LABELS,
  type AvailabilityEventKind,
  type ProviderContactMethod,
  type VerificationEvent,
  type VerificationQueueRow,
} from '../../../../core/pre-reservations/models/verification.model';
import { providerContactLinks } from '../../../../core/pre-reservations/provider-contact-links';
import { AvailabilityVerificationService } from '../../../../core/pre-reservations/services/availability-verification.service';
import {
  PreReservationService,
  type BookableOption,
  type BookableProvider,
  type PreReservationAddItemInput,
} from '../../../../core/pre-reservations/services/pre-reservation.service';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';
import { VerificationOutcomeFormComponent } from '../../verification/verification-outcome-form/verification-outcome-form.component';
import {
  buildCreatePayload,
  emptyItemDraft,
  todayIso,
  validateItemDrafts,
  type PreReservationIssue,
  type PreReservationItemDraft,
} from '../pre-reservation-create/pre-reservation-payload';

/** One rendered table row: a main line followed by its indented alternatives. */
interface ServiceRow {
  item: PreReservationItem;
  alternative: boolean;
}

/**
 * Pre-reservation detail (US1 base + US3 actions + US4 traceability).
 *
 * The «Servicios» table carries the US3 per-row actions (start, record outcome, promote,
 * withdraw) wired through `PreReservationService` and `AvailabilityVerificationService`;
 * every action reloads through `reload()`. US3 also adds the «Agregar servicio» line form
 * (one row built with the US1 payload helpers), the «Operador asignado» selector with
 * «Asignarme», the «Cotización» section with the admin «Autorizar excepción», and
 * «Cancelar pre-reserva». US4 appends the «Historial» and «Tiempos de verificación»
 * sections. The status itself is only ever read here — `refresh_pre_reservation_status`
 * owns it (R-003).
 */
@Component({
  selector: 'app-pre-reservation-detail',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    DatePipe,
    RouterLink,
    AlertComponent,
    SpinnerComponent,
    VerificationOutcomeFormComponent,
  ],
  template: `
    <div class="stack">
      <button type="button" class="button-link" (click)="goBack()">Volver a pre-reservas</button>

      @if (loading()) {
        <app-spinner label="Cargando pre-reserva…" />
      } @else if (loadError(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (detail(); as current) {
        <header class="heading">
          <h1>{{ current.reference }}</h1>
          <p>{{ statusLabel(current.status) }}</p>
        </header>

        <app-alert kind="info">
          Esta pre-reserva no es una reserva confirmada. Requiere verificación de disponibilidad con
          los proveedores.
        </app-alert>

        @if (current.status === 'cancelled') {
          <app-alert kind="warning">Pre-reserva cancelada: {{ current.cancel_reason }}</app-alert>
        }

        @if (actionError(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        }

        <section class="section" [class.is-disabled]="current.status === 'cancelled'">
          <h2>Resumen</h2>
          <p>
            Solicitud:
            @if (current.request; as linkedRequest) {
              <a [routerLink]="['/sales/requests', linkedRequest.id]">
                {{ linkedRequest.reference }}
              </a>
            } @else {
              {{ current.request_id }}
            }
          </p>
          <p>
            Cliente:
            @if (current.customer; as linkedCustomer) {
              <a [routerLink]="['/sales/customers', linkedCustomer.id]">
                {{ customerName(linkedCustomer) }}
              </a>
            } @else {
              —
            }
          </p>
          <p>Responsable: {{ current.agent?.full_name || '—' }}</p>
          <p>Creada: {{ current.created_at | date: 'short' }}</p>
          <p>Vence: {{ current.expires_at ? (current.expires_at | date: 'short') : '—' }}</p>

          <label for="detail-operator">Operador asignado</label>
          <select
            id="detail-operator"
            (change)="onOperatorChange($event)"
            [disabled]="current.status === 'cancelled' || busy()"
          >
            <option value="" [selected]="!current.assigned_operator_id">Sin asignar</option>
            @for (person of operators(); track person.id) {
              <option [value]="person.id" [selected]="person.id === current.assigned_operator_id">
                {{ person.full_name }}
              </option>
            }
          </select>
          <p class="hint">
            Puedes dejarlo sin asignar; quien gestione la verificación aparecerá en el detalle.
          </p>
          @if (canVerify() && current.status !== 'cancelled') {
            <div class="actions">
              <button type="button" (click)="assignToMe()" [disabled]="busy()">Asignarme</button>
            </div>
          }
        </section>

        <section class="section" [class.is-disabled]="current.status === 'cancelled'">
          <h2>Servicios</h2>
          <div class="table-wrap">
            <table class="data">
              <thead>
                <tr>
                  <th>Servicio</th>
                  <th>Fechas</th>
                  <th>Pasajeros</th>
                  <th>Proveedor</th>
                  <th>Estado</th>
                  <th>Retención</th>
                  <th>Verificado por</th>
                  <th>Acciones</th>
                </tr>
              </thead>
              <tbody>
                @for (row of serviceRows(); track row.item.id) {
                  <tr [class.withdrawn]="row.item.withdrawn_at !== null">
                    <td [class.alternative]="row.alternative">
                      @if (row.alternative) {
                        <span class="tag">Alternativa</span>
                      }
                      {{ row.item.item_label }}
                      @if (row.item.withdrawn_at) {
                        <span class="muted">Retirado: {{ row.item.withdrawn_reason }}</span>
                      }
                    </td>
                    <td>{{ itemDates(row.item) }}</td>
                    <td>{{ itemPax(row.item) }}</td>
                    <td>
                      @if (row.item.provider_name; as providerName) {
                        {{ providerName }}
                        @if (contactLinks(row.item); as links) {
                          @if (links.tel) {
                            <a [href]="links.tel">Llamar</a>
                          }
                          @if (links.whatsapp) {
                            <a [href]="links.whatsapp" target="_blank" rel="noopener noreferrer">
                              WhatsApp
                            </a>
                          }
                          @if (links.mailto) {
                            <a [href]="links.mailto">Correo</a>
                          }
                        }
                      } @else {
                        —
                      }
                    </td>
                    <td>{{ availabilityLabel(row.item.verification_status) }}</td>
                    <td>
                      {{
                        row.item.hold_expires_at ? (row.item.hold_expires_at | date: 'short') : '—'
                      }}
                    </td>
                    <td>{{ row.item.verifier?.full_name || '—' }}</td>
                    <td class="row-actions">
                      @if (canAdjust(current)) {
                        @if (canVerify() && !row.item.withdrawn_at) {
                          <button
                            type="button"
                            (click)="startVerification(row.item)"
                            [disabled]="
                              row.item.verification_started_at !== null ||
                              busyItemId() === row.item.id
                            "
                          >
                            Iniciar gestión
                          </button>
                          <button
                            type="button"
                            (click)="openOutcome(row.item)"
                            [disabled]="busyItemId() === row.item.id"
                          >
                            Registrar resultado
                          </button>
                        }
                        @if (!row.item.withdrawn_at && row.alternative) {
                          <button
                            type="button"
                            (click)="promote(row.item)"
                            [disabled]="busyItemId() === row.item.id"
                          >
                            Promover alternativa
                          </button>
                        }
                        @if (!row.item.withdrawn_at) {
                          <button
                            type="button"
                            (click)="openWithdraw(row.item)"
                            [disabled]="busyItemId() === row.item.id"
                          >
                            Retirar línea
                          </button>
                        }
                      }
                    </td>
                  </tr>
                  @if (outcomeItem(); as openRow) {
                    @if (openRow.item_id === row.item.id) {
                      <tr class="outcome-row">
                        <td colspan="8">
                          <app-verification-outcome-form
                            [item]="openRow"
                            (saved)="onOutcomeSaved()"
                            (cancelled)="closeOutcome()"
                          />
                        </td>
                      </tr>
                    }
                  }
                }
              </tbody>
            </table>
          </div>

          @if (withdrawTarget(); as target) {
            <div class="withdraw-prompt">
              <h3>Retirar línea</h3>
              <p class="muted">{{ target.item_label }}</p>
              <label class="req" for="withdraw-reason">Motivo del retiro</label>
              <textarea
                id="withdraw-reason"
                rows="2"
                [value]="withdrawReason()"
                (input)="onWithdrawReason($event)"
              ></textarea>
              <div class="actions">
                <button
                  type="button"
                  (click)="confirmWithdraw(target)"
                  [disabled]="busyItemId() === target.id"
                >
                  Retirar línea
                </button>
                <button
                  type="button"
                  (click)="closeWithdraw()"
                  [disabled]="busyItemId() === target.id"
                >
                  Cancelar
                </button>
              </div>
            </div>
          }
        </section>

        <section class="section" [class.is-disabled]="current.status === 'cancelled'">
          <h2>Agregar servicio</h2>
          @if (current.status === 'cancelled') {
            <p>Pre-reserva cancelada: no admite más servicios.</p>
          } @else {
            <fieldset class="plain item-row">
              <legend>Nuevo servicio</legend>

              <label for="ad-kind">Tipo</label>
              <select id="ad-kind" [value]="addDraft().kind" (change)="onAddKind($event)">
                <option value="product">Producto</option>
                <option value="addon">Complemento</option>
              </select>

              <label class="req" for="ad-bookable">
                {{ addDraft().kind === 'product' ? 'Producto' : 'Complemento' }}
              </label>
              <select
                id="ad-bookable"
                [value]="bookableValue(addDraft())"
                (change)="onAddBookable($event)"
              >
                <option value="">Elige…</option>
                @for (option of optionsFor(addDraft().kind); track option.id) {
                  <option [value]="option.id">{{ option.name }}</option>
                }
              </select>
              @if (addIssue('bookable'); as message) {
                <p class="field-error">{{ message }}</p>
              }

              <label class="req" for="ad-start">Desde</label>
              <input
                id="ad-start"
                type="date"
                [min]="today"
                [value]="addDraft().startDate"
                (change)="onAddDate('startDate', $event)"
              />
              @if (addIssue('startDate'); as message) {
                <p class="field-error">{{ message }}</p>
              }

              <label [class.req]="isAccommodation(addDraft())" for="ad-end">Hasta</label>
              <input
                id="ad-end"
                type="date"
                [min]="addDraft().startDate || today"
                [value]="addDraft().endDate"
                (change)="onAddDate('endDate', $event)"
              />
              @if (addIssue('endDate'); as message) {
                <p class="field-error">{{ message }}</p>
              }

              <label class="req" for="ad-adults">Adultos</label>
              <input
                id="ad-adults"
                type="number"
                min="1"
                max="99"
                [value]="addDraft().adults"
                (input)="onAddNumber('adults', $event)"
              />
              @if (addIssue('adults'); as message) {
                <p class="field-error">{{ message }}</p>
              }

              <label for="ad-children">Niños</label>
              <input
                id="ad-children"
                type="number"
                min="0"
                max="99"
                [value]="addDraft().children"
                (input)="onAddNumber('children', $event)"
              />
              @if (addIssue('children'); as message) {
                <p class="field-error">{{ message }}</p>
              }

              <label for="ad-quantity">Cantidad</label>
              <input
                id="ad-quantity"
                type="number"
                min="1"
                max="99"
                [value]="addDraft().quantity"
                (input)="onAddNumber('quantity', $event)"
              />
              @if (addIssue('quantity'); as message) {
                <p class="field-error">{{ message }}</p>
              }

              @if (providerOf(addDraft()); as provider) {
                <p class="notice">
                  Proveedor: {{ provider.name }} · {{ provider.contact_phone || 'sin teléfono' }} ·
                  {{ provider.contact_email || 'sin correo' }}
                </p>
              } @else {
                <label for="ad-provider">Proveedor</label>
                <input
                  id="ad-provider"
                  type="text"
                  [value]="addDraft().providerName"
                  (input)="onAddProvider('providerName', $event)"
                />
                <label for="ad-phone">Teléfono del proveedor</label>
                <input
                  id="ad-phone"
                  type="tel"
                  [value]="addDraft().providerPhone"
                  (input)="onAddProvider('providerPhone', $event)"
                />
                <label for="ad-email">Correo del proveedor</label>
                <input
                  id="ad-email"
                  type="email"
                  [value]="addDraft().providerEmail"
                  (input)="onAddProvider('providerEmail', $event)"
                />
              }

              <label for="ad-alt">Es alternativa de</label>
              <select
                id="ad-alt"
                [value]="addDraft().alternativeOf ?? ''"
                (change)="onAddAlternative($event)"
              >
                <option value="">No es alternativa</option>
                @for (target of alternativeTargets(current); track target.id) {
                  <option [value]="$index">
                    {{ $index + 1 }}. {{ target.item_label }} — {{ itemDates(target) }}
                  </option>
                }
              </select>
              <p class="hint">
                Las alternativas se verifican, pero no cuentan para el estado de la pre-reserva.
              </p>
              @if (addIssue('alternativeOf'); as message) {
                <p class="field-error">{{ message }}</p>
              }
            </fieldset>
            @if (addIssue('items'); as message) {
              <p class="field-error">{{ message }}</p>
            }
            <div class="actions">
              <button type="button" class="primary" (click)="addService()" [disabled]="busy()">
                Agregar servicio
              </button>
            </div>
          }
        </section>

        <section class="section">
          <h2>Cotización</h2>
          @if (current.quote_eligible) {
            <p>Lista para cotizar.</p>
          } @else {
            <p>No elegible para cotizar: {{ ineligibleReason(current) }}.</p>
          }
          <p>La cotización se genera desde el módulo de cotizaciones.</p>

          @if (current.quote_override_at; as overrideAt) {
            <p>
              Excepción autorizada por {{ current.override_by?.full_name || 'un administrador' }} el
              {{ overrideAt | date: 'short' }}.
            </p>
          }

          @if (canAuthorizeOverride(current)) {
            <label class="req" for="override-reason">Motivo de la excepción</label>
            <textarea
              id="override-reason"
              rows="2"
              [value]="overrideReason()"
              (input)="onOverrideReason($event)"
            ></textarea>
            <p class="hint">La excepción quedará registrada en la auditoría.</p>
            <div class="actions">
              <button type="button" (click)="authorizeException()" [disabled]="busy()">
                Autorizar excepción
              </button>
            </div>
          }
        </section>

        <section class="section">
          <h2>Historial</h2>
          @if (historyError(); as failure) {
            <app-alert kind="error">{{ failure.message }}</app-alert>
          } @else if (history().length === 0) {
            <p>Todavía no hay eventos.</p>
          } @else {
            <ul class="events">
              @for (event of history(); track event.id) {
                <li>
                  <strong>{{ eventLabel(event.event_kind) }}</strong>
                  · {{ event.created_at | date: 'short' }} · {{ event.actor_name || '—' }}
                  @if (event.from_status || event.to_status) {
                    <span> · {{ eventTransition(event) }}</span>
                  }
                  @if (event.provider_contact_person) {
                    <span> · Contacto: {{ event.provider_contact_person }}</span>
                    @if (event.contact_method; as method) {
                      <span> ({{ methodLabel(method) }})</span>
                    }
                  }
                  @if (event.notes; as notes) {
                    <span class="muted">{{ notes }}</span>
                  }
                </li>
              }
            </ul>
          }
        </section>

        <section class="section">
          <h2>Tiempos de verificación</h2>
          @if (timesError(); as failure) {
            <app-alert kind="error">{{ failure.message }}</app-alert>
          } @else if (times(); as metrics) {
            <p>
              @if (metrics.hours_to_verified !== null) {
                Tiempo hasta verificación total: {{ metrics.hours_to_verified }} h
              } @else {
                Aún no se verifica totalmente.
              }
            </p>
            <p>
              @if (metrics.hours_to_first_start !== null) {
                Primera gestión: {{ metrics.hours_to_first_start }} h desde la creación
              } @else {
                Aún no se inicia la gestión.
              }
            </p>
            <p>
              Verificadores: {{ metrics.verifier_count }} · Líneas verificables:
              {{ metrics.item_count }}
            </p>
          } @else {
            <p>Aún no se verifica totalmente.</p>
          }
        </section>

        <section class="section" [class.is-disabled]="current.status === 'cancelled'">
          <h2>Cancelar pre-reserva</h2>
          @if (current.status === 'cancelled') {
            <p>Esta pre-reserva ya está cancelada.</p>
          } @else {
            <label class="req" for="cancel-reason">Motivo de la cancelación</label>
            <textarea
              id="cancel-reason"
              rows="2"
              [value]="cancelReason()"
              (input)="onCancelReason($event)"
            ></textarea>
            <p class="hint">¿Cancelar esta pre-reserva? No se podrá reactivar.</p>
            <div class="actions">
              <button type="button" (click)="confirmCancel()" [disabled]="busy()">
                Cancelar pre-reserva
              </button>
            </div>
          }
        </section>
      } @else {
        <p>No encontramos esta pre-reserva.</p>
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

    .table-wrap {
      overflow-x: auto;
    }

    .tag {
      display: inline-block;
      margin-right: 0.35rem;
      padding: 0 0.35rem;
      border-radius: 0.25rem;
      background: #fef3c7;
      color: #92400e;
      font-size: 0.75rem;
    }

    .muted {
      display: block;
      font-size: 0.85rem;
      opacity: 0.8;
    }

    tr.withdrawn td {
      color: #78716c;
    }

    td.alternative {
      padding-left: 1.5rem;
    }

    td a + a {
      margin-left: 0.4rem;
    }

    .row-actions button + button {
      margin-left: 0.4rem;
    }

    .outcome-row td {
      background: #fafaf9;
    }

    .withdraw-prompt {
      margin-top: 0.85rem;
      padding: 0.85rem;
      border: 1px solid #d6d3d1;
      border-radius: 0.5rem;
      display: grid;
      gap: 0.5rem;
    }

    .withdraw-prompt h3,
    .withdraw-prompt p {
      margin: 0;
    }

    .item-row {
      padding: 0.75rem;
      border: 1px solid #e7e5e4;
      border-radius: 0.35rem;
    }

    .events {
      list-style: none;
      margin: 0;
      padding: 0;
      display: grid;
      gap: 0.6rem;
    }
  `,
})
export class PreReservationDetailComponent {
  private readonly preReservations = inject(PreReservationService);
  private readonly verifications = inject(AvailabilityVerificationService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  readonly id = input.required<string>();

  protected readonly loading = signal(true);
  protected readonly loadError = signal<AppError | null>(null);
  protected readonly detail = signal<PreReservationDetail | null>(null);
  protected readonly history = signal<VerificationEvent[]>([]);
  protected readonly historyError = signal<AppError | null>(null);
  protected readonly times = signal<VerificationTimes | null>(null);
  protected readonly timesError = signal<AppError | null>(null);
  protected readonly busyItemId = signal<string | null>(null);
  protected readonly actionError = signal<AppError | null>(null);
  protected readonly outcomeItem = signal<VerificationQueueRow | null>(null);
  protected readonly withdrawTarget = signal<PreReservationItem | null>(null);
  protected readonly withdrawReason = signal('');
  protected readonly busy = signal(false);
  protected readonly operators = signal<AssigneeOption[]>([]);
  protected readonly bookables = signal<BookableOption[]>([]);
  protected readonly addDraft = signal<PreReservationItemDraft>(emptyItemDraft());
  protected readonly addIssues = signal<PreReservationIssue[]>([]);
  protected readonly overrideReason = signal('');
  protected readonly cancelReason = signal('');
  protected readonly today = todayIso();
  /** Bookables and operators load once per component instance (see `loadAux`). */
  private auxLoaded = false;
  protected readonly statusLabel = (status: PreReservation['status']) =>
    PRE_RESERVATION_STATUS_LABELS[status];
  protected readonly availabilityLabel = (status: PreReservationItem['verification_status']) =>
    AVAILABILITY_STATUS_LABELS[status];
  protected readonly eventLabel = (kind: AvailabilityEventKind) =>
    AVAILABILITY_EVENT_KIND_LABELS[kind];
  protected readonly methodLabel = (method: ProviderContactMethod) => CONTACT_METHOD_LABELS[method];

  /** Only operators and admins work availability (contracts §3.2). */
  protected readonly canVerify = computed(() => hasRoleAtLeast(this.auth.role(), 'operator'));

  /** Main lines with their alternatives nested right after each one (position order). */
  protected readonly serviceRows = computed<ServiceRow[]>(() => {
    const items = this.detail()?.items ?? [];
    const rows: ServiceRow[] = [];
    for (const item of items) {
      if (item.alternative_of_item_id) {
        continue;
      }
      rows.push({ item, alternative: false });
      for (const alternative of items) {
        if (alternative.alternative_of_item_id === item.id) {
          rows.push({ item: alternative, alternative: true });
        }
      }
    }
    return rows;
  });

  constructor() {
    effect(() => {
      const id = this.id();
      void this.load(id);
    });
  }

  /** Reload hook for the actions US3 adds (assign, verify, withdraw, promote…). */
  protected reload(): void {
    void this.load(this.id());
  }

  protected goBack(): void {
    const state = history.state as { navigationId?: number } | null;
    if (state && typeof state.navigationId === 'number' && state.navigationId > 1) {
      history.back();
      return;
    }
    void this.router.navigate(['/sales/pre-reservations']);
  }

  protected customerName(customer: NonNullable<PreReservationDetail['customer']>): string {
    return customerDisplayName(customer);
  }

  protected itemDates(item: PreReservationItem): string {
    const start = formatDay(item.start_date);
    if (!item.end_date) {
      return start;
    }
    return `${start} – ${formatDay(item.end_date)}`;
  }

  protected itemPax(item: PreReservationItem): string {
    const adults = `${item.adults} ${item.adults === 1 ? 'adulto' : 'adultos'}`;
    const children =
      item.children > 0 ? ` · ${item.children} ${item.children === 1 ? 'niño' : 'niños'}` : '';
    return `${adults}${children} · cantidad ${item.quantity}`;
  }

  protected contactLinks(item: PreReservationItem): ReturnType<typeof providerContactLinks> {
    return providerContactLinks(item);
  }

  /** Adjustments (row actions) are closed once the pre-reservation is cancelled. */
  protected canAdjust(current: PreReservationDetail): boolean {
    return current.status !== 'cancelled';
  }

  /** «Autorizar excepción» is admin-only and never offered on verified/cancelled rows (contracts §6.3). */
  protected canAuthorizeOverride(current: PreReservationDetail): boolean {
    return (
      hasRoleAtLeast(this.auth.role(), 'admin') &&
      current.status !== 'verified' &&
      current.status !== 'cancelled'
    );
  }

  /** Why the row is not quotable yet; `quote_eligible` owns the rule (R-008). */
  protected ineligibleReason(current: PreReservationDetail): string {
    return quoteEligibilityReason(current) ?? 'no cumple todavía las reglas de elegibilidad';
  }

  /** Main, non-withdrawn lines an alternative of the line form may point at (contracts §1). */
  protected alternativeTargets(current: PreReservationDetail): PreReservationItem[] {
    return current.items.filter((item) => !item.alternative_of_item_id && !item.withdrawn_at);
  }

  /** Message of an «Agregar servicio» issue; `field` is relative to the single row. */
  protected addIssue(field: string): string | null {
    const key = field === 'items' ? 'items' : `item-0.${field}`;
    return this.addIssues().find((issue) => issue.field === key)?.message ?? null;
  }

  protected optionsFor(kind: 'product' | 'addon'): BookableOption[] {
    return this.bookables().filter((option) =>
      kind === 'product' ? option.kind !== 'addon' : option.kind === 'addon',
    );
  }

  protected bookableValue(item: PreReservationItemDraft): string {
    return (item.kind === 'product' ? item.productId : item.addonId) ?? '';
  }

  protected isAccommodation(item: PreReservationItemDraft): boolean {
    return item.itemKind === 'accommodation';
  }

  /** Read-only provider snapshot of the selected product, when it has an active provider. */
  protected providerOf(item: PreReservationItemDraft): BookableProvider | null {
    if (item.kind !== 'product' || !item.productId || !item.productHasProvider) {
      return null;
    }
    return this.bookables().find((option) => option.id === item.productId)?.provider ?? null;
  }

  /** Reassigns the verification operator (RPC `assign_pre_reservation_operator`). */
  protected async onOperatorChange(event: Event): Promise<void> {
    const value = (event.target as HTMLSelectElement).value;
    const id = this.detail()?.id;
    if (!id) {
      return;
    }
    await this.runAction(() => this.preReservations.assignOperator(id, value || null));
  }

  /** «Asignarme»: operators and admins take the verification of this pre-reservation. */
  protected async assignToMe(): Promise<void> {
    const userId = this.auth.user()?.id;
    const id = this.detail()?.id;
    if (!userId || !id) {
      return;
    }
    await this.runAction(() => this.preReservations.assignOperator(id, userId));
  }

  protected onAddKind(event: Event): void {
    const kind = (event.target as HTMLSelectElement).value === 'addon' ? 'addon' : 'product';
    this.patchAdd({
      kind,
      productId: null,
      addonId: null,
      itemKind: null,
      productHasProvider: false,
      providerName: '',
      providerPhone: '',
      providerEmail: '',
    });
  }

  protected onAddBookable(event: Event): void {
    const id = (event.target as HTMLSelectElement).value;
    const item = this.addDraft();
    if (!id) {
      this.patchAdd(
        item.kind === 'product'
          ? {
              productId: null,
              itemKind: null,
              productHasProvider: false,
              providerName: '',
              providerPhone: '',
              providerEmail: '',
            }
          : { addonId: null },
      );
      return;
    }
    const bookable = this.bookables().find((option) => option.id === id);
    if (!bookable) {
      return;
    }
    if (item.kind === 'addon') {
      this.patchAdd({ addonId: bookable.id });
      return;
    }
    const provider = bookable.provider && bookable.provider.is_active ? bookable.provider : null;
    this.patchAdd({
      productId: bookable.id,
      itemKind: bookable.kind,
      productHasProvider: provider !== null,
      providerName: provider?.name ?? '',
      providerPhone: provider?.contact_phone ?? '',
      providerEmail: provider?.contact_email ?? '',
    });
  }

  protected onAddDate(field: 'startDate' | 'endDate', event: Event): void {
    const value = (event.target as HTMLInputElement).value;
    this.patchAdd(field === 'startDate' ? { startDate: value } : { endDate: value });
  }

  protected onAddNumber(field: 'adults' | 'children' | 'quantity', event: Event): void {
    const raw = (event.target as HTMLInputElement).valueAsNumber;
    const value = Number.isFinite(raw) ? raw : 0;
    this.patchAdd(
      field === 'adults'
        ? { adults: value }
        : field === 'children'
          ? { children: value }
          : { quantity: value },
    );
  }

  protected onAddProvider(
    field: 'providerName' | 'providerPhone' | 'providerEmail',
    event: Event,
  ): void {
    this.patchAdd({ [field]: (event.target as HTMLInputElement).value });
  }

  protected onAddAlternative(event: Event): void {
    const raw = (event.target as HTMLSelectElement).value;
    this.patchAdd({ alternativeOf: raw === '' ? null : Number(raw) });
  }

  /**
   * Adds the single draft line (US1 helpers): the existing main lines pad the draft list so
   * `alternativeOf` resolves to the row index, which the payload maps to
   * `alternative_of_item_id`.
   */
  protected async addService(): Promise<void> {
    const current = this.detail();
    if (!current) {
      return;
    }
    const targets = this.alternativeTargets(current);
    const draft = this.addDraft();
    // Stand-ins occupy the indexes of the existing main lines; their own issues are filtered out.
    const padded = [...targets.map(() => ({ ...emptyItemDraft(), startDate: this.today })), draft];
    const prefix = `item-${targets.length}.`;
    const issues = validateItemDrafts(padded, this.today)
      .filter((issue) => issue.field === 'items' || issue.field.startsWith(prefix))
      .map((issue) =>
        issue.field.startsWith(prefix)
          ? { ...issue, field: `item-0.${issue.field.slice(prefix.length)}` }
          : issue,
      );
    this.addIssues.set(issues);
    if (issues.length > 0) {
      return;
    }

    const [row] = buildCreatePayload([draft], null).items;
    const { alternative_of: targetIndex, ...line } = row;
    const item: PreReservationAddItemInput = {
      ...line,
      alternative_of_item_id: targetIndex === undefined ? null : (targets[targetIndex]?.id ?? null),
    };

    if (await this.runAction(() => this.preReservations.addItem(current.id, item))) {
      this.addDraft.set(emptyItemDraft());
      this.addIssues.set([]);
    }
  }

  protected onOverrideReason(event: Event): void {
    this.overrideReason.set((event.target as HTMLTextAreaElement).value);
  }

  /** Admin-only: records the quotation exception with a mandatory reason (contracts §4). */
  protected async authorizeException(): Promise<void> {
    const current = this.detail();
    if (!current) {
      return;
    }
    const reason = this.overrideReason().trim();
    if (!reason) {
      this.actionError.set(toAppError({ message: 'OVERRIDE_REASON_REQUIRED' }));
      return;
    }
    if (!window.confirm('La excepción quedará registrada en la auditoría.')) {
      return;
    }
    if (await this.runAction(() => this.preReservations.authorizeOverride(current.id, reason))) {
      this.overrideReason.set('');
    }
  }

  protected onCancelReason(event: Event): void {
    this.cancelReason.set((event.target as HTMLTextAreaElement).value);
  }

  /** Cancels the pre-reservation with a mandatory reason and a confirmation (contracts §2.2). */
  protected async confirmCancel(): Promise<void> {
    const current = this.detail();
    if (!current) {
      return;
    }
    const reason = this.cancelReason().trim();
    if (!reason) {
      this.actionError.set(toAppError({ message: 'CANCEL_REASON_REQUIRED' }));
      return;
    }
    if (!window.confirm('¿Cancelar esta pre-reserva? No se podrá reactivar.')) {
      return;
    }
    if (await this.runAction(() => this.preReservations.cancel(current.id, reason))) {
      this.cancelReason.set('');
    }
  }

  private patchAdd(patch: Partial<PreReservationItemDraft>): void {
    this.addDraft.update((current) => ({ ...current, ...patch }));
  }

  protected eventTransition(event: VerificationEvent): string {
    const from = event.from_status ? AVAILABILITY_STATUS_LABELS[event.from_status] : '—';
    const to = event.to_status ? AVAILABILITY_STATUS_LABELS[event.to_status] : '—';
    return `${from} → ${to}`;
  }

  /** Records the first provider contact on a line (RPC `start_item_verification`). */
  protected async startVerification(item: PreReservationItem): Promise<void> {
    await this.run(item.id, () => this.verifications.start(item.id));
  }

  /** Deploys the shared outcome form under the row. */
  protected openOutcome(item: PreReservationItem): void {
    const current = this.detail();
    if (!current) {
      return;
    }
    if (this.outcomeItem()?.item_id === item.id) {
      this.outcomeItem.set(null);
      return;
    }
    this.outcomeItem.set(toQueueRow(current, item));
  }

  protected onOutcomeSaved(): void {
    this.outcomeItem.set(null);
    this.reload();
  }

  protected closeOutcome(): void {
    this.outcomeItem.set(null);
  }

  /** Promotes an alternative to main, replacing the line it pointed at. */
  protected async promote(item: PreReservationItem): Promise<void> {
    if (!window.confirm('¿Promover esta alternativa a servicio principal?')) {
      return;
    }
    await this.run(item.id, () => this.preReservations.promoteItem(item.id));
  }

  protected openWithdraw(item: PreReservationItem): void {
    this.withdrawTarget.set(item);
    this.withdrawReason.set('');
    this.actionError.set(null);
  }

  protected closeWithdraw(): void {
    this.withdrawTarget.set(null);
    this.withdrawReason.set('');
  }

  protected onWithdrawReason(event: Event): void {
    this.withdrawReason.set((event.target as HTMLTextAreaElement).value);
  }

  /** Withdraws a line with its live alternatives; the reason is mandatory (contracts §4). */
  protected async confirmWithdraw(item: PreReservationItem): Promise<void> {
    const reason = this.withdrawReason().trim();
    if (!reason) {
      this.actionError.set({ code: 'VALIDATION_ERROR', message: 'Indica el motivo del retiro.' });
      return;
    }
    await this.run(item.id, () => this.preReservations.withdrawItem(item.id, reason));
    this.closeWithdraw();
  }

  /** Runs one row action, surfacing its error and reloading the detail on success. */
  private async run(itemId: string, action: () => Promise<void>): Promise<void> {
    this.busyItemId.set(itemId);
    this.actionError.set(null);
    try {
      await action();
      this.outcomeItem.set(null);
      this.reload();
    } catch (failure) {
      this.actionError.set(toAppError(failure));
    } finally {
      this.busyItemId.set(null);
    }
  }

  /** Runs a header-level action (assign, add line, exception, cancel); true when it succeeded. */
  private async runAction(action: () => Promise<void>): Promise<boolean> {
    this.busy.set(true);
    this.actionError.set(null);
    try {
      await action();
      this.outcomeItem.set(null);
      this.withdrawTarget.set(null);
      this.reload();
      return true;
    } catch (failure) {
      this.actionError.set(toAppError(failure));
      return false;
    } finally {
      this.busy.set(false);
    }
  }

  private async load(id: string): Promise<void> {
    this.loading.set(true);
    this.loadError.set(null);
    try {
      // `getById` sweeps expired holds first (R-004), so the header shows fresh status.
      const [header, events, metrics] = await Promise.all([
        this.preReservations.getById(id),
        this.loadHistory(id),
        this.loadTimes(id),
      ]);
      // Bookables/operators feed the «Agregar servicio» form and the operator selector.
      await this.loadAux();
      this.detail.set(header);
      if (events !== undefined) {
        this.history.set(events);
      }
      if (metrics !== undefined) {
        this.times.set(metrics);
      }
    } catch (failure) {
      this.loadError.set(toAppError(failure));
      this.detail.set(null);
    } finally {
      this.loading.set(false);
    }
  }

  /** Secondary reads (US4): they fail independently and never block the header. */
  private async loadHistory(id: string): Promise<VerificationEvent[] | undefined> {
    try {
      this.historyError.set(null);
      return await this.preReservations.listHistory(id);
    } catch (failure) {
      this.historyError.set(toAppError(failure));
      this.history.set([]);
      return undefined;
    }
  }

  private async loadTimes(id: string): Promise<VerificationTimes | null | undefined> {
    try {
      this.timesError.set(null);
      return await this.preReservations.getTimes(id);
    } catch (failure) {
      this.timesError.set(toAppError(failure));
      this.times.set(null);
      return undefined;
    }
  }

  /** Reference data for «Agregar servicio» and the operator selector; fetched once. */
  private async loadAux(): Promise<void> {
    if (this.auxLoaded) {
      return;
    }
    const [bookables, operators] = await Promise.all([
      this.preReservations.listBookables(),
      this.preReservations.listOperators(),
    ]);
    this.bookables.set(bookables);
    this.operators.set(operators);
    this.auxLoaded = true;
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

/**
 * Projects a detail line onto the queue row shape the shared outcome form expects
 * (the form only reads the item id, label and reference).
 */
function toQueueRow(detail: PreReservationDetail, item: PreReservationItem): VerificationQueueRow {
  const holdMs = item.hold_expires_at ? Date.parse(item.hold_expires_at) : Number.NaN;
  return {
    item_id: item.id,
    organization_id: item.organization_id,
    pre_reservation_id: detail.id,
    reference: detail.reference,
    pre_reservation_status: detail.status,
    is_alternative: item.alternative_of_item_id !== null,
    alternative_of_item_id: item.alternative_of_item_id,
    item_kind: item.item_kind,
    item_label: item.item_label,
    start_date: item.start_date,
    end_date: item.end_date,
    adults: item.adults,
    children: item.children,
    quantity: item.quantity,
    provider_id: item.provider_id,
    provider_name: item.provider_name,
    provider_phone: item.provider_phone,
    provider_email: item.provider_email,
    verification_status: item.verification_status,
    verification_started_at: item.verification_started_at,
    verified_at: item.verified_at,
    verified_by_name: item.verifier?.full_name ?? null,
    provider_contact_person: item.provider_contact_person,
    hold_expires_at: item.hold_expires_at,
    hold_expired: Number.isFinite(holdMs) && holdMs < Date.now(),
    needs_action: item.verification_status === 'pending',
    assigned_operator_id: detail.assigned_operator_id,
    assigned_operator_name: detail.operator?.full_name ?? null,
    customer_first_name: detail.customer?.first_name ?? '',
    customer_last_name: detail.customer?.last_name ?? null,
    customer_is_anonymized: detail.customer?.is_anonymized ?? false,
    item_created_at: item.created_at,
  };
}
