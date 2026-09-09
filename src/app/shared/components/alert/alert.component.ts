import { ChangeDetectionStrategy, Component, input } from '@angular/core';

export type AlertKind = 'error' | 'info' | 'success';

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
      padding: 0.5rem 0.75rem;
      border-radius: 0.25rem;
    }

    .alert-error {
      color: #b3261e;
      background: #fceeee;
    }

    .alert-info {
      color: #1d4ed8;
      background: #eef4ff;
    }

    .alert-success {
      color: #166534;
      background: #ecfdf3;
    }
  `,
})
export class AlertComponent {
  readonly kind = input<AlertKind>('info');
}
