import type { CanDeactivateFn } from '@angular/router';

/** A form screen that can warn before the collaborator leaves with pending edits. */
export interface UnsavedChangesHost {
  hasUnsavedChanges(): boolean;
}

export const unsavedChangesGuard: CanDeactivateFn<UnsavedChangesHost> = (component) => {
  if (!component?.hasUnsavedChanges?.()) {
    return true;
  }
  return window.confirm('Hay cambios sin guardar. Si sales, se perderán. ¿Quieres salir?');
};
