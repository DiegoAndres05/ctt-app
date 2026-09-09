import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { toAppError, type AppError } from '../../../../core/error/error-handler';
import type { Addon, AddonUnit } from '../../../../core/catalog/models/addon.model';
import { AddonService } from '../../../../core/catalog/services/addon.service';
import { AlertComponent } from '../../../../shared/components/alert/alert.component';
import { SpinnerComponent } from '../../../../shared/components/spinner/spinner.component';

/**
 * Independent add-ons (User Story 2). Operator/Admin via `roleGuard`; RLS still scopes the rows.
 */
@Component({
  selector: 'app-addon-list',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, AlertComponent, SpinnerComponent],
  template: `
    <main class="page">
      <header>
        <div>
          <a routerLink="/catalog">Catálogo</a>
          <h1>Complementos</h1>
        </div>
        <a routerLink="/catalog/addons/new">Nuevo complemento</a>
      </header>

      @if (loading()) {
        <app-spinner label="Cargando complementos…" />
      } @else if (error(); as failure) {
        <app-alert kind="error">{{ failure.message }}</app-alert>
      } @else if (addons().length === 0) {
        <p>No hay complementos en esta organización.</p>
      } @else {
        <table>
          <thead>
            <tr>
              <th>Nombre</th>
              <th>Unidad</th>
              <th>Estado</th>
            </tr>
          </thead>
          <tbody>
            @for (addon of addons(); track addon.id) {
              <tr>
                <td>
                  <a [routerLink]="['/catalog/addons', addon.id]">{{ addon.name }}</a>
                </td>
                <td>{{ unitLabel(addon.unit) }}</td>
                <td>{{ addon.is_active ? 'Activo' : 'Inactivo' }}</td>
              </tr>
            }
          </tbody>
        </table>
      }
    </main>
  `,
  styles: `
    .page {
      padding: 1.5rem;
      display: grid;
      gap: 1rem;
    }

    header {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 1rem;
    }

    h1 {
      margin: 0.25rem 0 0;
    }

    table {
      width: 100%;
      border-collapse: collapse;
    }

    th,
    td {
      text-align: left;
      padding: 0.4rem 0.5rem;
      border-bottom: 1px solid #ddd;
    }
  `,
})
export class AddonListComponent {
  private readonly addonsApi = inject(AddonService);

  protected readonly addons = signal<Addon[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<AppError | null>(null);

  constructor() {
    void this.refresh();
  }

  protected unitLabel(unit: AddonUnit): string {
    switch (unit) {
      case 'per_person':
        return 'Por persona';
      case 'per_unit':
        return 'Por unidad';
      case 'per_service':
        return 'Por servicio';
    }
  }

  private async refresh(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.addons.set(await this.addonsApi.list());
    } catch (failure) {
      this.error.set(toAppError(failure));
    } finally {
      this.loading.set(false);
    }
  }
}
