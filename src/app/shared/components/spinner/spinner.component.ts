import { ChangeDetectionStrategy, Component, input } from '@angular/core';

/**
 * Accessible loading indicator. The label is the accessible name; the spinning mark is hidden
 * from assistive technology so it is not announced as punctuation.
 */
@Component({
  selector: 'app-spinner',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <p class="spinner" role="status" [attr.aria-label]="label()">
      <span class="mark" aria-hidden="true"></span>
      <span>{{ label() }}</span>
    </p>
  `,
  styles: `
    .spinner {
      display: inline-flex;
      align-items: center;
      gap: 0.5rem;
      margin: 0;
    }

    .mark {
      width: 0.85rem;
      height: 0.85rem;
      border: 2px solid currentColor;
      border-right-color: transparent;
      border-radius: 50%;
      animation: spin 0.7s linear infinite;
    }

    @keyframes spin {
      to {
        transform: rotate(360deg);
      }
    }
  `,
})
export class SpinnerComponent {
  readonly label = input('Cargando…');
}
