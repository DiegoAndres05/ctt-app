import type { PublicPlacement } from '../../../../core/catalog/models/public-listing.model';
import type { ProductStatus } from '../../../../core/catalog/models/product.model';
import { parseBilingualLines, parseYachtLines, type PublicDraft } from './listing-draft';

export interface PublishGate {
  id: string;
  label: string;
  ok: boolean;
}

export interface PublishGateInput {
  productStatus: ProductStatus | null;
  hasTariff: boolean;
  hasCover: boolean;
  draft: PublicDraft;
}

/**
 * Mirrors `listing_is_complete_for_publish` plus the product/tariff checks in
 * `publish_public_listing`. The button stays hidden until every gate passes.
 */
export function publishGates(input: PublishGateInput): PublishGate[] {
  const draft = input.draft;
  const warnings = parseBilingualLines(draft.warningsText);
  const warningsOk = warnings.every((pair) => pair.es && pair.en);
  const gates: PublishGate[] = [
    { id: 'active', label: 'El producto está activo', ok: input.productStatus === 'active' },
    { id: 'tariff', label: 'Hay una tarifa vigente', ok: input.hasTariff },
    { id: 'cover', label: 'Hay una foto principal', ok: input.hasCover },
    { id: 'name-es', label: 'Nombre en español', ok: draft.nameEs.trim().length > 0 },
    { id: 'name-en', label: 'Nombre en inglés', ok: draft.nameEn.trim().length > 0 },
    {
      id: 'description-es',
      label: 'Descripción en español',
      ok: draft.descriptionEs.trim().length > 0,
    },
    {
      id: 'description-en',
      label: 'Descripción en inglés',
      ok: draft.descriptionEn.trim().length > 0,
    },
    { id: 'warnings', label: 'Avisos completos en ambos idiomas', ok: warningsOk },
  ];

  gates.push(...placementGates(draft.placement, draft));
  return gates;
}

function placementGates(placement: PublicPlacement, draft: PublicDraft): PublishGate[] {
  if (placement === 'catalog') {
    const includes = parseBilingualLines(draft.includesText);
    return [
      { id: 'category', label: 'Categoría pública', ok: draft.publicCategoryId.trim().length > 0 },
      { id: 'location', label: 'Ubicación', ok: draft.location.trim().length > 0 },
      { id: 'price', label: 'Precio de vitrina', ok: Number(draft.displayPrice) > 0 },
      { id: 'currency', label: 'Moneda', ok: draft.currency.trim().length > 0 },
      {
        id: 'includes',
        label: 'Al menos una inclusión en español e inglés',
        ok: includes.length > 0 && includes.every((pair) => pair.es && pair.en),
      },
    ];
  }

  if (placement === 'lodging') {
    const map = draft.mapUrl.trim();
    return [
      { id: 'price', label: 'Precio de vitrina', ok: Number(draft.displayPrice) > 0 },
      { id: 'currency', label: 'Moneda', ok: draft.currency.trim().length > 0 },
      { id: 'guests', label: 'Huéspedes máximos', ok: draft.maxGuests > 0 },
      { id: 'lodging-type', label: 'Tipo de hospedaje', ok: draft.lodgingType.trim().length > 0 },
      { id: 'location-es', label: 'Ubicación en español', ok: draft.locationEs.trim().length > 0 },
      { id: 'location-en', label: 'Ubicación en inglés', ok: draft.locationEn.trim().length > 0 },
      { id: 'hood-es', label: 'Barrio en español', ok: draft.neighborhoodEs.trim().length > 0 },
      { id: 'hood-en', label: 'Barrio en inglés', ok: draft.neighborhoodEn.trim().length > 0 },
      {
        id: 'map',
        label: 'Mapa en https, si se informa',
        ok: map.length === 0 || map.startsWith('https://'),
      },
    ];
  }

  const lines = parseYachtLines(draft.yachtLinesText);
  const hasCapacity = lines.some(
    (line) => line.kind === 'capacity' && line.text_es && line.text_en,
  );
  const hasFeature = lines.some((line) => line.kind === 'feature' && line.text_es && line.text_en);
  const price = draft.displayPrice.trim();
  return [
    {
      id: 'yacht-lines',
      label: 'Al menos una línea de capacidad y una de característica, en ambos idiomas',
      ok: hasCapacity && hasFeature,
    },
    {
      id: 'yacht-currency',
      label: 'Moneda si hay precio de vitrina',
      ok: price.length === 0 || draft.currency.trim().length > 0,
    },
  ];
}
