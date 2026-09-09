-- us1_auth_functions_test.sql
-- Verifies the User Story 1 security controls added in migration 008:
--   1. a collaborator can no longer clear must_change_password by updating their own row;
--   2. change_password only rotates a credential after proving the current one;
--   3. five consecutive failed verifications lock the account for 15 minutes, and a live lock
--      rejects even a correct password.
--
-- Covers quickstart.md scenarios 5 and 6.
--
-- Run with: supabase/tests/run-sql-tests.sh supabase/tests/us1_auth_functions_test.sql
-- The suite rolls back, so it leaves the database exactly as it found it.

\set ON_ERROR_STOP on

BEGIN;

-- Seed fixtures (supabase/seed.sql). The agent still holds a temporary password, which is the
-- state the mandatory-change flow is about.
\set admin_id 00000000-0000-4000-b000-000000000001
\set agent_id 00000000-0000-4000-b000-000000000003
\set own_session_id 00000000-0000-4000-c000-000000000001
\set other_session_id 00000000-0000-4000-c000-000000000002

CREATE OR REPLACE FUNCTION pg_temp.act_as(
  p_user_id uuid,
  p_role text,
  p_session_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Same GUC PostgREST populates from the verified token, holding the same claims the auth
  -- hook injects (migration 006).
  --
  -- Must be called before switching into `authenticated`: it reads the profile to resolve the
  -- tenant, and under that role RLS would already be hiding the row.
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'app_role', p_role,
      'organization_id',
        (SELECT organization_id::text FROM public.user_profiles WHERE id = p_user_id),
      'session_id', coalesce(p_session_id::text, gen_random_uuid()::text)
    )::text,
    true
  );
END;
$$;

-- ===========================================================================
-- 1. must_change_password is no longer self-writable
-- ===========================================================================

\echo '--- must_change_password self-update scope ---'

-- Give the agent a live lock so that the attempt to clear it below is a real change rather
-- than a no-op the trigger would have no reason to reject.
UPDATE public.user_profiles
SET locked_until = now() + interval '15 minutes',
    failed_login_attempts = 5
WHERE id = :'agent_id'::uuid;

SELECT pg_temp.act_as(:'agent_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  format('SELECT must_change_password FROM public.user_profiles WHERE id = %L', :'agent_id'),
  'fixture: the agent starts with must_change_password = true'
);

SELECT tests.assert_raises(
  format('UPDATE public.user_profiles SET must_change_password = false WHERE id = %L', :'agent_id'),
  'A collaborator may only update last_activity_at on their own profile.',
  'a collaborator cannot clear must_change_password on their own profile'
);

SELECT tests.assert_raises(
  format('UPDATE public.user_profiles SET role = ''admin'' WHERE id = %L', :'agent_id'),
  'A collaborator may only update last_activity_at on their own profile.',
  'a collaborator cannot promote themselves to admin'
);

SELECT tests.assert_raises(
  format(
    'UPDATE public.user_profiles SET locked_until = NULL, failed_login_attempts = 0 WHERE id = %L',
    :'agent_id'
  ),
  'A collaborator may only update last_activity_at on their own profile.',
  'a collaborator cannot reset their own lockout counters'
);

-- The one column the session interceptor (T024) needs must still be writable.
UPDATE public.user_profiles SET last_activity_at = now() WHERE id = :'agent_id'::uuid;

SELECT tests.assert_true(
  format(
    'SELECT last_activity_at IS NOT NULL FROM public.user_profiles WHERE id = %L',
    :'agent_id'
  ),
  'a collaborator can still record their own last_activity_at'
);

SELECT tests.assert_true(
  format('SELECT must_change_password FROM public.user_profiles WHERE id = %L', :'agent_id'),
  'must_change_password survived every rejected attempt'
);

RESET ROLE;

-- ===========================================================================
-- 2. change_password
-- ===========================================================================

\echo '--- change_password ---'

-- Two sessions for the agent: the caller's own, and another that must not survive the rotation.
INSERT INTO auth.sessions (id, user_id, created_at, updated_at)
VALUES
  (:'own_session_id'::uuid, :'agent_id'::uuid, now(), now()),
  (:'other_session_id'::uuid, :'agent_id'::uuid, now(), now());

SELECT pg_temp.act_as(:'agent_id'::uuid, 'agent', :'own_session_id'::uuid);
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  'SELECT public.change_password(''NotThePassword'', ''BrandNewPass1!'')',
  'INVALID_CURRENT_PASSWORD',
  'change_password rejects a wrong current password'
);

