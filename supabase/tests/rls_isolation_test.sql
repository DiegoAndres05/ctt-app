-- rls_isolation_test.sql
-- Multi-tenant isolation, required by SC-002 (0% cross-organization data leakage) and
-- User Story 2 acceptance scenarios 1 and 2.
--
-- Two agencies are created, then every reachable operation is attempted from a session
-- belonging to the first one against data belonging to the second. Nothing here relies on
-- application code: the only thing under test is what the database itself allows a session
-- holding a given set of JWT claims to see and change.
--
-- On "404 or empty" (T031): the database layer can only answer "empty", and that is what is
-- asserted below. The 404 is PostgREST's rendering of an empty result when the client asks for
-- a single object (`Accept: application/vnd.pgrst.object+json`); a plain collection request
-- for a foreign id returns 200 with an empty array. Either way the row never leaves the
-- database, which is the property SC-002 is about.
--
-- Run with: supabase/tests/run-sql-tests.sh supabase/tests/rls_isolation_test.sql
-- The suite rolls back, so it leaves the database exactly as it found it.

\set ON_ERROR_STOP on

BEGIN;

\set alpha_org_id  11111111-1111-4000-a000-000000000001
\set beta_org_id   22222222-2222-4000-a000-000000000002
\set alpha_admin_id 11111111-1111-4000-b000-000000000001
\set alpha_agent_id 11111111-1111-4000-b000-000000000002
\set beta_admin_id  22222222-2222-4000-b000-000000000001
\set beta_agent_id  22222222-2222-4000-b000-000000000002
\set orphan_user_id 33333333-3333-4000-b000-000000000001

-- ===========================================================================
-- Fixtures: two independent agencies
-- ===========================================================================

CREATE OR REPLACE FUNCTION pg_temp.add_collaborator(
  p_user_id uuid,
  p_organization_id uuid,
  p_email text,
  p_full_name text,
  p_role public.app_role
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000', p_user_id, 'authenticated', 'authenticated',
          p_email, now(), now());

  INSERT INTO public.user_profiles (
    id, organization_id, full_name, email, role, status, must_change_password
  )
  VALUES (p_user_id, p_organization_id, p_full_name, p_email, p_role, 'active', false);
END;
$$;

-- Impersonates a session by populating the claims GUC PostgREST fills from a verified token.
-- The application role travels in `app_role` (docs/adr/0002-jwt-app-role-claim.md); `role`
-- keeps the value Supabase Auth issues.
CREATE OR REPLACE FUNCTION pg_temp.act_as(
  p_user_id uuid,
  p_organization_id uuid,
  p_app_role text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_strip_nulls(jsonb_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'app_role', p_app_role,
      'organization_id', p_organization_id::text
    ))::text,
    true
  );
END;
$$;

INSERT INTO public.organizations (id, name, slug, status)
VALUES
  (:'alpha_org_id'::uuid, 'Agencia Alpha', 'agencia-alpha', 'active'),
  (:'beta_org_id'::uuid, 'Agencia Beta', 'agencia-beta', 'active');

SELECT pg_temp.add_collaborator(
  :'alpha_admin_id'::uuid, :'alpha_org_id'::uuid,
  'admin-alpha@test.invalid', 'Admin Alpha', 'admin'
);
SELECT pg_temp.add_collaborator(
  :'alpha_agent_id'::uuid, :'alpha_org_id'::uuid,
  'agente-alpha@test.invalid', 'Agente Alpha', 'agent'
);
SELECT pg_temp.add_collaborator(
  :'beta_admin_id'::uuid, :'beta_org_id'::uuid,
  'admin-beta@test.invalid', 'Admin Beta', 'admin'
);
SELECT pg_temp.add_collaborator(
  :'beta_agent_id'::uuid, :'beta_org_id'::uuid,
  'agente-beta@test.invalid', 'Agente Beta', 'agent'
);

-- Creating the agencies and their collaborators already produced audit events on both sides,
-- so the audit assertions below have something to leak if isolation were broken.
SELECT tests.assert_true(
  format(
    'SELECT count(*) > 0 FROM audit.audit_events WHERE organization_id = %L',
    :'beta_org_id'
  ),
  'fixture: Beta owns audit events that Alpha must never see'
);

