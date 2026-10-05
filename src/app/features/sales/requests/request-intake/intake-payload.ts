import type { AssistedChannel } from '../../../../core/customers/models/request.model';
import type { AssistedRequestPayload } from '../../../../core/customers/services/request.service';

export interface IntakeItem {
  productId: string | null;
  freeText: string;
  quantity: number;
}

/** Draft edited by the assisted-intake form. The server remains the authority. */
export interface IntakeDraft {
  channel: AssistedChannel;
  customerId: string | null;
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
  countryCode: string;
  travelStart: string;
  travelEnd: string;
  adults: number;
  children: number;
  items: IntakeItem[];
  specialRequirements: string;
  privacyNoticeGiven: boolean;
}

export interface IntakeIssue {
  field: string;
  message: string;
}

export function emptyIntakeDraft(channel: AssistedChannel = 'whatsapp'): IntakeDraft {
  return {
    channel,
    customerId: null,
    firstName: '',
    lastName: '',
    email: '',
    phone: '',
    countryCode: '',
    travelStart: '',
    travelEnd: '',
    adults: 1,
    children: 0,
    items: [{ productId: null, freeText: '', quantity: 1 }],
    specialRequirements: '',
    privacyNoticeGiven: false,
  };
}

/** Client-side affordance. `create_assisted_request` repeats these checks. */
export function validateIntakeDraft(draft: IntakeDraft, today: string): IntakeIssue[] {
  const issues: IntakeIssue[] = [];

  if (!draft.customerId) {
    if (!draft.firstName.trim()) {
      issues.push({ field: 'firstName', message: 'Ingresa el nombre.' });
    }
    if (!draft.email.trim() && !draft.phone.trim()) {
      issues.push({ field: 'email', message: 'Ingresa correo o teléfono.' });
    }
  }

  if (!draft.privacyNoticeGiven) {
    issues.push({
      field: 'privacyNoticeGiven',
      message: 'Confirma que informaste al cliente sobre el tratamiento de sus datos.',
    });
  }

  if (draft.travelStart && draft.travelStart < today) {
    issues.push({
      field: 'travelStart',
      message: 'La fecha de inicio no puede estar en el pasado.',
    });
  }
  if (draft.travelEnd && draft.travelStart && draft.travelEnd < draft.travelStart) {
    issues.push({
      field: 'travelEnd',
      message: 'La fecha de fin no puede ser anterior a la de inicio.',
    });
  }
  if (!Number.isInteger(draft.adults) || draft.adults < 1 || draft.adults > 99) {
    issues.push({ field: 'adults', message: 'Los adultos deben estar entre 1 y 99.' });
  }
  if (!Number.isInteger(draft.children) || draft.children < 0 || draft.children > 99) {
    issues.push({ field: 'children', message: 'Los niños deben estar entre 0 y 99.' });
  }

  const filled = draft.items.filter((item) => item.productId || item.freeText.trim());
  if (filled.length === 0 && !draft.specialRequirements.trim()) {
    issues.push({
      field: 'items',
      message: 'Agrega un interés o una nota de lo que pidió el cliente.',
    });
  }

  draft.items.forEach((item, index) => {
    const touched = item.productId || item.freeText.trim() || draft.items.length > 1;
    if (touched && !item.productId && !item.freeText.trim()) {
      issues.push({ field: `item-${index}`, message: 'Elige un producto o escribe un texto.' });
    }
    if (item.quantity < 1 || item.quantity > 99) {
      issues.push({ field: `item-${index}`, message: 'La cantidad debe estar entre 1 y 99.' });
    }
  });

  return issues;
}

export function buildAssistedRequestPayload(
  draft: IntakeDraft,
  idempotencyKey: string,
): AssistedRequestPayload {
  const items = draft.items
    .filter((item) => item.productId || item.freeText.trim())
    .map((item) => {
      const row: { product_id?: string; free_text?: string; quantity: number } = {
        quantity: item.quantity,
      };
      if (item.productId) {
        row.product_id = item.productId;
      }
      const text = item.freeText.trim();
      if (text) {
        row.free_text = text;
      }
      return row;
    });

  const payload: AssistedRequestPayload = {
    channel: draft.channel,
    privacy_notice_given: draft.privacyNoticeGiven,
    idempotency_key: idempotencyKey,
    travel_start_date: emptyToNull(draft.travelStart),
    travel_end_date: emptyToNull(draft.travelEnd),
    adults: draft.adults,
    children: draft.children,
    special_requirements: emptyToNull(draft.specialRequirements.trim()),
    items,
  };

  if (draft.customerId) {
    payload.customer_id = draft.customerId;
  } else {
    payload.contact = {
      first_name: draft.firstName.trim(),
      last_name: emptyToNull(draft.lastName.trim()),
      email: emptyToNull(draft.email.trim()),
      phone: emptyToNull(draft.phone.trim()),
      country_code: emptyToNull(draft.countryCode.trim().toUpperCase()),
    };
  }

  return payload;
}

function emptyToNull(value: string): string | null {
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}
