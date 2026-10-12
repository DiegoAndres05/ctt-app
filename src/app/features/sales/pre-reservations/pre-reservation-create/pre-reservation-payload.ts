import type { RequestDetail } from '../../../../core/customers/models/request.model';
import type { PreReservationItemKind } from '../../../../core/pre-reservations/models/pre-reservation.model';
import type {
  BookableOption,
  CreatePreReservationPayload,
  PreReservationItemInput,
} from '../../../../core/pre-reservations/services/pre-reservation.service';

/**
 * Draft lines edited by the «Nueva pre-reserva» form.
 * The server (`resolve_pre_reservation_item`) remains the authority: everything here is
 * an affordance that mirrors contracts §1 so the agent gets feedback before the round trip.
 */
export interface PreReservationItemDraft {
  /** Selector on the form: `product` for catalog products, `addon` for add-ons. */
  kind: 'product' | 'addon';
  productId: string | null;
  addonId: string | null;
  /** Catalog subtype of the selected bookable; `accommodation` requires an end date. */
  itemKind: PreReservationItemKind | null;
  startDate: string;
  endDate: string;
  adults: number;
  children: number;
  quantity: number;
  /** True when the selected product already carries an active provider snapshot. */
  productHasProvider: boolean;
  providerName: string;
  providerPhone: string;
  providerEmail: string;
  /** Index of an earlier main row, or `null` for a main row. */
  alternativeOf: number | null;
  /** Origin interest of the source request, kept for traceability. */
  sourceRequestItemId: string | null;
}

export interface PreReservationDraft {
  items: PreReservationItemDraft[];
  /** Operator select value; `''` means unassigned and the payload normalizes it to null. */
  assignedOperatorId: string;
}

/** `{ field, message }` issues; `field` addresses a line as `item-<index>.<property>`. */
export interface PreReservationIssue {
  field: string;
  message: string;
}

export function emptyPreReservationDraft(): PreReservationDraft {
  // `''` keeps the «Sin asignar» option selected; the payload normalizes it to null.
  return { items: [], assignedOperatorId: '' };
}

export function emptyItemDraft(kind: 'product' | 'addon' = 'product'): PreReservationItemDraft {
  return {
    kind,
    productId: null,
    addonId: null,
    itemKind: null,
    startDate: '',
    endDate: '',
    adults: 1,
    children: 0,
    quantity: 1,
    productHasProvider: false,
    providerName: '',
    providerPhone: '',
    providerEmail: '',
    alternativeOf: null,
    sourceRequestItemId: null,
  };
}

/**
 * Prefill: one draft per request interest that maps to an active catalog product.
 * Interests without a product (free text) or whose product is no longer active are skipped:
 * the agent can still add those lines by hand.
 */
export function draftsFromRequest(
  request: Pick<
    RequestDetail,
    'travel_start_date' | 'travel_end_date' | 'adults' | 'children' | 'items'
  >,
  bookables: BookableOption[],
): PreReservationItemDraft[] {
  const drafts: PreReservationItemDraft[] = [];

  for (const interest of request.items) {
    const productId = interest.product_id;
    if (!productId) {
      continue;
    }
    const bookable = bookables.find((option) => option.id === productId && option.kind !== 'addon');
    if (!bookable) {
      continue;
    }
    const provider = bookable.provider && bookable.provider.is_active ? bookable.provider : null;
    drafts.push({
      ...emptyItemDraft('product'),
      productId: bookable.id,
      itemKind: bookable.kind,
      startDate: request.travel_start_date ?? '',
      endDate: request.travel_end_date ?? '',
      adults: request.adults,
      children: request.children,
      quantity: interest.quantity,
      productHasProvider: provider !== null,
      providerName: provider?.name ?? '',
      providerPhone: provider?.contact_phone ?? '',
      providerEmail: provider?.contact_email ?? '',
      sourceRequestItemId: interest.id,
    });
  }

  return drafts;
}

/**
 * Client-side affordance that mirrors `resolve_pre_reservation_item` (contracts §1):
 * XOR selector, dates (today floor, accommodation exit date), 1–99 / 0–99 / 1–99 ranges,
 * alternatives pointing at an earlier main row, and at least one main row.
 */
