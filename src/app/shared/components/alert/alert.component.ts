import { ChangeDetectionStrategy, Component, input } from '@angular/core';

export type AlertKind = 'error' | 'info' | 'success' | 'warning';

/**
 * Inline status banner for forms and lists.
 *
 * Errors use `role="alert"` so a screen reader announces them when they appear; everything
 * else is `status`.
 */
@Component({
  selector: 'app-alert',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <p
      class="alert"
      [class]="'alert alert-' + kind()"
      [attr.role]="kind() === 'error' ? 'alert' : 'status'"
    >
      <ng-content />
    </p>
  `,
  styles: `
    .alert {
      margin: 0;
      padding: 0.65rem 0.9rem;
      border: 1px solid transparent;
      border-radius: var(--radius-md);
      font-size: 0.925rem;
    }

    .alert-error {
      color: var(--color-danger);
      background: var(--color-danger-bg);
      border-color: var(--color-danger-border);
    }

    .alert-info {
      color: var(--color-info);
      background: var(--color-info-bg);
      border-color: var(--color-info-border);
    }

    .alert-success {
      color: var(--color-success);
      background: var(--color-success-bg);
      border-color: var(--color-success-border);
    }

    .alert-warning {
      color: var(--color-warning);
      background: var(--color-warning-bg);
      border-color: var(--color-warning-border);
    }
  `,
})
export class AlertComponent {
  readonly kind = input<AlertKind>('info');
}
