/**
 * Device deep links for calling a provider from a pre-reservation line or queue row.
 *
 * The panel never calls a provider itself (R-006): it only offers `tel:`, WhatsApp and
 * email links so the operator can open the device's own apps.
 */
export interface ProviderContactLinks {
  /** `tel:` with the phone stripped of spaces. */
  tel?: string;
  /** `https://wa.me/<digits>`; only when the phone contains digits. */
  whatsapp?: string;
  /** `mailto:` with the provider email. */
  mailto?: string;
}

/** Builds the links for whatever contact data the line snapshot carries; missing data is omitted. */
export function providerContactLinks(provider: {
  provider_phone?: string | null;
  provider_email?: string | null;
}): ProviderContactLinks {
  const links: ProviderContactLinks = {};

  const phone = (provider.provider_phone ?? '').trim().replace(/\s+/g, '');
  if (phone) {
    links.tel = `tel:${phone}`;
    const digits = phone.replace(/\D/g, '');
    if (digits) {
      links.whatsapp = `https://wa.me/${digits}`;
    }
  }

  const email = (provider.provider_email ?? '').trim();
  if (email) {
    links.mailto = `mailto:${email}`;
  }

  return links;
}
