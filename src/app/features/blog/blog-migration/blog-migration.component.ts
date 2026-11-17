import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import type { BlogSource } from '../../../core/blog/models/blog-article.model';
import { BlogService, type BlogError } from '../../../core/blog/services/blog.service';
import { AlertComponent } from '../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';

/** Splits the manifest textarea: one slug per line, trimmed, blanks and repeats dropped. */
export function parseManifest(text: string): string[] {
  return [
    ...new Set(
      text
        .split('\n')
        .map((line) => line.trim())
        .filter((line) => line !== ''),
    ),
  ];
}

/**
 * Blog migration from a previous blog (spec 013, US6). Administrator only.
 *
 * While the migration is open the site keeps reading its previous blog. The switch only
 * completes when every slug of the manifest has a published article in the panel.
 */
@Component({
  selector: 'app-blog-migration',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [DatePipe, RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page stack">
      <header class="page-head">
        <a routerLink="/cms/settings">Ajustes del catálogo</a>
        <h1>Migración del blog</h1>
        <p class="hint">
          Para agencias que ya tienen un blog (por ejemplo en WordPress). Copia sus artículos con el
          mismo slug y su fecha original; mientras tanto el sitio sigue leyendo el blog anterior. Si
          tu agencia no tiene blog previo, no necesitas esta pantalla: publica directamente.
        </p>
      </header>

      @if (loading()) {
        <app-spinner label="Cargando migración…" />
      } @else if (source(); as current) {
        @if (error(); as failure) {
          <app-alert kind="error">{{ failure.message }}</app-alert>
        }
        @if (notice(); as message) {
          <app-alert kind="success">{{ message }}</app-alert>
        }

        @if (current.cutoverCompletedAt) {
          <section class="card stack">
            <h2>Cambio de fuente completado</h2>
            <p>
              Desde el {{ current.cutoverCompletedAt | date: 'd MMM y, h:mm a' }} el sitio lee el
              blog solo desde el panel. Esta configuración ya no se puede cambiar.
            </p>
          </section>
        } @else {
          <section class="card stack">
            <label class="check">
              <input
                type="checkbox"
                [checked]="current.migrationRequired"
                [disabled]="busy()"
                (change)="toggleMigration($event)"
              />
              Este blog viene de un blog anterior (migración)
            </label>
            @if (current.migrationRequired) {
              <p class="hint">
                El sitio responde «legacy» al pedir el blog del panel y sigue usando el blog
                anterior.
              </p>
            }
          </section>

          @if (current.migrationRequired) {
            <section class="card stack">
              <h2>Manifiesto</h2>
              <label for="blog-manifest">Slugs que muestra el blog actual, uno por línea</label>
              <textarea
                id="blog-manifest"
                rows="8"
                [value]="manifestText()"
                (input)="manifestText.set($any($event.target).value)"
              ></textarea>
              <div class="actions">
                <span class="hint">{{ manifestCount() }} slugs</span>
                <button type="button" class="btn" (click)="saveManifest()" [disabled]="busy()">
                  Guardar manifiesto
                </button>
              </div>
            </section>

            <section class="card stack">
              <h2>Estado de la copia</h2>
              @if (current.manifest.length === 0) {
                <p class="empty">Carga el manifiesto para ver qué falta copiar.</p>
              } @else {
                <div class="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th scope="col">Slug</th>
                        <th scope="col">Estado</th>
                      </tr>
                    </thead>
                    <tbody>
                      @for (item of current.manifest; track item.slug) {
                        <tr>
                          <td>{{ item.slug }}</td>
                          <td>
                            @if (item.published) {
                              Publicado
                            } @else if (item.articleId) {
                              <a [routerLink]="['/cms/blog', item.articleId]"
                                >Copiado, sin publicar</a
                              >
                            } @else {
                              <a
                                routerLink="/cms/blog/new"
                                [queryParams]="{ migrated: 1, slug: item.slug }"
                                >Falta · copiar</a
                              >
                            }
                          </td>
                        </tr>
                      }
                    </tbody>
                  </table>
                </div>
              }

              @if (missing().length > 0) {
                <app-alert kind="warning">
                  Faltan {{ missing().length }}: {{ missing().join(', ') }}
                </app-alert>
              }

              <div class="actions">
                <button type="button" class="btn primary" (click)="complete()" [disabled]="busy()">
                  Completar cambio de fuente
                </button>
              </div>
            </section>
          }
        }
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      }
    </main>
  `,
})
export class BlogMigrationComponent {
  private readonly api = inject(BlogService);

  protected readonly source = signal<BlogSource | null>(null);
  protected readonly loading = signal(true);
  protected readonly busy = signal(false);
  protected readonly error = signal<BlogError | null>(null);
  protected readonly notice = signal<string | null>(null);
  protected readonly manifestText = signal('');
  protected readonly missing = signal<string[]>([]);

  protected readonly manifestCount = computed(() => parseManifest(this.manifestText()).length);

  constructor() {
    void this.load();
  }

  protected toggleMigration(event: Event): void {
    const required = (event.target as HTMLInputElement).checked;
    void this.run(
      () => this.api.setMigrationRequired(required),
      required ? 'Migración abierta.' : 'Migración desactivada.',
    );
  }

  protected saveManifest(): void {
    void this.run(
      () => this.api.replaceManifest(parseManifest(this.manifestText())),
      'Manifiesto guardado.',
    );
  }

  protected complete(): void {
    if (
      !window.confirm(
        '¿Completar el cambio de fuente? Desde ahora el sitio leerá el blog solo desde el panel.',
      )
    ) {
      return;
    }
    void this.run(() => this.api.completeCutover(), 'Cambio de fuente completado.');
  }

  private async run(work: () => Promise<BlogSource>, message: string): Promise<void> {
    this.busy.set(true);
    this.error.set(null);
    this.notice.set(null);
    try {
      this.apply(await work());
      this.notice.set(message);
    } catch (failure) {
      const error = failure as BlogError;
      this.error.set(error);
      if (error.missingSlugs) {
        this.missing.set(error.missingSlugs);
      }
    } finally {
      this.busy.set(false);
    }
  }

  private async load(): Promise<void> {
    this.loading.set(true);
    try {
      this.apply(await this.api.getSource());
    } catch (failure) {
      this.error.set(failure as BlogError);
    } finally {
      this.loading.set(false);
    }
  }

  private apply(source: BlogSource): void {
    this.source.set(source);
    this.missing.set(source.missing);
    this.manifestText.set(source.manifest.map((item) => item.slug).join('\n'));
  }
}