export function validateItemDrafts(
  items: PreReservationItemDraft[],
  today: string,
): PreReservationIssue[] {
  const issues: PreReservationIssue[] = [];

  items.forEach((item, index) => {
    const field = (name: string) => `item-${index}.${name}`;

    if (item.kind === 'product' && !item.productId) {
      issues.push({ field: field('bookable'), message: 'Elige un producto.' });
    }
    if (item.kind === 'addon' && !item.addonId) {
      issues.push({ field: field('bookable'), message: 'Elige un complemento.' });
    }

    if (!item.startDate) {
      issues.push({ field: field('startDate'), message: 'Indica la fecha de servicio.' });
    } else if (item.startDate < today) {
      issues.push({
        field: field('startDate'),
        message: 'La fecha de servicio no puede estar en el pasado.',
      });
    }

    if (item.itemKind === 'accommodation') {
      if (!item.endDate) {
        issues.push({ field: field('endDate'), message: 'Indica la fecha de salida.' });
      } else if (item.startDate && item.endDate <= item.startDate) {
        issues.push({
          field: field('endDate'),
          message: 'La fecha de salida debe ser posterior a la de llegada.',
        });
      }
    } else if (item.endDate && item.startDate && item.endDate < item.startDate) {
      issues.push({
        field: field('endDate'),
        message: 'La fecha de fin no puede ser anterior a la de inicio.',
      });
    }

    if (!Number.isInteger(item.adults) || item.adults < 1 || item.adults > 99) {
      issues.push({ field: field('adults'), message: 'Los adultos deben estar entre 1 y 99.' });
    }
    if (!Number.isInteger(item.children) || item.children < 0 || item.children > 99) {
      issues.push({ field: field('children'), message: 'Los niños deben estar entre 0 y 99.' });
    }
    if (!Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 99) {
      issues.push({ field: field('quantity'), message: 'La cantidad debe estar entre 1 y 99.' });
    }

    if (item.alternativeOf !== null) {
      const targetIndex = item.alternativeOf;
      const target = targetIndex >= 0 && targetIndex < index ? items[targetIndex] : undefined;
      if (!target || target.alternativeOf !== null) {
        issues.push({
          field: field('alternativeOf'),
          message: 'La alternativa debe apuntar a una fila principal anterior.',
        });
      }
    }
  });

  if (!items.some((item) => item.alternativeOf === null)) {
    issues.push({
      field: 'items',
      message: 'La pre-reserva necesita al menos un servicio principal.',
    });
  }

  return issues;
}

/**
 * Normalizes the drafts into the `create_pre_reservation` body: trimmed text, blanks as
 * `null`, `alternative_of` only on alternative rows, and the manual provider omitted when
 * the product already carries its own provider snapshot.
 */
export function buildCreatePayload(
  items: PreReservationItemDraft[],
  assignedOperatorId: string | null,
): CreatePreReservationPayload {
  return {
    items: items.map((item) => {
      const keepsCatalogProvider = item.kind === 'product' && item.productHasProvider;
      const sourceRequestItemId = item.sourceRequestItemId?.trim() || null;

      const row: PreReservationItemInput = {
        product_id: item.kind === 'product' ? item.productId : null,
        addon_id: item.kind === 'addon' ? item.addonId : null,
        start_date: item.startDate.trim(),
        end_date: emptyToNull(item.endDate),
        adults: item.adults,
        children: item.children,
        quantity: item.quantity,
        source_request_item_id: sourceRequestItemId,
        provider_name: keepsCatalogProvider ? null : emptyToNull(item.providerName),
        provider_phone: keepsCatalogProvider ? null : emptyToNull(item.providerPhone),
        provider_email: keepsCatalogProvider ? null : emptyToNull(item.providerEmail),
      };
      if (item.alternativeOf !== null) {
        row.alternative_of = item.alternativeOf;
      }
      return row;
    }),
    assigned_operator_id: assignedOperatorId || null,
  };
}

function emptyToNull(value: string): string | null {
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

/** Today as `YYYY-MM-DD` in the agency timezone; floors the «Desde» date of the line form. */
export function todayIso(now = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Bogota',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
}
