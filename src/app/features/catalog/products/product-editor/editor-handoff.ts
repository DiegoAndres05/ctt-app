import { Injectable } from '@angular/core';
import type { LodgingAmenity } from '../../../../core/catalog/models/public-listing.model';
import type { PublicDraft } from './listing-draft';

/** Carries unsaved public fields across the create → :id navigation. */
export interface EditorHandoffPayload {
  productId: string;
  draft: PublicDraft;
  amenities: LodgingAmenity[];
}

@Injectable({ providedIn: 'root' })
export class ProductEditorHandoff {
  private pending: EditorHandoffPayload | null = null;

  stash(payload: EditorHandoffPayload): void {
    this.pending = payload;
  }

  take(productId: string): EditorHandoffPayload | null {
    if (!this.pending || this.pending.productId !== productId) {
      return null;
    }
    const payload = this.pending;
    this.pending = null;
    return payload;
  }
}
