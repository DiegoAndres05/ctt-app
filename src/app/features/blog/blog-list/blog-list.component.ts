import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import {
  BLOG_LOCALE_LABELS,
  BLOG_STATUS_LABELS,
  type BlogArticleStatus,
  type BlogArticleSummary,
} from '../../../core/blog/models/blog-article.model';
import { BlogService } from '../../../core/blog/services/blog.service';
import type { AppError } from '../../../core/error/error-handler';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';

/**
 * Blog articles of the agency (spec 013, US1). Operator and Administrator only: the route has
 * roleGuard('operator') and the RPC re-checks the role.
 */
@Component({
  selector: 'app-blog-list',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page stack">
      <header class="page-head">
        <h1>Blog</h1>
        <p class="hint">
          Artículos que el sitio de tu agencia muestra en su blog. Lo publicado aparece en el sitio
          en 5 minutos como máximo.
        </p>
      </header>

      <div class="filters-bar">
        <label for="blog-status">
          Estado
          <select id="blog-status" [value]="status() ?? ''" (change)="onStatus($event)">
            <option value="">Todos</option>
            <option value="draft">Borrador</option>
            <option value="published">Publicado</option>
            <option value="retired">Retirado</option>
          </select>
        </label>
        <a class="btn primary" routerLink="/cms/blog/new">Nuevo artículo</a>
      </div>

      @if (loading()) {
        <app-spinner label="Cargando artículos…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (articles().length === 0) {
        <p class="empty">
          @if (status()) {
            No hay artículos con ese estado.
          } @else {
            Todavía no hay artículos. Crea el primero con «Nuevo artículo».
          }
        </p>
      } @else {
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">Título</th>
                <th scope="col">Estado</th>
                <th scope="col">Idiomas completos</th>
                <th scope="col">Publicado</th>
                <th scope="col">Última edición</th>
              </tr>
            </thead>
            <tbody>
              @for (article of articles(); track article.id) {
                <tr>
                  <td>
                    <a [routerLink]="['/cms/blog', article.id]">{{
                      article.title || article.slug
                    }}</a>
                    <span class="hint slug">/{{ article.slug }}</span>
                  </td>
                  <td>
                    {{ statusLabels[article.status] }}
                    @if (article.hasPendingChanges) {
                      <span class="tag">Cambios sin publicar</span>
                    }
                    @if (article.migrated) {
                      <span class="hint">· migrado</span>
                    }
                  </td>
                  <td>
                    @for (locale of article.completeLocales; track locale) {
                      <span class="lang">{{ localeLabels[locale] }}</span>
                    } @empty {
                      <span class="hint">Ninguno</span>
                    }
                  </td>
                  <td>
                    {{
                      article.firstPublishedAt ? (article.firstPublishedAt | date: 'd MMM y') : '—'
                    }}
                  </td>
                  <td>{{ article.updatedAt | date: 'd MMM y, h:mm a' }}</td>
                </tr>
              }
            </tbody>
          </table>
        </div>
      }
    </main>
  `,
  styles: `
    .slug {
      display: block;
    }

    .lang + .lang::before {
      content: ' · ';
    }

    .filters-bar {
      justify-content: space-between;
    }
  `,
})
export class BlogListComponent {
  private readonly api = inject(BlogService);

  protected readonly statusLabels = BLOG_STATUS_LABELS;
  protected readonly localeLabels = BLOG_LOCALE_LABELS;

  protected readonly status = signal<BlogArticleStatus | null>(null);
  protected readonly articles = signal<BlogArticleSummary[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);

  constructor() {
    void this.load();
  }

  protected onStatus(event: Event): void {
    const value = (event.target as HTMLSelectElement).value;
    this.status.set(
      value === 'draft' || value === 'published' || value === 'retired' ? value : null,
    );
    void this.load();
  }

  private async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.articles.set(await this.api.listArticles(this.status()));
    } catch (failure) {
      this.error.set(failure as AppError);
    } finally {
      this.loading.set(false);
    }
  }
}
