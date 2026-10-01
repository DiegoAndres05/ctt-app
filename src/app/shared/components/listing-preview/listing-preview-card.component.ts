import { ChangeDetectionStrategy, Component, input } from '@angular/core';
import type { PreviewListing } from './preview-listing.model';

/**
 * Live catalog card. The locale toggle stays outside this component.
 */
@Component({
  selector: 'app-listing-preview-card',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (listing(); as card) {
      <article class="card" [class.yacht]="card.variant === 'yacht'" [class.lodging]="card.variant === 'lodging'">
        <div class="cover">
          @if (card.imageLoading) {
            <p>Cargando imagen…</p>
          } @else if (card.imageUrl) {
            <img [src]="card.imageUrl" alt="" />
          } @else {
            <p>Sin foto</p>
          }
          @if (card.soldOut) {
            <span class="badge">Agotado</span>
          }
        </div>
        <h3>{{ card.title }}</h3>
        <p class="summary" [class.missing]="card.missingLocale && card.summary.startsWith('Falta')">
          {{ card.summary }}
        </p>
        @if (card.categoryLabel) {
          <p class="meta">{{ card.categoryLabel }}</p>
        }
        @if (card.location) {
          <p class="meta">{{ card.location }}</p>
        }
        @if (card.variant === 'lodging') {
          <p class="meta">
            {{ card.lodgingType || 'Tipo de inmueble' }}
            @if (card.occupancy) {
              · {{ card.occupancy }} huéspedes
            }
          </p>
        }
        @if (card.showPrice) {
          <p class="price">{{ priceLabel(card) }}</p>
        }
      </article>
    }
  `,
  styles: `
    .card {
      display: grid;
      gap: 0.35rem;
      width: min(18rem, 100%);
      padding: 0.75rem;
      background: #fff;
      border: 1px solid #e7e5e4;
      border-radius: 0.75rem;
    }

    .cover {
      position: relative;
      display: grid;
      place-items: center;
      min-height: 8.5rem;
      border-radius: 0.5rem;
      background: #e7e5e4;
      color: #57534e;
      overflow: hidden;
    }

    img {
      width: 100%;
      height: 8.5rem;
      object-fit: cover;
    }

    h3,
    p {
      margin: 0;
    }

    .summary.missing,
    .badge {
      color: #9a3412;
    }

    .badge {
      position: absolute;
      top: 0.4rem;
      left: 0.4rem;
      background: #fff7ed;
      border-radius: 999px;
      padding: 0.1rem 0.45rem;
      font-size: 0.75rem;
    }

    .meta {
      color: #57534e;
      font-size: 0.9rem;
    }

    .price {
      font-weight: 700;
    }

    .yacht {
      border-color: #0f766e;
    }
  `,
})
export class ListingPreviewCardComponent {
  readonly listing = input.required<PreviewListing>();

  protected priceLabel(card: PreviewListing): string {
    if (card.displayPrice === null || Number.isNaN(card.displayPrice)) {
      return 'Sin precio';
    }
    try {
      return new Intl.NumberFormat('es-CO', {
        style: 'currency',
        currency: card.currency || 'COP',
        maximumFractionDigits: 0,
      }).format(card.displayPrice);
    } catch {
      return `${card.displayPrice} ${card.currency}`;
    }
  }
}
