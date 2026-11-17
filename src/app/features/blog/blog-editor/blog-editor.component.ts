import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { imagesMissingAlt } from '../../../core/blog/models/blog-blocks';
import {
  BLOG_FIELD_LABELS,
  BLOG_LIMITS,
  BLOG_LOCALE_LABELS,
  BLOG_LOCALES,
  BLOG_SLUG_PATTERN,
  BLOG_STATUS_LABELS,
  slugify,
  type BlogArticleDetail,
  type BlogLocale,
  type BlogPublishError,
} from '../../../core/blog/models/blog-article.model';
import { BlogService, type BlogError } from '../../../core/blog/services/blog.service';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';
import type { UnsavedChangesHost } from '../../../shared/components/unsaved-changes.guard';
import { BlogPreviewComponent } from './blog-preview.component';
import {
  hasExistingText,
  hasTranslatableText,
  inParts,
  translateLocale,
  type TranslationMode,
} from './blog-translation';
import {
  draftFrom,
  emptyDraft,
  fromEditorBlocks,
  localeOf,
  newBlock,
  snapshotOf,
  toSavePayload,
  type ArticleDraft,
  type EditorBlock,
  type LocaleDraft,
  type LocaleField,
} from './blog-editor.model';
import type { BlogBlockType } from '../../../core/blog/models/blog-blocks';

interface ErrorGroup {
  locale: BlogLocale | null;
  label: string;
  fields: string[];
}

/**
 * Blog article editor (spec 013, US1, US2, US4, US5 and the copy step of US6).
 *
 * Draft: everything can be saved incomplete. Published or retired: edits are a pending
 * revision that the site does not see until «Publicar cambios». The backend validates and
 * normalizes again; this screen only helps the editor get there.
 */
