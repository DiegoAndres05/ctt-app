import { ChangeDetectionStrategy, Component, computed, input, output } from '@angular/core';
import { AlertComponent } from '../alert/alert.component';
import { SpinnerComponent } from '../spinner/spinner.component';
import { LIST_PAGE_SIZE, pageCount } from './list-query';

/**
 * Shared list chrome: title, create slot, filters, table, pagination, empty and no-results.
 */
@Component({
  selector: 'app-data-table',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [AlertComponent, SpinnerComponent],
  template: `
    <section class="list">
      <header>
        <h1>{{ title() }}</h1>
        <div class="create">
          <ng-content select="[dataTableCreate]" />
        </div>
      </header>

      <div class="filters">
        <ng-content select="[dataTableFilters]" />
      </div>

      @if (loading()) {
        <app-spinner [label]="loadingLabel()" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure }}</app-alert>
      } @else if (total() === 0 && !filtered()) {
        <p class="empty">{{ emptyMessage() }}</p>
      } @else if (total() === 0) {
        <p class="empty">No hay resultados para esta búsqueda.</p>
        <button type="button" (click)="clearFilters.emit()">Limpiar filtros</button>
      } @else {
        <div class="table-wrap">
          <ng-content />
        </div>
        <nav class="pager" aria-label="Paginación">
          <button type="button" [disabled]="page() <= 1" (click)="pageChange.emit(page() - 1)">
            Anterior
          </button>
          <span>Página {{ page() }} de {{ pages() }}</span>
          <button
            type="button"
            [disabled]="page() >= pages()"
            (click)="pageChange.emit(page() + 1)"
          >
            Siguiente
          </button>
        </nav>
      }
    </section>
  `,
  styles: `
    .list {
      display: grid;
      gap: 0.9rem;
    }

    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 1rem;
    }

    h1 {
      margin: 0;
      font-size: 1.6rem;
    }

    .filters {
      display: flex;
      flex-wrap: wrap;
      gap: 0.75rem;
      align-items: end;
    }

    .empty {
      margin: 0;
    }

    .pager {
      display: flex;
      align-items: center;
      gap: 0.75rem;
    }

    .table-wrap {
      overflow-x: auto;
    }
  `,
})
export class DataTableComponent {
  readonly title = input.required<string>();
  readonly loading = input(false);
  readonly error = input<string | null>(null);
  readonly total = input(0);
  readonly page = input(1);
  readonly pageSize = input(LIST_PAGE_SIZE);
  readonly filtered = input(false);
  readonly emptyMessage = input('Todavía no hay registros.');
  readonly loadingLabel = input('Cargando…');
  readonly pageChange = output<number>();
  readonly clearFilters = output<void>();

  protected readonly pages = computed(() => pageCount(this.total(), this.pageSize()));
}
