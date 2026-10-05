/** Mirrors `public.document_type`. */
export type DocumentType = 'cc' | 'ce' | 'passport' | 'nit' | 'other';

/** A row of `public.customers`. */
export interface Customer {
  id: string;
  organization_id: string;
  first_name: string;
  last_name: string | null;
  email: string | null;
  phone_e164: string | null;
  document_type: DocumentType | null;
  document_number: string | null;
  country_code: string | null;
  is_anonymized: boolean;
  anonymized_at: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

/** A row of `public.customer_list`. */
export interface CustomerListRow {
  id: string;
  organization_id: string;
  first_name: string;
  last_name: string | null;
  email: string | null;
  phone_e164: string | null;
  country_code: string | null;
  is_anonymized: boolean;
  created_at: string;
  request_count: number;
  last_request_at: string | null;
}

/** Editable contact fields sent to `update_customer`. */
export interface CustomerContactInput {
  first_name: string;
  last_name: string | null;
  email: string | null;
  phone: string | null;
  country_code: string | null;
  document_type: DocumentType | null;
  document_number: string | null;
}

export const DOCUMENT_TYPE_LABELS: Record<DocumentType, string> = {
  cc: 'Cédula de ciudadanía',
  ce: 'Cédula de extranjería',
  passport: 'Pasaporte',
  nit: 'NIT',
  other: 'Otro',
};

/** Display name. Anonymized profiles never leak the stored placeholder plus a surname. */
export function customerDisplayName(customer: {
  first_name: string;
  last_name: string | null;
  is_anonymized: boolean;
}): string {
  if (customer.is_anonymized) {
    return 'Cliente anonimizado';
  }
  return `${customer.first_name} ${customer.last_name ?? ''}`.replace(/\s+/g, ' ').trim();
}