-- ===========================================================================
-- 1. A session of Alpha reads only Alpha (US2 scenario 1)
-- ===========================================================================

\echo '--- Alpha reads only Alpha ---'

SELECT pg_temp.act_as(:'alpha_admin_id'::uuid, :'alpha_org_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  format(
    'SELECT array_agg(id) = ARRAY[%L::uuid] FROM public.organizations',
    :'alpha_org_id'
  ),
  'organizations: an Alpha admin lists only its own agency'
);

SELECT tests.assert_true(
  format(
    'SELECT bool_and(organization_id = %L) AND count(*) = 2 FROM public.user_profiles',
    :'alpha_org_id'
  ),
  'user_profiles: an Alpha admin lists only Alpha collaborators'
);

SELECT tests.assert_true(
  format(
    'SELECT bool_and(organization_id = %L) FROM audit.audit_events',
    :'alpha_org_id'
  ),
  'audit_events: an Alpha admin reads only Alpha history'
);

-- ===========================================================================
-- 2. Direct access by foreign id yields nothing (US2 scenario 2, T031)
-- ===========================================================================

\echo '--- direct access by foreign id ---'

SELECT tests.assert_true(
  format('SELECT count(*) = 0 FROM public.organizations WHERE id = %L', :'beta_org_id'),
  'organizations: fetching Beta by its own id returns no row'
);

SELECT tests.assert_true(
  format('SELECT count(*) = 0 FROM public.user_profiles WHERE id = %L', :'beta_admin_id'),
  'user_profiles: fetching a Beta collaborator by id returns no row'
);

SELECT tests.assert_true(
  format(
    'SELECT count(*) = 0 FROM public.user_profiles WHERE email = %L',
    'admin-beta@test.invalid'
  ),
  'user_profiles: a Beta collaborator cannot be found by email either'
);

SELECT tests.assert_true(
  format(
    'SELECT count(*) = 0 FROM audit.audit_events WHERE organization_id = %L',
    :'beta_org_id'
  ),
  'audit_events: filtering explicitly by the Beta tenant returns no row'
);

-- A foreign id is indistinguishable from one that was never issued, so the response cannot be
-- used to probe which identifiers exist.
SELECT tests.assert_true(
  '(SELECT count(*) FROM public.user_profiles WHERE id = '
  || quote_literal(:'beta_admin_id') || '::uuid)
   = (SELECT count(*) FROM public.user_profiles WHERE id = gen_random_uuid())',
  'a foreign id and a non-existent id are indistinguishable'
);

-- ===========================================================================
-- 3. Writes cannot cross the tenant boundary
-- ===========================================================================

\echo '--- cross-tenant writes ---'

-- A policy whose USING clause matches no row makes the statement a no-op instead of an error,
-- so nothing of Beta's is touched and the response discloses nothing about it either.
UPDATE public.organizations SET name = 'Owned by Alpha' WHERE id = :'beta_org_id'::uuid;
SELECT tests.assert_equals(
  :ROW_COUNT, 0,
  'organizations: an Alpha admin cannot rename Beta'
);

UPDATE public.user_profiles SET role = 'agent' WHERE id = :'beta_admin_id'::uuid;
SELECT tests.assert_equals(
  :ROW_COUNT, 0,
  'user_profiles: an Alpha admin cannot demote a Beta administrator'
);

-- Neither table carries a DELETE policy, so deletion reaches nothing in any tenant and must
-- go through a SECURITY DEFINER routine instead.
DELETE FROM public.user_profiles WHERE id = :'beta_agent_id'::uuid;
SELECT tests.assert_equals(
  :ROW_COUNT, 0,
  'user_profiles: DELETE reaches no collaborator of another tenant'
);

DELETE FROM public.user_profiles WHERE id = :'alpha_agent_id'::uuid;
SELECT tests.assert_equals(
  :ROW_COUNT, 0,
  'user_profiles: DELETE reaches no collaborator of the caller''s own tenant either'
);

DELETE FROM public.organizations WHERE id = :'alpha_org_id'::uuid;
SELECT tests.assert_equals(
  :ROW_COUNT, 0,
  'organizations: DELETE reaches no agency at all'
);

