import { NgTemplateOutlet } from '@angular/common';
import { ChangeDetectionStrategy, Component, input } from '@angular/core';
import type { BlogBlock, InlineRun } from '../../../core/blog/models/blog-blocks';

/**
 * Renders a block document with the mapping of contracts/public-consumer.md. Every text goes
 * through interpolation, so it is always escaped; there is no innerHTML anywhere.
 */
@Component({
  selector: 'app-blog-preview',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <article class="preview" lang="{{ locale() }}">
      @if (coverUrl(); as url) {
        <img class="cover" [src]="url" [alt]="coverAlt() ?? ''" />
      }
      <h1>{{ title() || 'Sin título' }}</h1>
      @if (summary()) {
        <p class="summary">{{ summary() }}</p>
      }

      @for (block of blocks(); track $index) {
        @switch (block.type) {
          @case ('paragraph') {
            <p><ng-container *ngTemplateOutlet="runs; context: { $implicit: block.text }" /></p>
          }
          @case ('heading') {
            @if (block.level === 3) {
              <h3><ng-container *ngTemplateOutlet="runs; context: { $implicit: block.text }" /></h3>
            } @else {
              <h2><ng-container *ngTemplateOutlet="runs; context: { $implicit: block.text }" /></h2>
            }
          }
          @case ('quote') {
            <blockquote>
              <ng-container *ngTemplateOutlet="runs; context: { $implicit: block.text }" />
            </blockquote>
          }
          @case ('list') {
            @if (block.ordered) {
              <ol>
                @for (item of block.items; track $index) {
                  <li><ng-container *ngTemplateOutlet="runs; context: { $implicit: item }" /></li>
                }
              </ol>
            } @else {
              <ul>
                @for (item of block.items; track $index) {
                  <li><ng-container *ngTemplateOutlet="runs; context: { $implicit: item }" /></li>
                }
              </ul>
            }
          }
          @case ('image') {
            <img
              class="body-image"
              [src]="imageUrl()(block.ref)"
              [alt]="block.decorative ? '' : (block.alt ?? '')"
            />
          }
        }
      }
    </article>

    <ng-template #runs let-items>
      @for (run of asRuns(items); track $index) {
        @if (run.href) {
          <a [href]="run.href" rel="noopener" target="_blank">{{ run.text }}</a>
        } @else if (run.bold) {
          <strong>{{ run.text }}</strong>
        } @else if (run.italic) {
          <em>{{ run.text }}</em>
        } @else {
          {{ run.text }}
        }
      }
    </ng-template>
  `,
  imports: [NgTemplateOutlet],
  styles: `
    .preview {
      display: grid;
      gap: 0.75rem;
      padding: 1rem;
      border: 1px solid var(--color-border);
      border-radius: var(--radius-lg);
      background: var(--color-surface);
    }

    .preview h1 {
      margin: 0;
      font-size: 1.4rem;
    }

    .summary {
      color: var(--color-text-muted);
    }

    .cover,
    .body-image {
      max-width: 100%;
      border-radius: var(--radius-md);
    }

    blockquote {
      margin: 0;
      padding-left: 0.85rem;
      border-left: 3px solid var(--color-border-strong);
    }
  `,
})
export class BlogPreviewComponent {
  readonly locale = input<string>('es');
  readonly title = input<string | null>(null);
  readonly summary = input<string | null>(null);
  readonly coverUrl = input<string | null>(null);
  readonly coverAlt = input<string | null>(null);
  readonly blocks = input<readonly BlogBlock[]>([]);
  readonly imageUrl = input<(ref: string) => string | null>(() => null);

  protected asRuns(value: unknown): InlineRun[] {
    return Array.isArray(value) ? (value as InlineRun[]) : [];
  }
}
