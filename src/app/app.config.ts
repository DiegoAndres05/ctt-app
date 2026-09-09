import { ApplicationConfig, ErrorHandler, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideHttpClient, withFetch, withInterceptors } from '@angular/common/http';
import { provideRouter, withComponentInputBinding } from '@angular/router';
import { AppErrorHandler } from './core/error/error-handler';
import { sessionInterceptor } from './core/auth/interceptors/session.interceptor';
import { routes } from './app.routes';

/**
 * Root providers.
 *
 * Change detection is zoneless: Angular 22 applications are zoneless by default and the
 * workspace carries no `zone.js` dependency. Session state is therefore driven purely by
 * signals in `AuthService`.
 *
 * `withComponentInputBinding()` is what lets the login screen receive `returnUrl` and `reason`
 * from the query string as inputs.
 */
export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideRouter(routes, withComponentInputBinding()),
    provideHttpClient(withFetch(), withInterceptors([sessionInterceptor])),
    { provide: ErrorHandler, useClass: AppErrorHandler },
  ],
};
