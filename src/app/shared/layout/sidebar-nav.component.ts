import {
  ChangeDetectionStrategy,
  Component,
  computed,
  effect,
  inject,
  input,
  output,
  signal,
  untracked,
} from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { NavigationEnd, Router, RouterLink } from '@angular/router';
import { filter, map, startWith } from 'rxjs';
import { AuthService } from '../../core/auth/services/auth.service';
import {
  activeNavItemId,
  parentIdsForActive,
  visibleNavItems,
  type NavItem,
} from './nav-items';

const COLLAPSED_KEY = 'ctt.sidebar.collapsed';

/**
 * Left navigation. Groups stay open on the active child. Desktop icon mode is remembered
 * on this device; viewports under 960px use a drawer and ignore that preference.
 */
@Component({
  selector: 'app-sidebar-nav',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  template: `
    <nav class="sidebar" [class.collapsed]="collapsed()" aria-label="Principal">
      <ul class="groups">
        @for (item of items(); track item.id) {
          <li>
            @if (item.children; as children) {
              @if (collapsed()) {
                <ul class="children icons">
                  @for (child of children; track child.id) {
                    <li>
                      <a
                        [routerLink]="child.path"
                        [title]="child.label"
                        [class.active]="child.id === activeId()"
                        [attr.aria-current]="child.id === activeId() ? 'page' : null"
                        (click)="navigated.emit()"
                      >
                        <span aria-hidden="true">{{ glyph(child) }}</span>
                        <span class="sr">{{ child.label }}</span>
                      </a>
                    </li>
                  }
                </ul>
              } @else {
                <button
                  type="button"
                  class="group"
                  [class.active]="isGroupActive(item)"
                  [attr.aria-expanded]="isExpanded(item.id)"
                  (click)="toggle(item.id)"
                >
                  {{ item.label }}
                </button>
                @if (isExpanded(item.id)) {
                  <ul class="children">
                    @for (child of children; track child.id) {
                      <li>
                        <a
                          [routerLink]="child.path"
                          [class.active]="child.id === activeId()"
                          [attr.aria-current]="child.id === activeId() ? 'page' : null"
                          (click)="navigated.emit()"
                        >
                          {{ child.label }}
                        </a>
                      </li>
                    }
                  </ul>
                }
              }
            } @else if (item.path) {
              <a
                class="top"
                [routerLink]="item.path"
                [title]="collapsed() ? item.label : ''"
                [class.active]="item.id === activeId()"
                [attr.aria-current]="item.id === activeId() ? 'page' : null"
                (click)="navigated.emit()"
              >
                @if (collapsed()) {
                  <span aria-hidden="true">{{ glyph(item) }}</span>
                  <span class="sr">{{ item.label }}</span>
                } @else {
                  {{ item.label }}
                }
              </a>
            }
          </li>
        }
      </ul>
    </nav>
  `,
  styles: `
    .sidebar {
      background: #1c1917;
      color: #fafaf9;
      min-height: 100%;
      padding: 0.75rem 0.5rem;
    }

    .groups,
    .children {
      list-style: none;
      margin: 0;
      padding: 0;
      display: grid;
      gap: 0.25rem;
    }

    .children {
      padding: 0.25rem 0 0.5rem 0.75rem;
    }

    a,
    .group {
      display: block;
      width: 100%;
      text-align: left;
      color: inherit;
      text-decoration: none;
      background: transparent;
      border: 0;
      border-radius: 0.35rem;
      padding: 0.45rem 0.6rem;
      font: inherit;
      cursor: pointer;
    }

    a.active,
    .group.active {
      background: #44403c;
    }

    a:hover,
    .group:hover {
      background: #292524;
    }

    .collapsed a {
      text-align: center;
      font-weight: 700;
    }

    .icons {
      padding-left: 0;
    }

    .sr {
      position: absolute;
      width: 1px;
      height: 1px;
      overflow: hidden;
      clip: rect(0 0 0 0);
    }
  `,
})
export class SidebarNavComponent {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  readonly collapsed = input(false);
  readonly navigated = output<void>();

  private readonly url = toSignal(
    this.router.events.pipe(
      filter((event) => event instanceof NavigationEnd),
      map(() => this.router.url),
      startWith(this.router.url),
    ),
    { initialValue: this.router.url },
  );

  protected readonly items = computed(() => visibleNavItems(this.auth.role()));
  protected readonly activeId = computed(() => activeNavItemId(this.items(), this.url()));
  private readonly expanded = signal<ReadonlySet<string>>(new Set<string>());

  constructor() {
    effect(() => {
      const parents = parentIdsForActive(this.items(), this.activeId());
      untracked(() => {
        if (parents.length === 0) {
          return;
        }
        this.expanded.update((current) => {
          const next = new Set(current);
          for (const id of parents) {
            next.add(id);
          }
          return next;
        });
      });
    });
  }

  protected isExpanded(id: string): boolean {
    return this.expanded().has(id);
  }

  protected isGroupActive(item: NavItem): boolean {
    return (item.children ?? []).some((child) => child.id === this.activeId());
  }

  protected toggle(id: string): void {
    this.expanded.update((current) => {
      const next = new Set(current);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }

  protected glyph(item: NavItem): string {
    return item.label.slice(0, 1).toUpperCase();
  }
}

export function readSidebarCollapsed(): boolean {
  try {
    return localStorage.getItem(COLLAPSED_KEY) === 'true';
  } catch {
    return false;
  }
}

export function writeSidebarCollapsed(collapsed: boolean): void {
  try {
    localStorage.setItem(COLLAPSED_KEY, collapsed ? 'true' : 'false');
  } catch {
    // Private mode or a blocked storage API: the menu still works for this visit.
  }
}
