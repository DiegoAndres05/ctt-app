import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  effect,
  inject,
  signal,
  untracked,
} from '@angular/core';
import { takeUntilDestroyed, toSignal } from '@angular/core/rxjs-interop';
import { NavigationEnd, Router, RouterOutlet } from '@angular/router';
import { filter } from 'rxjs';
import { roleLabel } from '../../core/auth/models/user.model';
import { AuthService } from '../../core/auth/services/auth.service';
import { SupabaseService } from '../../core/auth/services/supabase.service';
import { AlertComponent } from '../components/alert/alert.component';
import {
  SidebarNavComponent,
  readSidebarCollapsed,
  writeSidebarCollapsed,
} from './sidebar-nav.component';
import { VerifiedNoticeComponent } from './verified-notice/verified-notice.component';

const NARROW_QUERY = '(max-width: 959px)';

/**
 * Authenticated frame: sidebar, identity bar, and the screen outlet.
 * Login, register, and mandatory password change stay outside this component.
 */
@Component({
  selector: 'app-admin-shell',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterOutlet, SidebarNavComponent, AlertComponent, VerifiedNoticeComponent],
  template: `
    <div class="shell" [class.collapsed]="collapsed() && !narrow()" [class.narrow]="narrow()">
      @if (narrow() && drawerOpen()) {
        <button
          type="button"
          class="backdrop"
          aria-label="Cerrar menú"
          (click)="drawerOpen.set(false)"
        ></button>
      }
      <div class="sidebar-slot" [class.open]="!narrow() || drawerOpen()">
        <app-sidebar-nav
          [collapsed]="collapsed() && !narrow()"
          [collapsible]="!narrow()"
          [organizationName]="organizationName()"
          (navigated)="drawerOpen.set(false)"
          (collapseChange)="setCollapsed($event)"
          (signOut)="onSignOut()"
        />
      </div>

      <div class="main">
        <header class="topbar">
          @if (narrow()) {
            <button type="button" (click)="drawerOpen.set(!drawerOpen())">Menú</button>
          } @else {
            <button type="button" (click)="toggleCollapsed()">
              {{ collapsed() ? 'Expandir menú' : 'Contraer menú' }}
            </button>
          }

          @if (auth.user(); as identity) {
            <p class="identity">
              <span>{{ auth.profile()?.full_name || identity.email }}</span>
              <span>{{ roleLabel(identity.role) }}</span>
              <span>{{ organizationName() || identity.organizationId }}</span>
            </p>
          }

          <button type="button" (click)="onSignOut()">Cerrar sesión</button>
        </header>

        @if (denied()) {
          <div class="denied">
            <app-alert kind="error">No tienes permisos para realizar esta acción.</app-alert>
          </div>
        }

        <div class="content">
          <app-verified-notice />
          <router-outlet />
        </div>
      </div>
    </div>
  `,
  styles: `
    .shell {
      min-height: 100vh;
      display: grid;
      grid-template-columns: 16rem minmax(0, 1fr);
      background: var(--color-bg);
    }

    .shell.collapsed {
      grid-template-columns: 4.75rem minmax(0, 1fr);
    }

    .shell.narrow {
      grid-template-columns: minmax(0, 1fr);
    }

    .sidebar-slot {
      position: sticky;
      top: 0;
      align-self: start;
      height: 100vh;
    }

    .narrow .sidebar-slot {
      position: fixed;
      z-index: 30;
      inset: 0 auto 0 0;
      width: min(16rem, 92vw);
      transform: translateX(-105%);
      transition: transform 0.2s ease;
    }

    .narrow .sidebar-slot.open {
      transform: none;
    }

    .backdrop {
      position: fixed;
      inset: 0;
      z-index: 20;
      border: 0;
      background: rgb(15 23 42 / 45%);
    }

    .main {
      min-width: 0;
      display: grid;
      grid-template-rows: auto auto 1fr;
    }

    .topbar {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      padding: 0.45rem 1.25rem;
      background: #fff;
      border-bottom: 1px solid #edf0f5;
      min-height: 2rem;
    }
    .topbar button {
      border: 1px solid #e2e8f0;
      background: #fff;
      color: #1e293b;
      border-radius: 0.5rem;
      font-size: 0.95rem;
      padding: 0.5rem 0.85rem;
    }

    .identity {
      display: flex;
      flex-wrap: wrap;
      gap: 0.35rem 0.8rem;
      margin: 0;
      flex: 1;
      font-size: 0.85rem;
      color: #536178;
    }

    .identity span + span::before {
      content: '·';
      margin-right: 0.8rem;
      color: #cbd5e1;
    }

    .denied,
    .content {
      padding: 0.9rem 1.35rem 1.5rem;
    }

    .denied {
      padding-bottom: 0;
    }
  `,
})
export class AdminShellComponent {
  protected readonly auth = inject(AuthService);
  private readonly supabase = inject(SupabaseService);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);

  protected readonly roleLabel = roleLabel;
  protected readonly collapsed = signal(readSidebarCollapsed());
  protected readonly narrow = signal(false);
  protected readonly drawerOpen = signal(false);
  protected readonly organizationName = signal<string | null>(null);

  private readonly query = toSignal(this.router.routerState.root.queryParamMap, {
    initialValue: this.router.routerState.root.snapshot.queryParamMap,
  });

  protected readonly denied = () => this.query().get('denied') === '1';

  constructor() {
    const media = window.matchMedia(NARROW_QUERY);
    this.narrow.set(media.matches);
    const onChange = (event: MediaQueryListEvent) => {
      this.narrow.set(event.matches);
      if (event.matches) {
        this.drawerOpen.set(false);
      }
    };
    media.addEventListener('change', onChange);
    this.destroyRef.onDestroy(() => media.removeEventListener('change', onChange));

    this.router.events
      .pipe(
        filter((event) => event instanceof NavigationEnd),
        takeUntilDestroyed(this.destroyRef),
      )
      .subscribe(() => this.drawerOpen.set(false));

    effect(() => {
      const organizationId = this.auth.organizationId();
      if (!organizationId) {
        return;
      }
      untracked(() => {
        void this.loadOrganization(organizationId);
      });
    });
  }

  protected toggleCollapsed(): void {
    this.setCollapsed(!this.collapsed());
  }

  protected setCollapsed(next: boolean): void {
    this.collapsed.set(next);
    writeSidebarCollapsed(next);
  }

  protected async onSignOut(): Promise<void> {
    await this.auth.signOut();
    await this.router.navigateByUrl('/login');
  }

  private async loadOrganization(organizationId: string): Promise<void> {
    const { data } = await this.supabase.client
      .from('organizations')
      .select('name')
      .eq('id', organizationId)
      .maybeSingle<{ name: string }>();
    this.organizationName.set(data?.name ?? null);
  }
}