@Component({
  selector: 'app-blog-editor',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, AlertComponent, SpinnerComponent, BlogPreviewComponent],
  templateUrl: './blog-editor.component.html',
  styles: `
    .translate-bar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 0.5rem;
    }

    .blocks {
      display: grid;
      gap: 0.75rem;
    }

    .block {
      display: grid;
      gap: 0.5rem;
      padding: 0.75rem;
      border: 1px solid var(--color-border);
      border-radius: var(--radius-md);
      background: var(--color-surface);
    }

    .block-head {
      display: flex;
      flex-wrap: wrap;
      gap: 0.5rem;
      align-items: center;
      justify-content: space-between;
    }

    .block-tools {
      display: flex;
      gap: 0.35rem;
    }

    .block textarea {
      min-height: 4.5rem;
    }

    .thumb-image {
      max-width: 14rem;
      max-height: 9rem;
      border-radius: var(--radius-md);
      border: 1px solid var(--color-border);
    }

    .error-list {
      margin: 0;
      padding-left: 1.1rem;
    }

    .error-list button {
      padding: 0;
      border: 0;
      background: none;
      color: var(--color-primary);
      text-decoration: underline;
      cursor: pointer;
    }

    .counter {
      font-size: 0.75rem;
      color: var(--color-text-muted);
      justify-self: end;
    }

    .status-line {
      display: flex;
      flex-wrap: wrap;
      gap: 0.5rem;
      align-items: center;
    }

    @media (max-width: 960px) {
      .editor-layout {
        grid-template-columns: 1fr;
      }
    }
  `,
})
export class BlogEditorComponent implements UnsavedChangesHost {
  private readonly api = inject(BlogService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  protected readonly locales = BLOG_LOCALES;
  protected readonly localeLabels = BLOG_LOCALE_LABELS;
  protected readonly statusLabels = BLOG_STATUS_LABELS;
  protected readonly limits = BLOG_LIMITS;

  protected readonly articleId = signal<string | null>(null);
  protected readonly detail = signal<BlogArticleDetail | null>(null);
  protected readonly draft = signal<ArticleDraft>(emptyDraft());
  protected readonly locale = signal<BlogLocale>('es');
  protected readonly loading = signal(true);
  protected readonly busy = signal(false);
  protected readonly uploading = signal(false);
  protected readonly error = signal<BlogError | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly conflict = signal(false);
  protected readonly publishErrors = signal<BlogPublishError[]>([]);
  protected readonly showPublished = signal(false);
  private readonly slugTouched = signal(false);
  private baseline = snapshotOf(emptyDraft());

  /** Translation (spec 017). */
  protected readonly translating = signal(false);
  /** «Traduciendo… 2/5» for articles sent in several parts. */
  protected readonly translationProgress = signal<{ done: number; total: number } | null>(null);
  protected readonly askTranslationMode = signal(false);
  /** Target locale before the last translation, for «Deshacer traducción» (FR-009). */
  protected readonly translationUndo = signal<{ locale: BlogLocale; previous: LocaleDraft } | null>(
    null,
  );

  protected readonly isNew = computed(() => this.articleId() === null);
  protected readonly status = computed(() => this.detail()?.status ?? 'draft');
  protected readonly slugLocked = computed(() => !!this.detail()?.firstPublishedAt);
  protected readonly hasPending = computed(
    () => this.status() !== 'draft' && !!this.detail()?.working,
  );
  protected readonly requiredLocales = computed<BlogLocale[]>(
    () => this.detail()?.requiredLocales ?? ['es', 'en'],
  );
  protected readonly current = computed(() => localeOf(this.draft(), this.locale()));
  protected readonly coverUrl = computed(() => this.api.mediaUrl(this.draft().coverRef));
  protected readonly slugInvalid = computed(() => {
    const slug = this.draft().slug.trim();
    return !this.draft().migrated && slug !== '' && !BLOG_SLUG_PATTERN.test(slug);
  });
  protected readonly imageUrl = (ref: string): string | null => this.api.mediaUrl(ref);

  protected readonly errorGroups = computed<ErrorGroup[]>(() => {
    const groups = new Map<string, ErrorGroup>();
    for (const item of this.publishErrors()) {
      const key = item.locale ?? 'common';
      const group = groups.get(key) ?? {
        locale: item.locale,
        label: item.locale ? BLOG_LOCALE_LABELS[item.locale] : 'General',
        fields: [],
      };
      group.fields.push(BLOG_FIELD_LABELS[item.field] ?? item.field);
      groups.set(key, group);
    }
    return [...groups.values()];
  });

  /** Content shown in the preview: the pending draft, or the published version on request. */
  protected readonly previewSource = computed(() => {
    const published = this.detail()?.published;
    if (this.showPublished() && published) {
      const content = this.locale() === 'en' ? published.en : published.es;
      return {
        title: content.title,
        summary: content.summary,
        coverAlt: content.coverAlt,
        coverUrl: this.api.mediaUrl(published.coverRef),
        blocks: content.body,
      };
    }
    const local = this.current();
    return {
      title: local.title,
      summary: local.summary,
      coverAlt: local.coverAlt,
      coverUrl: this.coverUrl(),
      blocks: fromEditorBlocks(local.blocks),
    };
  });

  /** The other locale, which the current tab translates from. */
  protected readonly translationSource = computed<BlogLocale>(() =>
    this.locale() === 'es' ? 'en' : 'es',
  );
  /** Hidden when the agency offers a single language (spec 017, edge cases). */
  protected readonly canTranslate = computed(() => this.requiredLocales().length > 1);
  protected readonly sourceHasText = computed(() =>
    hasTranslatableText(localeOf(this.draft(), this.translationSource())),
  );
  protected readonly showTranslationNotice = computed(
    () => this.translationUndo()?.locale === this.locale(),
  );

  protected readonly missingAlt = computed(() =>
    imagesMissingAlt(fromEditorBlocks(this.current().blocks)),
  );

  constructor() {
    const id = this.route.snapshot.paramMap.get('id');
    const query = this.route.snapshot.queryParamMap;
    if (id && id !== 'new') {
      this.articleId.set(id);
      void this.load(id);
    } else {
      const slug = query.get('slug') ?? '';
      const migrated = query.get('migrated') === '1';
      this.draft.set({ ...emptyDraft(), slug, migrated });
      this.slugTouched.set(slug !== '');
      this.baseline = snapshotOf(this.draft());
      this.loading.set(false);
    }
  }

  hasUnsavedChanges(): boolean {
    return !this.loading() && snapshotOf(this.draft()) !== this.baseline;
  }

  // -------------------------------------------------------------------------
  // Field editing
  // -------------------------------------------------------------------------

  protected selectLocale(locale: BlogLocale): void {
    this.locale.set(locale);
  }

  protected setSlug(event: Event): void {
    this.slugTouched.set(true);
    const slug = (event.target as HTMLInputElement).value;
    this.draft.update((draft) => ({ ...draft, slug }));
  }

  protected setMigrated(event: Event): void {
    const migrated = (event.target as HTMLInputElement).checked;
    this.draft.update((draft) => ({ ...draft, migrated }));
  }

  protected setOriginalDate(event: Event): void {
    const originalPublishedAt = (event.target as HTMLInputElement).value;
    this.draft.update((draft) => ({ ...draft, originalPublishedAt }));
  }

  protected setField(field: LocaleField, event: Event): void {
    const value = (event.target as HTMLInputElement | HTMLTextAreaElement).value;
    this.updateLocale((locale) => ({ ...locale, [field]: value }));
    if (field === 'title' && this.locale() === 'es' && this.isNew() && !this.slugTouched()) {
      this.draft.update((draft) => ({ ...draft, slug: value.trim() ? slugify(value) : '' }));
    }
  }

  protected fieldLength(field: LocaleField): number {
    return this.current()[field].length;
  }

  protected addBlock(type: BlogBlockType): void {
    this.updateLocale((locale) => ({ ...locale, blocks: [...locale.blocks, newBlock(type)] }));
  }

  protected removeBlock(key: number): void {
    this.updateLocale((locale) => ({
      ...locale,
      blocks: locale.blocks.filter((b) => b.key !== key),
    }));
  }

  protected moveBlock(key: number, delta: -1 | 1): void {
    this.updateLocale((locale) => {
      const blocks = [...locale.blocks];
      const index = blocks.findIndex((b) => b.key === key);
      const target = index + delta;
      if (index < 0 || target < 0 || target >= blocks.length) {
        return locale;
      }
      [blocks[index], blocks[target]] = [blocks[target], blocks[index]];
      return { ...locale, blocks };
    });
  }

  protected setBlock(key: number, patch: Partial<EditorBlock>): void {
    this.updateLocale((locale) => ({
      ...locale,
      blocks: locale.blocks.map((b) => (b.key === key ? { ...b, ...patch } : b)),
    }));
  }

  protected setBlockText(key: number, prop: 'markup' | 'itemsMarkup' | 'alt', event: Event): void {
    this.setBlock(key, { [prop]: (event.target as HTMLTextAreaElement | HTMLInputElement).value });
  }

  protected setBlockFlag(key: number, prop: 'ordered' | 'decorative', event: Event): void {
    this.setBlock(key, { [prop]: (event.target as HTMLInputElement).checked });
  }

  protected setHeadingLevel(key: number, event: Event): void {
    this.setBlock(key, { level: (event.target as HTMLSelectElement).value === '3' ? 3 : 2 });
  }

  // -------------------------------------------------------------------------
  // Images
  // -------------------------------------------------------------------------

  protected async onCoverSelected(event: Event): Promise<void> {
    const ref = await this.uploadFrom(event);
    if (ref) {
      this.draft.update((draft) => ({ ...draft, coverRef: ref }));
    }
  }

  protected removeCover(): void {
    this.draft.update((draft) => ({ ...draft, coverRef: null }));
  }

  protected async onBlockImageSelected(key: number, event: Event): Promise<void> {
    const ref = await this.uploadFrom(event);
    if (ref) {
      this.setBlock(key, { ref });
    }
  }

  private async uploadFrom(event: Event): Promise<string | null> {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    const id = this.articleId();
    if (!file || !id) {
      return null;
    }
    this.error.set(null);
    this.uploading.set(true);
    try {
      return await this.api.uploadImage(id, file);
    } catch (failure) {
      this.error.set(failure as BlogError);
      return null;
    } finally {
      this.uploading.set(false);
    }
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  protected async save(): Promise<boolean> {
    return this.run(async () => {
      const id = this.articleId();
      const state = await this.api.saveArticle(
        toSavePayload(this.draft(), id, this.detail()?.revision ?? null),
      );
      if (!id) {
        this.baseline = snapshotOf(this.draft());
        this.articleId.set(state.id);
        await this.router.navigate(['/cms/blog', state.id], { replaceUrl: true });
      }
      await this.load(state.id);
      this.notice.set(
        this.status() === 'draft'
          ? 'Borrador guardado.'
          : 'Cambios guardados. Aún no están en el sitio.',
      );
    });
  }

  protected async overwrite(): Promise<void> {
    const id = this.articleId();
    if (!id) {
      return;
    }
    await this.run(async () => {
      const fresh = await this.api.getArticle(id);
      await this.api.saveArticle(toSavePayload(this.draft(), id, fresh.revision));
      await this.load(id);
      this.notice.set('Guardaste tu versión encima de la otra.');
    });
  }

  protected async reload(): Promise<void> {
    const id = this.articleId();
    if (id) {
      await this.load(id);
    }
  }

  protected async publish(): Promise<void> {
    await this.saveThen(
      (id, revision) => this.api.publishArticle(id, revision),
      'Artículo publicado. Aparecerá en el sitio en 5 minutos como máximo.',
    );
  }

  protected async publishChanges(): Promise<void> {
    await this.saveThen(
      (id, revision) => this.api.publishChanges(id, revision),
      'Cambios publicados en la misma dirección.',
    );
  }

  protected async discardChanges(): Promise<void> {
    if (
      !window.confirm(
        '¿Descartar los cambios sin publicar? El sitio seguirá mostrando la versión publicada.',
      )
    ) {
      return;
    }
    await this.transition(
      (id, revision) => this.api.discardChanges(id, revision),
      'Cambios descartados.',
    );
  }

  protected async retire(): Promise<void> {
    if (
      !window.confirm(
        '¿Retirar el artículo? Dejará de verse en el sitio, pero seguirá en el panel.',
      )
    ) {
      return;
    }
    await this.transition((id, revision) => this.api.retire(id, revision), 'Artículo retirado.');
  }

  protected async republish(): Promise<void> {
    await this.transition(
      (id, revision) => this.api.republish(id, revision),
      'Artículo publicado de nuevo en la misma dirección.',
    );
  }

  protected async remove(): Promise<void> {
    const id = this.articleId();
    const revision = this.detail()?.revision;
    if (
      !id ||
      revision === undefined ||
      !window.confirm('¿Eliminar este borrador? No se puede deshacer.')
    ) {
      return;
    }
    await this.run(async () => {
      await this.api.deleteArticle(id, revision);
      this.baseline = snapshotOf(this.draft());
      await this.router.navigate(['/cms/blog']);
    });
  }

  // -------------------------------------------------------------------------
  // Translation (spec 017)
  // -------------------------------------------------------------------------

  protected requestTranslation(): void {
    if (this.translating() || !this.sourceHasText()) {
      return;
    }
    if (hasExistingText(this.current())) {
      this.askTranslationMode.set(true);
      return;
    }
    void this.translate('replace');
  }

  protected chooseTranslationMode(mode: TranslationMode | null): void {
    this.askTranslationMode.set(false);
    if (mode) {
      void this.translate(mode);
    }
  }

  protected undoTranslation(): void {
    const undo = this.translationUndo();
    if (!undo) {
      return;
    }
    this.draft.update((draft) => ({ ...draft, [undo.locale]: undo.previous }));
    this.translationUndo.set(null);
    this.locale.set(undo.locale);
  }

  /** All or nothing (FR-006): the target changes only if every segment came back. */
  private async translate(mode: TranslationMode): Promise<void> {
    const target = this.locale();
    const source = this.translationSource();
    const before = localeOf(this.draft(), target);
    this.translating.set(true);
    this.error.set(null);
    this.notice.set(null);
    try {
      const translated = await translateLocale(
        localeOf(this.draft(), source),
        before,
        mode,
        inParts(
          (segments) => this.api.translate(source, target, segments),
          (done, total) => this.translationProgress.set(total > 1 ? { done, total } : null),
        ),
      );
      if (localeOf(this.draft(), target) !== before) {
        this.error.set({
          code: 'VALIDATION_ERROR',
          message: 'Cambiaste el texto mientras se traducía. Vuelve a traducir.',
        });
        return;
      }
      this.draft.update((draft) => ({ ...draft, [target]: translated }));
      this.translationUndo.set({ locale: target, previous: before });
    } catch (failure) {
      this.error.set(withRetryTime(failure as BlogError));
    } finally {
      this.translating.set(false);
      this.translationProgress.set(null);
    }
  }

  protected focusError(locale: BlogLocale | null): void {
    if (locale) {
      this.locale.set(locale);
    }
  }

  // -------------------------------------------------------------------------

  private async saveThen(
    action: (id: string, revision: number) => Promise<unknown>,
    message: string,
  ): Promise<void> {
    if (this.isNew() || this.hasUnsavedChanges()) {
      const saved = await this.save();
      if (!saved) {
        return;
      }
    }
    await this.transition(action, message);
  }

  private async transition(
    action: (id: string, revision: number) => Promise<unknown>,
    message: string,
  ): Promise<void> {
    const id = this.articleId();
    const revision = this.detail()?.revision;
    if (!id || revision === undefined) {
      return;
    }
    await this.run(async () => {
      await action(id, revision);
      await this.load(id);
      this.notice.set(message);
    });
  }

  private async run(work: () => Promise<void>): Promise<boolean> {
    this.busy.set(true);
    this.error.set(null);
    this.notice.set(null);
    this.conflict.set(false);
    this.publishErrors.set([]);
    try {
      await work();
      return true;
    } catch (failure) {
      const error = failure as BlogError;
      this.error.set(error);
      this.conflict.set(error.code === 'ARTICLE_CONFLICT');
      this.publishErrors.set(error.publishErrors ?? []);
      return false;
    } finally {
      this.busy.set(false);
    }
  }

  private async load(id: string): Promise<void> {
    this.loading.set(true);
    try {
      const detail = await this.api.getArticle(id);
      this.detail.set(detail);
      this.draft.set(draftFrom(detail.slug, detail.working ?? detail.published, detail.migrated));
      this.baseline = snapshotOf(this.draft());
      this.showPublished.set(false);
      this.translationUndo.set(null);
    } catch (failure) {
      this.error.set(failure as BlogError);
    } finally {
      this.loading.set(false);
    }
  }

  private updateLocale(change: (locale: LocaleDraft) => LocaleDraft): void {
    const key = this.locale();
    this.draft.update((draft) => ({ ...draft, [key]: change(localeOf(draft, key)) }));
  }
}

/** Adds the local retry time to TRANSLATION_RATE_LIMITED (FR-012). */
function withRetryTime(error: BlogError): BlogError {
  if (error.code !== 'TRANSLATION_RATE_LIMITED' || !error.retryAt) {
    return error;
  }
  const at = new Date(error.retryAt);
  if (Number.isNaN(at.getTime())) {
    return error;
  }
  const time = at.toLocaleTimeString('es-CO', { hour: 'numeric', minute: '2-digit' });
  return { ...error, message: `${error.message} Podrás volver a intentarlo a las ${time}.` };
}
