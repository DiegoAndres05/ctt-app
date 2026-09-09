import { TestBed, type ComponentFixture } from '@angular/core/testing';
import { provideRouter, Router } from '@angular/router';
import { vi } from 'vitest';
import { AuthService } from '../../../core/auth/services/auth.service';
import { LoginComponent } from './login.component';

/**
 * Regression coverage for direct logins: when `/login` is opened without a
 * `returnUrl` query parameter, `withComponentInputBinding()` binds the input to
 * `undefined` (hiding its default) and the post-login redirect must still work.
 */
describe('LoginComponent returnUrl handling', () => {
  let fixture: ComponentFixture<LoginComponent>;
  let router: Router;
  let signIn: ReturnType<typeof vi.fn>;

  async function submitWith(returnUrl: string | undefined | 'UNSET'): Promise<void> {
    TestBed.resetTestingModule();
    signIn = vi.fn(async () => undefined);
    TestBed.configureTestingModule({
      imports: [LoginComponent],
      providers: [provideRouter([]), { provide: AuthService, useValue: { signIn } }],
    });
    fixture = TestBed.createComponent(LoginComponent);
    const component = fixture.componentInstance as unknown as {
      credentials: { set(value: { email: string; password: string }): void };
      onSubmit(event: Event): Promise<void>;
    };
    if (returnUrl !== 'UNSET') {
      fixture.componentRef.setInput('returnUrl', returnUrl);
    }
    component.credentials.set({ email: 'admin@demo-turismo.test', password: 'DemoPass123!' });
    router = TestBed.inject(Router);
    vi.spyOn(router, 'navigateByUrl').mockResolvedValue(true);
    await component.onSubmit(new Event('submit'));
  }

  function navigatedTo(): unknown {
    return vi.mocked(router.navigateByUrl).mock.calls[0]?.[0];
  }

  it('navigates to /dashboard when the router binds returnUrl to undefined', async () => {
    await submitWith(undefined);
    expect(signIn).toHaveBeenCalledWith('admin@demo-turismo.test', 'DemoPass123!');
    expect(navigatedTo()).toBe('/dashboard');
  });

  it('navigates to /dashboard when returnUrl was never bound', async () => {
    await submitWith('UNSET');
    expect(navigatedTo()).toBe('/dashboard');
  });

  it('rejects absolute URLs (open redirect protection)', async () => {
    await submitWith('https://evil.test/phish');
    expect(navigatedTo()).toBe('/dashboard');
  });

  it('rejects protocol-relative URLs (open redirect protection)', async () => {
    await submitWith('//evil.test/phish');
    expect(navigatedTo()).toBe('/dashboard');
  });

  it('honours an internal return path', async () => {
    await submitWith('/users');
    expect(navigatedTo()).toBe('/users');
  });
});
