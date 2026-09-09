import { TestBed } from '@angular/core/testing';
import { provideRouter, type UrlTree } from '@angular/router';
import type { AppRole } from '../models/user.model';
import { AuthService } from '../services/auth.service';
import { roleGuard } from './role.guard';

describe('roleGuard', () => {
  async function activate(actual: AppRole | null, required: AppRole): Promise<boolean | UrlTree> {
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      providers: [
        provideRouter([{ path: 'dashboard', children: [] }]),
        {
          provide: AuthService,
          useValue: {
            whenInitialized: async () => undefined,
            role: () => actual,
          },
        },
      ],
    });

    const result = await TestBed.runInInjectionContext(() =>
      Promise.resolve(
        roleGuard(required)(
          // The factory closes over `required`; the snapshots are unused.
          {} as never,
          {} as never,
        ),
      ),
    );
    return result as boolean | UrlTree;
  }

  function isDenied(result: boolean | UrlTree): boolean {
    return (
      result !== true &&
      String(result).includes('/dashboard') &&
      String(result).includes('denied=1')
    );
  }

  it('lets an admin through an admin-only route', async () => {
    await expect(activate('admin', 'admin')).resolves.toBe(true);
  });

  it('lets an admin through an operator-required route (hierarchy)', async () => {
    await expect(activate('admin', 'operator')).resolves.toBe(true);
  });

  it('lets an operator through an agent-required route (hierarchy)', async () => {
    await expect(activate('operator', 'agent')).resolves.toBe(true);
  });

  it('turns an operator away from an admin-only route', async () => {
    expect(isDenied(await activate('operator', 'admin'))).toBe(true);
  });

  it('turns an agent away from user-management routes', async () => {
    expect(isDenied(await activate('agent', 'admin'))).toBe(true);
  });

  it('turns a session with no role away', async () => {
    expect(isDenied(await activate(null, 'agent'))).toBe(true);
  });
});
