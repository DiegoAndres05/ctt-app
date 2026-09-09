import { TestBed } from '@angular/core/testing';
import { HttpRequest, type HttpEvent, type HttpHandlerFn } from '@angular/common/http';
import { firstValueFrom, of } from 'rxjs';
import {
  SESSION_ABSOLUTE_LIMIT_MS,
  SESSION_INACTIVITY_LIMIT_MS,
  SessionActivityStore,
  sessionInterceptor,
} from './session.interceptor';

const HOUR = 60 * 60 * 1000;
const ANCHOR = Date.parse('2026-09-08T08:00:00.000Z');

describe('session limits (FR-001)', () => {
  let store: SessionActivityStore;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    store = TestBed.inject(SessionActivityStore);
  });

  it('leaves an untracked session alone', () => {
    expect(store.check(ANCHOR + 100 * HOUR)).toBe('active');
  });

  it('expires a session after 8 hours without activity', () => {
    store.track(ANCHOR);

    expect(store.check(ANCHOR + SESSION_INACTIVITY_LIMIT_MS - 1)).toBe('active');
    expect(store.check(ANCHOR + SESSION_INACTIVITY_LIMIT_MS)).toBe('inactivity');
  });

  it('keeps a session alive while the user keeps working', () => {
    store.track(ANCHOR);

    for (let elapsed = HOUR; elapsed <= 20 * HOUR; elapsed += HOUR) {
      store.registerActivity(ANCHOR + elapsed);
      expect(store.check(ANCHOR + elapsed)).toBe('active');
    }
  });

  it('expires a continuously used session at the 24 hour ceiling', () => {
    store.track(ANCHOR);
    store.registerActivity(ANCHOR + SESSION_ABSOLUTE_LIMIT_MS - 1);

    expect(store.check(ANCHOR + SESSION_ABSOLUTE_LIMIT_MS - 1)).toBe('active');
    expect(store.check(ANCHOR + SESSION_ABSOLUTE_LIMIT_MS)).toBe('absolute');
  });

  it('reports the absolute limit in preference to inactivity', () => {
    store.track(ANCHOR);

    expect(store.check(ANCHOR + SESSION_ABSOLUTE_LIMIT_MS + HOUR)).toBe('absolute');
  });

  it('never revives an expired session', () => {
    store.track(ANCHOR);
    store.check(ANCHOR + SESSION_INACTIVITY_LIMIT_MS);

    store.registerActivity(ANCHOR + SESSION_INACTIVITY_LIMIT_MS + 1);

    expect(store.check(ANCHOR + SESSION_INACTIVITY_LIMIT_MS + 1)).toBe('inactivity');
  });

  it('does not restart the inactivity clock when the access token is refreshed', () => {
    store.track(ANCHOR);
    store.registerActivity(ANCHOR + HOUR);

    // A refresh reports the same server-issued session anchor.
    store.track(ANCHOR);

    expect(store.check(ANCHOR + HOUR + SESSION_INACTIVITY_LIMIT_MS)).toBe('inactivity');
  });

  it('restarts tracking for a genuinely new session', () => {
    store.track(ANCHOR);
    store.check(ANCHOR + SESSION_ABSOLUTE_LIMIT_MS);

    store.track(ANCHOR + SESSION_ABSOLUTE_LIMIT_MS);

    expect(store.check(ANCHOR + SESSION_ABSOLUTE_LIMIT_MS)).toBe('active');
  });

  it('resumes the inactivity clock from the activity recorded before a reload', () => {
    store.track(ANCHOR, ANCHOR + 3 * HOUR);

    expect(store.check(ANCHOR + 3 * HOUR + SESSION_INACTIVITY_LIMIT_MS - 1)).toBe('active');
    expect(store.check(ANCHOR + 3 * HOUR + SESSION_INACTIVITY_LIMIT_MS)).toBe('inactivity');
  });

  it('ignores stored activity that predates the session', () => {
    store.track(ANCHOR, ANCHOR - 10 * HOUR);

    expect(store.check(ANCHOR + SESSION_INACTIVITY_LIMIT_MS - 1)).toBe('active');
  });

  it('forgets everything once the session is cleared', () => {
    store.track(ANCHOR);
    store.check(ANCHOR + SESSION_ABSOLUTE_LIMIT_MS);

    store.clear();

    expect(store.expiry()).toBe('active');
    expect(store.isTracking()).toBe(false);
  });

  it('evaluates the session clocks well under the 500ms budget (SC-003)', () => {
    store.track(ANCHOR);
    const started = performance.now();
    for (let i = 0; i < 10_000; i++) {
      store.check(ANCHOR + 1000);
    }
    expect(performance.now() - started).toBeLessThan(500);
  });
});

describe('sessionInterceptor', () => {
  let store: SessionActivityStore;
  const request = new HttpRequest('GET', '/api/example');
  const next: HttpHandlerFn = (handled) => of({ type: 0, request: handled } as HttpEvent<unknown>);

  beforeEach(() => {
    TestBed.configureTestingModule({});
    store = TestBed.inject(SessionActivityStore);
  });

  it('forwards a request from a live session and counts it as activity', async () => {
    store.track(Date.now());

    await TestBed.runInInjectionContext(async () => {
      await firstValueFrom(sessionInterceptor(request, next));
    });

    expect(store.expiry()).toBe('active');
    expect(store.lastActivityAt()).not.toBeNull();
  });

  it('refuses a request once the session has expired', async () => {
    store.track(Date.now() - SESSION_ABSOLUTE_LIMIT_MS);

    await TestBed.runInInjectionContext(async () => {
      await expect(firstValueFrom(sessionInterceptor(request, next))).rejects.toMatchObject({
        code: 'SESSION_EXPIRED',
      });
    });
  });
});