SELECT tests.assert_raises(
  'SELECT public.change_password(''DemoPass123!'', ''short1!'')',
  'WEAK_PASSWORD',
  'change_password rejects a new password under 8 characters'
);

SELECT tests.assert_raises(
  format('SELECT public.change_password(''DemoPass123!'', %L)', repeat('a', 73)),
  'WEAK_PASSWORD',
  'change_password rejects a new password longer than bcrypt can hash'
);

SELECT tests.assert_raises(
  'SELECT public.change_password(''DemoPass123!'', ''DemoPass123!'')',
  'PASSWORD_UNCHANGED',
  'change_password refuses to re-use the temporary password'
);

SELECT tests.assert_true(
  format('SELECT must_change_password FROM public.user_profiles WHERE id = %L', :'agent_id'),
  'no rejected rotation cleared the mandatory-change flag'
);

SELECT tests.assert_true(
  'SELECT public.change_password(''DemoPass123!'', ''BrandNewPass1!'')
     = jsonb_build_object(''must_change_password'', false)',
  'change_password succeeds with the correct current password'
);

RESET ROLE;

SELECT tests.assert_true(
  format('SELECT NOT must_change_password FROM public.user_profiles WHERE id = %L', :'agent_id'),
  'the mandatory-change flag is cleared server-side by change_password'
);

SELECT tests.assert_true(
  format(
    'SELECT encrypted_password = extensions.crypt(''BrandNewPass1!'', encrypted_password)
       FROM auth.users WHERE id = %L',
    :'agent_id'
  ),
  'auth.users now stores a bcrypt hash of the new password'
);

SELECT tests.assert_true(
  format(
    'SELECT encrypted_password <> extensions.crypt(''DemoPass123!'', encrypted_password)
       FROM auth.users WHERE id = %L',
    :'agent_id'
  ),
  'the temporary password no longer authenticates'
);

SELECT tests.assert_true(
  format(
    'SELECT array_agg(id) = ARRAY[%L::uuid] FROM auth.sessions WHERE user_id = %L',
    :'own_session_id', :'agent_id'
  ),
  'the rotation kept the calling session and dropped the other one'
);

SELECT tests.assert_true(
  format(
    'SELECT count(*) = 1 FROM audit.audit_events
       WHERE actor_id = %L AND event_type = ''password_changed'' AND result = ''success''',
    :'agent_id'
  ),
  'exactly one password_changed event was recorded'
);

-- ===========================================================================
-- 3. Failed-login accounting and lockout
-- ===========================================================================

\echo '--- failed-login lockout ---'

-- Supabase Auth calls the hook outside any PostgREST request, so there are no request claims.
-- Clearing them keeps the audit attribution faithful: `account_locked` and `account_unlocked`
-- come from the migration 007 trigger, which has no actor to attribute them to and therefore
-- records them as system events.
SELECT set_config('request.jwt.claims', '', true);

-- The hook is invoked by Supabase Auth, never by a browser session.
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format(
    'SELECT public.password_verification_hook(
       jsonb_build_object(''user_id'', %L, ''valid'', false))',
    :'admin_id'
  ),
  'permission denied',
  'an authenticated session cannot invoke the password verification hook'
);

RESET ROLE;

SET LOCAL ROLE supabase_auth_admin;

-- Four wrong passwords: counted, still allowed to keep trying.
SELECT public.password_verification_hook(
         jsonb_build_object('user_id', :'admin_id', 'valid', false)
       )
FROM generate_series(1, 4);

RESET ROLE;

SELECT tests.assert_true(
  format(
    'SELECT failed_login_attempts = 4 AND locked_until IS NULL
       FROM public.user_profiles WHERE id = %L',
    :'admin_id'
  ),
  'four failed verifications are counted without locking the account'
);

SET LOCAL ROLE supabase_auth_admin;

SELECT tests.assert_true(
  format(
    'SELECT public.password_verification_hook(
       jsonb_build_object(''user_id'', %L, ''valid'', false)) ->> ''decision'' = ''reject''',
    :'admin_id'
  ),
  'the fifth failed verification is rejected'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    'SELECT failed_login_attempts = 5
       AND locked_until BETWEEN now() + interval ''14 minutes'' AND now() + interval ''15 minutes''
       FROM public.user_profiles WHERE id = %L',
    :'admin_id'
  ),
  'the account is locked for 15 minutes after the fifth attempt'
);

