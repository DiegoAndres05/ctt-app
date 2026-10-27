import { NgTemplateOutlet } from '@angular/common';
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
import { roleLabel } from '../../core/auth/models/user.model';
import { AuthService } from '../../core/auth/services/auth.service';
import { activeNavItemId, parentIdsForActive, visibleNavItems, type NavItem } from './nav-items';

const COLLAPSED_KEY = 'ctt.sidebar.collapsed';

const SECTIONS: readonly { label: string; ids: readonly string[] }[] = [
  { label: 'Operaciones', ids: ['dashboard', 'sales', 'reports'] },
  { label: 'Gestión y ajustes', ids: ['settings', 'cms'] },
];

/**
 * Left navigation. Groups stay open on the active child. Desktop icon mode is remembered
 * on this device; viewports under 960px use a drawer and ignore that preference.
 */
@Component({
  selector: 'app-sidebar-nav',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, NgTemplateOutlet],
  template: `
    <nav class="sidebar" [class.collapsed]="collapsed()" aria-label="Principal">
      <div class="brand">
        <span class="brand-mark" aria-hidden="true">
          <svg viewBox="0 0 24 24">
            <circle cx="12" cy="12" r="8" />
            <path d="M4 12h16M12 4c2.4 2.6 2.4 13.4 0 16M12 4c-2.4 2.6-2.4 13.4 0 16" />
          </svg>
        </span>
        @if (!collapsed()) {
          <span class="brand-copy">
            <strong>{{ organizationName() || 'Panel' }}</strong>
            <small>Turismo B2B Suite</small>
          </span>
        }
        @if (collapsible()) {
          <button
            type="button"
            class="icon-btn"
            [attr.aria-label]="collapsed() ? 'Expandir menú' : 'Contraer menú'"
            (click)="collapseChange.emit(!collapsed())"
          >
            <svg viewBox="0 0 24 24"><path d="M5 7h14M5 12h14M5 17h14" /></svg>
          </button>
        }
      </div>

      <div class="scroll">
        @for (section of sections(); track section.label) {
          @if (!collapsed()) {
            <p class="kicker">{{ section.label }}</p>
          }
          <ul>
            @for (item of section.items; track item.id) {
              <li>
                @if (item.children; as children) {
                  @if (collapsed()) {
                    <button
                      type="button"
                      class="row"
                      [class.branch]="isGroupActive(item)"
                      [title]="displayLabel(item)"
                      [attr.aria-label]="displayLabel(item)"
                      (click)="openFromRail(item.id)"
                    >
                      <ng-container [ngTemplateOutlet]="glyph" [ngTemplateOutletContext]="{ $implicit: item.id }" />
                    </button>
                  } @else {
                    <button
                      type="button"
                      class="row"
                      [class.branch]="isGroupActive(item)"
                      [attr.aria-expanded]="isExpanded(item.id)"
                      (click)="toggle(item.id)"
                    >
                      <ng-container [ngTemplateOutlet]="glyph" [ngTemplateOutletContext]="{ $implicit: item.id }" />
                      <span>{{ displayLabel(item) }}</span>
                      <svg class="chevron" [class.open]="isExpanded(item.id)" viewBox="0 0 24 24">
                        <path d="M9 6l6 6-6 6" />
                      </svg>
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
                    class="row"
                    [routerLink]="item.path"
                    [title]="collapsed() ? displayLabel(item) : ''"
                    [attr.aria-label]="collapsed() ? displayLabel(item) : null"
                    [class.active]="item.id === activeId()"
                    [attr.aria-current]="item.id === activeId() ? 'page' : null"
                    (click)="navigated.emit()"
                  >
                    <ng-container [ngTemplateOutlet]="glyph" [ngTemplateOutletContext]="{ $implicit: item.id }" />
                    @if (!collapsed()) {
                      <span>{{ displayLabel(item) }}</span>
                      @if (item.id === activeId()) {
                        <span class="dot"></span>
                      }
                    }
                  </a>
                }
              </li>
            }
          </ul>
        }
      </div>

      <div class="footer">
        <span class="avatar" aria-hidden="true">
          {{ initials() }}
          @if (sessionActive()) {
            <span class="presence"></span>
          }
        </span>
        @if (!collapsed()) {
          <span class="who">
            <strong>{{ userName() || 'Sesión' }}</strong>
            @if (roleName()) {
              <small>{{ roleName() }}</small>
            }
          </span>
        }
        <button type="button" class="icon-btn" aria-label="Cerrar sesión" (click)="signOut.emit()">
          <svg viewBox="0 0 24 24">
            <path d="M10 7V5h9v14h-9v-2" />
            <path d="M14 12H4m0 0 3-3M4 12l3 3" />
          </svg>
        </button>
      </div>
    </nav>

    <ng-template #glyph let-id>
      <svg class="icon" viewBox="0 0 24 24" aria-hidden="true">
        @switch (id) {
          @case ('dashboard') {
            <rect x="4" y="4" width="6.5" height="6.5" rx="1.3" />
            <rect x="13.5" y="4" width="6.5" height="6.5" rx="1.3" />
            <rect x="4" y="13.5" width="6.5" height="6.5" rx="1.3" />
            <rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.3" />
          }
          @case ('sales') {
            <path d="M4 20.5h16M6 20.5V6.5h12v14" />
            <path d="M10 20.5v-4h4v4M9 9.5h1.5M13.5 9.5H15M9 13h1.5M13.5 13H15" />
          }
          @case ('reports') {
            <path d="M5 19V5M5 19h14" />
            <path d="M9 16v-4M13 16V8M17 16v-2" />
          }
          @case ('settings') {
            <path d="M10.1 2.6h3.8l.5 2.2a6.5 6.5 0 0 1 1.7 1l2-.9 2.6 2.6-.9 2a6.5 6.5 0 0 1 1 1.7l2.2.5v3.8l-2.2.5a6.5 6.5 0 0 1-1 1.7l.9 2-2.6 2.6-2-.9a6.5 6.5 0 0 1-1.7 1l-.5 2.2h-3.8l-.5-2.2a6.5 6.5 0 0 1-1.7-1l-2 .9-2.6-2.6.9-2a6.5 6.5 0 0 1-1-1.7l-2.2-.5V9.7l2.2-.5a6.5 6.5 0 0 1 1-1.7l-.9-2 2.6-2.6 2 .9a6.5 6.5 0 0 1 1.7-1l.5-2.2z" />
            <circle cx="12" cy="12" r="2.5" />
          }
          @default {
            <path d="M7 3.5h7l5 5V20a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4.5a1 1 0 0 1 1-1z" />
            <path d="M14 3.5V9h5.5" />
          }
        }
      </svg>
    </ng-template>
  `,
  styles: `
    :host { display: flex; height: 100%; min-height: 0; }
    .sidebar {
      background: #202830;
      color: #e7eef5;
      flex: 1;
      min-height: 0;
      overflow: hidden;
      padding: 0.85rem 0.65rem 0.7rem;
      box-sizing: border-box;
      display: flex;
      flex-direction: column;
      gap: 0.35rem;
    }
    svg { fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
    .brand { display: flex; align-items: center; gap: 0.45rem; padding: 0.1rem 0.15rem 0.7rem; }
    .brand-mark {
      display: grid;
      place-items: center;
      flex: 0 0 auto;
      width: 2.15rem;
      height: 2.15rem;
      border-radius: 0.65rem;
      background: #16352f;
      color: #5dbea6;
    }
    .brand-mark svg { width: 1.25rem; height: 1.25rem; }
    .brand-copy { display: grid; min-width: 0; flex: 1; line-height: 1.2; }
    .who strong,
    .who small { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .brand-copy strong { font-size: 0.84rem; line-height: 1.15; }
    .brand-copy small { color: #5dbea6; font-size: 0.7rem; }
    .icon-btn {
      display: grid;
      place-items: center;
      flex: 0 0 auto;
      width: 2rem;
      height: 2rem;
      margin-left: auto;
      border: 0;
      border-radius: 0.5rem;
      background: transparent;
      color: #c5d0dc;
      padding: 0;
      cursor: pointer;
    }
    .icon-btn svg { width: 1.15rem; height: 1.15rem; }
    .scroll { flex: 1; min-height: 0; overflow: auto; }
    .kicker {
      margin: 0.8rem 0.45rem 0.28rem;
      color: #8b97a6;
      font-size: 0.68rem;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
    ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 0.15rem; }
    .row, .children a {
      display: flex;
      align-items: center;
      gap: 0.65rem;
      width: 100%;
      min-height: 2.5rem;
      box-sizing: border-box;
      border: 0;
      border-radius: 0.7rem;
      background: transparent;
      color: #d5dee8;
      text-align: left;
      text-decoration: none;
      padding: 0.35rem 0.7rem;
      font: inherit;
      font-size: 0.92rem;
      cursor: pointer;
    }
    .icon { width: 1.15rem; height: 1.15rem; flex: 0 0 auto; }
    .chevron { width: 1rem; height: 1rem; margin-left: auto; color: #9aa8b6; }
    .chevron.open { transform: rotate(90deg); }
    .dot {
      margin-left: auto;
      width: 0.4rem;
      height: 0.4rem;
      border-radius: 50%;
      background: currentColor;
    }
    .children {
      margin: 0.1rem 0 0.35rem 1.15rem;
      padding: 0.05rem 0 0.05rem 0.35rem;
      border-left: 1px solid rgb(255 255 255 / 14%);
    }
    .children a { min-height: 2.15rem; padding-left: 0.7rem; font-size: 0.9rem; color: #d5dee8; }
    .row.active, .children a.active { background: #449084; color: #fff; }
    .row.branch { color: #e7fff8; }
    .row:hover, .children a:hover, .icon-btn:hover { background: #2a3441; }
    .row.active:hover, .children a.active:hover { background: #3c8478; }
    .row:focus-visible, .children a:focus-visible, .icon-btn:focus-visible {
      outline: 2px solid #9ee6d4;
      outline-offset: 2px;
    }
    .footer {
      margin-top: auto;
      display: flex;
      align-items: center;
      gap: 0.5rem;
      background: #2a3441;
      border-radius: 0.85rem;
      padding: 0.5rem 0.4rem 0.5rem 0.55rem;
    }
    .avatar {
      position: relative;
      display: grid;
      place-items: center;
      flex: 0 0 auto;
      width: 2.3rem;
      height: 2.3rem;
      border-radius: 50%;
      background: #1a3f38;
      color: #d7fff4;
      font-size: 0.7rem;
      font-weight: 700;
    }
    .presence {
      position: absolute;
      right: -1px;
      bottom: -1px;
      width: 0.55rem;
      height: 0.55rem;
      border-radius: 50%;
      background: #3dce7a;
      box-shadow: 0 0 0 2px #2a3441;
    }
    .who { display: grid; min-width: 0; flex: 1; line-height: 1.2; }
    .who strong { font-size: 0.86rem; }
    .who small { color: #9aa8b6; font-size: 0.72rem; }
    .footer .icon-btn { background: #24303c; border-radius: 0.55rem; }
    .collapsed { align-items: center; padding-inline: 0.4rem; }
    .collapsed .brand, .collapsed .footer { flex-direction: column; width: 100%; }
    .collapsed .icon-btn { margin-left: 0; }
    .collapsed .row { width: 2.55rem; min-height: 2.55rem; justify-content: center; padding: 0; }
  `,
})
export class SidebarNavComponent {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  readonly collapsed = input(false);
  readonly collapsible = input(true);
  readonly organizationName = input<string | null>(null);
  readonly navigated = output<void>();
  readonly collapseChange = output<boolean>();
  readonly signOut = output<void>();

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
  protected readonly sections = computed(() => groupNav(this.items()));
  protected readonly userName = computed(
    () => this.auth.profile()?.full_name || this.auth.user()?.email || '',
  );
  protected readonly roleName = computed(() => {
    const role = this.auth.user()?.role;
    return role ? roleLabel(role) : '';
  });
  protected readonly initials = computed(() => initials(this.userName() || 'Panel'));
  protected readonly sessionActive = computed(() => this.auth.profile()?.status !== 'inactive');
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

  protected displayLabel(item: NavItem): string {
    return item.id === 'cms' ? 'CMS Turístico' : item.label;
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

  /** A collapsed group has no room for its children, so open the menu on that group. */
  protected openFromRail(id: string): void {
    this.expanded.update((current) => {
      const next = new Set(current);
      next.add(id);
      return next;
    });
    this.collapseChange.emit(false);
  }
}

function groupNav(items: readonly NavItem[]): { label: string; items: NavItem[] }[] {
  const byId = new Map(items.map((item) => [item.id, item]));
  const used = new Set<string>();
  const sections = SECTIONS.map((section) => {
    const grouped = section.ids.flatMap((id) => {
      const item = byId.get(id);
      if (!item) {
        return [];
      }
      used.add(id);
      return [item];
    });
    return { label: section.label, items: grouped };
  }).filter((section) => section.items.length > 0);
  const rest = items.filter((item) => !used.has(item.id));
  if (rest.length > 0) {
    sections.push({ label: 'Más', items: rest });
  }
  return sections;
}

function initials(value: string): string {
  const parts = value.trim().split(/\s+/).filter(Boolean);
  const letters = parts.slice(0, 2).map((part) => part.charAt(0).toUpperCase());
  return letters.join('') || 'P';
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