-- WITH CHECK pins the tenant on insert, so an admin cannot plant a collaborator elsewhere.
SELECT tests.assert_raises(
  format(
    'INSERT INTO public.user_profiles (id, organization_id, full_name, email, role)
     VALUES (%L, %L, ''Intruso'', ''intruso@test.invalid'', ''admin'')',
    :'orphan_user_id', :'beta_org_id'
  ),
  'row-level security',
  'user_profiles: an Alpha admin cannot create a collaborator inside Beta'
);

-- Nor move one of their own collaborators across the boundary.
SELECT tests.assert_raises(
  format(
    'UPDATE public.user_profiles SET organization_id = %L WHERE id = %L',
    :'beta_org_id', :'alpha_agent_id'
  ),
  'row-level security',
  'user_profiles: an Alpha admin cannot move a collaborator into Beta'
);

SELECT tests.assert_raises(
  format(
    'INSERT INTO audit.audit_events (organization_id, event_type, result)
     VALUES (%L, ''login_success'', ''success'')',
    :'beta_org_id'
  ),
  'permission denied',
  'audit_events: an authenticated session cannot forge history for any tenant'
);

RESET ROLE;

-- ===========================================================================
-- 4. Role scope within a tenant
-- ===========================================================================

\echo '--- role scope inside a tenant ---'

SELECT pg_temp.act_as(:'alpha_agent_id'::uuid, :'alpha_org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  'SELECT count(*) = 0 FROM audit.audit_events',
  'audit_events: a non-admin collaborator reads no history, not even its own tenant''s'
);

SELECT tests.assert_true(
  format(
    'SELECT bool_and(organization_id = %L) AND count(*) = 2 FROM public.user_profiles',
    :'alpha_org_id'
  ),
  'user_profiles: a non-admin still sees its own agency roster'
);

UPDATE public.organizations SET name = 'Renombrada por un agente'
WHERE id = :'alpha_org_id'::uuid;
SELECT tests.assert_equals(
  :ROW_COUNT, 0,
  'organizations: a non-admin cannot modify its own agency'
);

RESET ROLE;

-- ===========================================================================
-- 5. Sessions without a tenant claim (ADR-0002 follow-up)
-- ===========================================================================

\echo '--- sessions with no tenant claim ---'

-- What a deactivated or profile-less user receives from the auth hook: a valid token that
-- carries no organization_id. Every policy compares against NULL, which is not TRUE.
SELECT pg_temp.act_as(:'alpha_admin_id'::uuid, NULL, 'admin');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  'SELECT count(*) = 0 FROM public.organizations',
  'organizations: a session with no organization_id claim reads nothing'
);

SELECT tests.assert_true(
  'SELECT count(*) = 0 FROM public.user_profiles',
  'user_profiles: a session with no organization_id claim reads nothing'
);

SELECT tests.assert_true(
  'SELECT count(*) = 0 FROM audit.audit_events',
  'audit_events: a session with no organization_id claim reads nothing'
);

RESET ROLE;

-- An unauthenticated caller matches no policy at all.
SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  'SELECT count(*) FROM public.organizations',
  'permission denied',
  'organizations: anon holds no privilege on the table'
);

SELECT tests.assert_raises(
  'SELECT count(*) FROM public.user_profiles',
  'permission denied',
  'user_profiles: anon holds no privilege on the table'
);

SELECT tests.assert_raises(
  'SELECT count(*) FROM audit.audit_events',
  'permission denied',
  'audit_events: anon holds no privilege on the table'
);

RESET ROLE;

-- ===========================================================================
-- 6. Nothing above disturbed the other tenant
-- ===========================================================================

\echo '--- Beta is intact ---'

SELECT tests.assert_true(
  format(
    'SELECT name = ''Agencia Beta'' FROM public.organizations WHERE id = %L',
    :'beta_org_id'
  ),
  'Beta''s name is unchanged after every attempt'
);

SELECT tests.assert_true(
  format(
    'SELECT count(*) = 2 AND bool_and(role IN (''admin'', ''agent''))
       FROM public.user_profiles WHERE organization_id = %L',
    :'beta_org_id'
  ),
  'Beta''s roster is unchanged after every attempt'
);

\echo '--- rls_isolation_test: all assertions passed ---'

ROLLBACK;
