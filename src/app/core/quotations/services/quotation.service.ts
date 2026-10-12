import { inject, Injectable } from '@angular/core';
import { SupabaseService } from '../../auth/services/supabase.service';
import { redact, toAppError } from '../../error/error-handler';
import { toSearchOrFilter } from '../../customers/search-pattern';
import { LIST_PAGE_SIZE } from '../../../shared/components/data-table/list-query';
import type {
  CreateQuotationDraftResult,
  PublicQuotation,
  QuotationAdjustment,
  QuotationAdjustmentInput,
  QuotationBreakdown,
  QuotationDetail,
  QuotationLine,
  QuotationListRow,
  QuotationResponseKind,
  QuotationStatus,
  QuotationTextsInput,
  QuotationVersion,
} from '../models/quotation.model';

export interface QuotationPageQuery {
  q?: string;
  status?: QuotationStatus | '';
  page: number;
}

/** Result of `set_quotation_texts` (contracts §2). */
export interface SetQuotationTextsResult {
  version_id: string;
}

/** Result of `set_quotation_terms` (contracts §3): the server recomputes the validity. */
export interface SetQuotationTermsResult {
  version_id: string;
  valid_until: string;
  terms: string;
}

/** Result of `issue_quotation` (contracts §3): `public_token` travels only in this response. */
export interface IssueQuotationResult {
  version_id: string;
  reference: string;
  version_number: number;
  status: QuotationStatus;
  valid_until: string;
  public_token: string;
  total: number;
  currency: string;
}

/** Result of `record_quotation_response` (contracts §5). */
export interface RecordQuotationResponseResult {
  version_id: string;
  status: QuotationStatus;
  response: QuotationResponseKind;
}

/**
 * Result of `accept_public_quotation` (contracts §5): `available: false` means the link
 * stopped working (unknown token or voided version) — not an error.
 */
export interface AcceptPublicQuotationResult {
  available: boolean;
  status?: QuotationStatus;
}

/** Result of `void_quotation` (contracts §5). */
export interface VoidQuotationResult {
  version_id: string;
  status: QuotationStatus;
}

/** Family embed read alongside the version to expose `COT-#####` in the editor. */
interface FamilyEmbed {
  reference: string | null;
}

interface QuotationVersionRow extends QuotationVersion {
  family: FamilyEmbed | FamilyEmbed[] | null;
}

const VERSION_SELECT = '*, family:quotation_families(reference)';

/**
 * Reads quotations and applies the panel RPCs (feature 005).
 *
 * Direct table writes are revoked; mutations go through SECURITY DEFINER functions.
 * The server owns the price: every method returns the RPC JSON untouched and nothing
 * here sums or recomputes a total (FR-002).
 */
@Injectable({ providedIn: 'root' })
export class QuotationService {
  private readonly supabase = inject(SupabaseService);

  /**
   * Expires issued quotations whose validity ran out (contracts §1 and §3).
   *
   * Runs before every list/detail read; the sweep is best-effort —
   * `expire_due_quotations` ships in migration `046_us2_quotation_issue.sql` and may not
   * exist yet — so a failure is logged and swallowed: the read that triggered it must
   * still succeed.
   */
  async expireDue(): Promise<number> {
    const { data, error } = await this.supabase.client.rpc('expire_due_quotations');
    if (error) {
      console.warn('[cttadmin] could not sweep expired quotations', redact(error));
      return 0;
    }
    if (typeof data === 'number') {
      return data;
    }
    return (data as { expired_count?: number } | null)?.expired_count ?? 0;
  }

  /**
   * Paginated `quotation_list` page (contracts §1): `expire_due_quotations` first, then
   * `range` + `count: 'exact'`, newest first, optional status filter and free-text search.
   */
  async listPage(input: QuotationPageQuery): Promise<{
    rows: QuotationListRow[];
    total: number;
  }> {
    await this.expireDue();

    const page = Math.max(1, Math.floor(input.page) || 1);
    const from = (page - 1) * LIST_PAGE_SIZE;
    const to = from + LIST_PAGE_SIZE - 1;

    let query = this.supabase.client
      .from('quotation_list')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);

    if (input.status) {
      query = query.eq('status', input.status);
    }

    const filter = toSearchOrFilter(input.q ?? '', [
      'reference',
      'pre_reservation_reference',
      'customer_first_name',
      'customer_last_name',
    ]);
    if (filter) {
      query = query.or(filter);
    }