SELECT tests.assert_true(
  format(
    'SELECT count(*) = 5 FROM audit.audit_events
       WHERE actor_id = %L AND event_type = ''login_failure''',
    :'admin_id'
  ),
  'every failed verification produced a login_failure event'
);

SELECT tests.assert_true(
  format(
    'SELECT count(*) = 1 FROM audit.audit_events
       WHERE resource_id = %L AND actor_id IS NULL AND event_type = ''account_locked''',
    :'admin_id'
  ),
  'the lock produced exactly one account_locked event, recorded as a system event'
);

SET LOCAL ROLE supabase_auth_admin;

SELECT tests.assert_true(
  format(
    'SELECT public.password_verification_hook(
       jsonb_build_object(''user_id'', %L, ''valid'', true)) ->> ''decision'' = ''reject''',
    :'admin_id'
  ),
  'a correct password is rejected while the lock is live'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    'SELECT count(*) = 0 FROM audit.audit_events
       WHERE actor_id = %L AND event_type = ''login_success''',
    :'admin_id'
  ),
  'no login_success was recorded while the account was locked'
);

-- Move the lock into the past to observe expiry without waiting 15 minutes. Done as the
-- migration owner because no application role may write this column.
--
-- Back-dating the column is itself a locked_until change, so the migration 007 trigger records
-- an `account_unlocked` for it. The marker below separates that fixture artifact from the event
-- the hook is expected to produce.
UPDATE public.user_profiles
SET locked_until = now() - interval '1 minute'
WHERE id = :'admin_id'::uuid;

SELECT coalesce(max(id), 0) AS audit_marker FROM audit.audit_events \gset

SET LOCAL ROLE supabase_auth_admin;

SELECT tests.assert_true(
  format(
    'SELECT public.password_verification_hook(
       jsonb_build_object(''user_id'', %L, ''valid'', true)) ->> ''decision'' = ''continue''',
    :'admin_id'
  ),
  'once the lock expires the correct password is accepted again'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    'SELECT failed_login_attempts = 0 AND locked_until IS NULL AND last_activity_at IS NOT NULL
       FROM public.user_profiles WHERE id = %L',
    :'admin_id'
  ),
  'a successful verification resets the counters and stamps activity'
);

SELECT tests.assert_true(
  format(
    'SELECT count(*) = 1 FROM audit.audit_events
       WHERE id > %s AND resource_id = %L AND actor_id IS NULL
         AND event_type = ''account_unlocked''',
    :'audit_marker', :'admin_id'
  ),
  'clearing the expired lock produced an account_unlocked event'
);

SELECT tests.assert_true(
  format(
    'SELECT count(*) = 1 FROM audit.audit_events
       WHERE actor_id = %L AND event_type = ''login_success''',
    :'admin_id'
  ),
  'the accepted verification produced a login_success event'
);

-- A deactivated collaborator is turned away even with the right password, and only then.
UPDATE public.user_profiles SET status = 'inactive' WHERE id = :'admin_id'::uuid;

SET LOCAL ROLE supabase_auth_admin;

SELECT tests.assert_true(
  format(
    'SELECT public.password_verification_hook(
       jsonb_build_object(''user_id'', %L, ''valid'', true)) ->> ''message''
     LIKE ''ACCOUNT_INACTIVE%%''',
    :'admin_id'
  ),
  'a deactivated collaborator is rejected after proving their password'
);

SELECT tests.assert_true(
  format(
    'SELECT public.password_verification_hook(
       jsonb_build_object(''user_id'', %L, ''valid'', false)) ->> ''message'' IS NULL',
    :'admin_id'
  ),
  'a wrong password against a deactivated account reveals nothing about its status'
);

RESET ROLE;

-- ===========================================================================
-- 4. Session termination auditing
-- ===========================================================================

\echo '--- record_session_end ---'

SELECT pg_temp.act_as(:'agent_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.record_session_end('logout');
SELECT public.record_session_end('session_expired');

SELECT tests.assert_raises(
  'SELECT public.record_session_end(''role_changed'')',
  'VALIDATION_ERROR',
  'record_session_end only accepts the two session-termination reasons'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    'SELECT count(*) = 2 FROM audit.audit_events
       WHERE actor_id = %L AND event_type IN (''logout'', ''session_expired'')',
    :'agent_id'
  ),
  'logout and session_expired are recorded for the calling session'
);

\echo '--- us1_auth_functions_test: all assertions passed ---'

ROLLBACK;