    const { data, error, count } = await query;
    if (error) {
      throw toAppError(error);
    }
    return { rows: (data ?? []) as QuotationListRow[], total: count ?? 0 };
  }

  /**
   * Version + family reference + lines + adjustments (contracts §1). Read-only: the
   * editor paints these amounts and never recomputes them.
   */
  async getById(versionId: string): Promise<QuotationDetail | null> {
    await this.expireDue();

    const { data, error } = await this.supabase.client
      .from('quotation_versions')
      .select(VERSION_SELECT)
      .eq('id', versionId)
      .maybeSingle();
    if (error) {
      throw toAppError(error);
    }
    if (!data) {
      return null;
    }

    const [linesResult, adjustmentsResult] = await Promise.all([
      this.supabase.client
        .from('quotation_lines')
        .select('*')
        .eq('version_id', versionId)
        .order('position'),
      this.supabase.client
        .from('quotation_adjustments')
        .select('*')
        .eq('version_id', versionId)
        .order('created_at'),
    ]);
    if (linesResult.error) {
      throw toAppError(linesResult.error);
    }
    if (adjustmentsResult.error) {
      throw toAppError(adjustmentsResult.error);
    }

    return mapDetail(
      data as QuotationVersionRow,
      (linesResult.data ?? []) as QuotationLine[],
      (adjustmentsResult.data ?? []) as QuotationAdjustment[],
    );
  }

  /**
   * Creates — or reopens — the draft of a quotable pre-reservation (contracts §2).
   * Returns the family's open version when one already exists.
   */
  async createDraft(preReservationId: string): Promise<CreateQuotationDraftResult> {
    const { data, error } = await this.supabase.client.rpc('create_quotation_draft', {
      p_pre_reservation_id: preReservationId,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as CreateQuotationDraftResult;
  }

  /** Recalculates a draft on the server and returns the fresh breakdown (contracts §2). */
  async recalculate(versionId: string): Promise<QuotationBreakdown> {
    const { data, error } = await this.supabase.client.rpc('recalculate_quotation', {
      p_version_id: versionId,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as QuotationBreakdown;
  }

  /** Sets the tax percentage of one line (0–100) and returns the breakdown (contracts §2). */
  async setTax(lineId: string, taxRate: number): Promise<QuotationBreakdown> {
    const { data, error } = await this.supabase.client.rpc('set_quotation_line_tax', {
      p_line_id: lineId,
      p_tax_rate: taxRate,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as QuotationBreakdown;
  }

  /** Sets a missing exchange rate (> 0) and returns the breakdown (contracts §2). */
  async setExchangeRate(
    versionId: string,
    currency: string,
    rate: number,
  ): Promise<QuotationBreakdown> {
    const { data, error } = await this.supabase.client.rpc('set_quotation_exchange_rate', {
      p_version_id: versionId,
      p_currency: currency,
      p_rate: rate,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as QuotationBreakdown;
  }

  /** Saves the commercial texts of a draft (contracts §2). */
  async setTexts(versionId: string, texts: QuotationTextsInput): Promise<SetQuotationTextsResult> {
    const { data, error } = await this.supabase.client.rpc('set_quotation_texts', {
      p_version_id: versionId,
      p_inclusions: texts.inclusions,
      p_exclusions: texts.exclusions,
      p_notes: texts.notes,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as SetQuotationTextsResult;
  }

  /** Creates or updates one adjustment and returns the breakdown (contracts §2). */
  async saveAdjustment(
    versionId: string,
    adjustment: QuotationAdjustmentInput,
  ): Promise<QuotationBreakdown> {
    const { data, error } = await this.supabase.client.rpc('upsert_quotation_adjustment', {
      p_version_id: versionId,
      p_pre_reservation_item_id: adjustment.pre_reservation_item_id,
      p_label: adjustment.label,
      p_direction: adjustment.direction,
      p_kind: adjustment.kind,
      p_value: adjustment.value,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as QuotationBreakdown;
  }

  /** Deletes one adjustment and returns the breakdown (contracts §2). */
  async deleteAdjustment(adjustmentId: string): Promise<QuotationBreakdown> {
    const { data, error } = await this.supabase.client.rpc('delete_quotation_adjustment', {
      p_adjustment_id: adjustmentId,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as QuotationBreakdown;
  }

  /**
   * Saves the terms and validity of a draft (contracts §3).
   *
   * `validUntil` null restores the server default (48 h); the server enforces both caps
   * (`VALIDITY_EXCEEDS_HOLD`, `VALIDITY_EXCEEDS_30_DAYS`) and `TERMS_REQUIRED`.
   */
  async setTerms(
    versionId: string,
    terms: string,
    validUntil: string | null,
  ): Promise<SetQuotationTermsResult> {
    const { data, error } = await this.supabase.client.rpc('set_quotation_terms', {
      p_version_id: versionId,
      p_terms: terms,
      p_valid_until: validUntil,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as SetQuotationTermsResult;
  }

  /**
   * Freezes and issues a draft: assigns `COT-#####`, stores the fingerprint and returns
   * the one-time `public_token`, kept in `sessionStorage` under `quotation-token:<id>`
   * (contracts §3 and §4).
   */
  async issue(versionId: string): Promise<IssueQuotationResult> {
    const { data, error } = await this.supabase.client.rpc('issue_quotation', {
      p_version_id: versionId,
    });
    if (error) {
      throw toAppError(error);
    }
    const result = data as IssueQuotationResult;
    if (result?.public_token) {
      storeQuotationToken(result.version_id ?? versionId, result.public_token);
    }
    return result;
  }

  /** Saves the organization's terms template, admin-only server-side (contracts §3). */
  async saveDefaults(terms: string): Promise<void> {
    const { error } = await this.supabase.client.rpc('upsert_quotation_defaults', {
      p_terms: terms,
    });
    if (error) {
      throw toAppError(error);
    }
  }

  /** The organization's terms template, or null while there is no row yet (contracts §1). */
  async getDefaults(): Promise<string | null> {
    const { data, error } = await this.supabase.client
      .from('quotation_defaults')
      .select('terms_template')
      .maybeSingle();
    if (error) {
      throw toAppError(error);
    }
    return data ? (data as { terms_template: string }).terms_template : null;
  }

  /**
   * The public proposal for a client token (contracts §4). Callable without a session:
   * the RPC resolves the family by SHA-256 hash and never returns customer data, notes,
   * the pre-reservation or the token itself.
   */
  async getPublic(token: string): Promise<PublicQuotation> {
    const { data, error } = await this.supabase.client.rpc('get_public_quotation', {
      p_token: token,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as PublicQuotation;
  }

  /**
   * Server-built WhatsApp body for one delivered version (contracts §4 and research R-009):
   * reference, line summaries, frozen total and validity — no URL and no token. The screen
   * appends the `Detalle:` line with the token kept in `sessionStorage` at issue time.
   */
  async whatsappText(versionId: string): Promise<string> {
    const { data, error } = await this.supabase.client.rpc('quotation_whatsapp_text', {
      p_version_id: versionId,
    });
    if (error) {
      throw toAppError(error);
    }
    return (data as string | null) ?? '';
  }

  /**
   * Records the agent-registered response on an issued version (contracts §5).
   * `accepted` revalidates the pre-reservation and the frozen fingerprint;
   * `changes_requested` appends a response row and leaves the version `issued`.
   */
  async recordResponse(
    versionId: string,
    kind: QuotationResponseKind,
  ): Promise<RecordQuotationResponseResult> {
    const { data, error } = await this.supabase.client.rpc('record_quotation_response', {
      p_version_id: versionId,
      p_kind: kind,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as RecordQuotationResponseResult;
  }

  /**
   * Two-step public acceptance by token (contracts §5): the server rejects anything but
   * `confirmed: true` with `CONFIRMATION_REQUIRED`. Origin `customer`; creates no
   * reservation — that is feature 006's job.
   */
  async acceptPublic(token: string, confirmed: boolean): Promise<AcceptPublicQuotationResult> {
    const { data, error } = await this.supabase.client.rpc('accept_public_quotation', {
      p_token: token,
      p_confirmed: confirmed,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as AcceptPublicQuotationResult;
  }

  /**
   * Supersedes the current version and opens draft vN+1 in the same family (contracts §5):
   * texts are copied, tariffs and amounts are recalculated. The family reference and public
   * token survive, so the same link shows the new version once it is issued.
   * Returns the new draft's breakdown; navigate with `breakdown.version_id`.
   */
  async createVersion(versionId: string): Promise<QuotationBreakdown> {
    const { data, error } = await this.supabase.client.rpc('create_quotation_version', {
      p_version_id: versionId,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as QuotationBreakdown;
  }

  /** Admin-only void with a mandatory reason; kills the public link (contracts §5). */
  async voidQuotation(versionId: string, reason: string): Promise<VoidQuotationResult> {
    const { data, error } = await this.supabase.client.rpc('void_quotation', {
      p_version_id: versionId,
      p_reason: reason,
    });
    if (error) {
      throw toAppError(error);
    }
    return data as VoidQuotationResult;
  }
}

/** PostgREST returns many-to-one embeds as objects, but the type allows arrays. */
function single<T>(value: T | T[] | null): T | null {
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

function mapDetail(
  row: QuotationVersionRow,
  lines: QuotationLine[],
  adjustments: QuotationAdjustment[],
): QuotationDetail {
  return {
    ...row,
    reference: single(row.family)?.reference ?? null,
    lines,
    adjustments,
  };
}

/** `sessionStorage` key that keeps the public link alive for one tab session (contracts §4). */
export function quotationTokenKey(versionId: string): string {
  return `quotation-token:${versionId}`;
}

/**
 * The one-time `public_token` issued for this version in this tab session, or null.
 *
 * The database only keeps the SHA-256 hash, so a missing token cannot be recovered: the
 * editor has to offer a new version instead (contracts §4).
 */
export function readQuotationToken(versionId: string): string | null {
  try {
    return sessionStorage.getItem(quotationTokenKey(versionId));
  } catch {
    return null;
  }
}

function storeQuotationToken(versionId: string, token: string): void {
  try {
    sessionStorage.setItem(quotationTokenKey(versionId), token);
  } catch {
    // Storage can be unavailable (private mode): the link was already on screen once.
  }
}
