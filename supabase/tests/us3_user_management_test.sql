-- us3_user_management_test.sql
-- Verifies the User Story 3 RPCs in migration 009: admin-only collaborator provisioning,
-- role changes and activation, tenant-scoped, with audit events emitted by the existing
-- triggers. Not required by a success criterion of its own; the functions have no other
-- automated check.
--
-- Run with: supabase/tests/run-sql-tests.sh supabase/tests/us3_user_management_test.sql
-- The suite rolls back, so it leaves the database exactly as it found it.

\set ON_ERROR_STOP on

BEGIN;

\set admin_id 00000000-0000-4000-b000-000000000001
\set operator_id 00000000-0000-4000-b000-000000000002
\set agent_id 00000000-0000-4000-b000-000000000003
\set foreign_org 22222222-2222-4000-a000-000000000002
\set foreign_user 22222222-2222-4000-b000-000000000001

CREATE OR REPLACE FUNCTION pg_temp.act_as(p_user_id uuid, p_role text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'app_role', p_role,
      'organization_id',
        (SELECT organization_id::text FROM public.user_profiles WHERE id = p_user_id)
    )::text,
    true
  );
END;
$$;

-- A second agency so cross-tenant attempts have a real target.
INSERT INTO public.organizations (id, name, slug, status)
VALUES (:'foreign_org'::uuid, 'Agencia Extranjera', 'agencia-extranjera', 'active');

INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000000', :'foreign_user'::uuid,
  'authenticated', 'authenticated', 'admin@extranjera.test', now(), now()
);

INSERT INTO public.user_profiles (
  id, organization_id, full_name, email, role, status, must_change_password
)
VALUES (
  :'foreign_user'::uuid, :'foreign_org'::uuid,
  'Admin Extranjero', 'admin@extranjera.test', 'admin', 'active', false
);

\echo '--- non-admins cannot manage users ---'

SELECT pg_temp.act_as(:'agent_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  $sql$SELECT public.create_internal_user('Invitado', 'invitado@demo-turismo.test', 'agent', 'TempPass1!')$sql$,
  'INSUFFICIENT_PERMISSIONS',
  'an agent cannot create a collaborator'
);

RESET ROLE;

SELECT pg_temp.act_as(:'operator_id'::uuid, 'operator');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  format(
    'SELECT public.update_user_role(%L::uuid, ''agent'')',
    :'agent_id'
  ),
  'INSUFFICIENT_PERMISSIONS',
  'an operator cannot change another collaborator''s role'
);

SELECT tests.assert_raises(
  format(
    'SELECT public.toggle_user_status(%L::uuid, ''inactive'')',
    :'agent_id'
  ),
  'INSUFFICIENT_PERMISSIONS',
  'an operator cannot deactivate a collaborator'
);

RESET ROLE;

\echo '--- an administrator can provision, retask and deactivate ---'

SELECT pg_temp.act_as(:'admin_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  $sql$SELECT public.create_internal_user('Otro Admin', 'otro-admin@demo-turismo.test', 'admin', 'TempPass1!')$sql$,
  'VALIDATION_ERROR',
  'create_internal_user rejects the admin role'
);

SELECT public.create_internal_user(
  'Colaborador Nuevo',
  'nuevo@demo-turismo.test',
  'operator',
  'TempPass1!'
) AS created \gset

SELECT tests.assert_true(
  format(
    $sql$SELECT role = 'operator' AND status = 'active' AND must_change_password
         FROM public.user_profiles WHERE email = 'nuevo@demo-turismo.test'$sql$
  ),
  'the new collaborator is an active operator who must change their password'
);

SELECT tests.assert_true(
  $sql$SELECT count(*) = 1 FROM audit.audit_events
       WHERE event_type = 'user_created'
         AND resource_id = (SELECT id FROM public.user_profiles WHERE email = 'nuevo@demo-turismo.test')
         AND actor_id = '00000000-0000-4000-b000-000000000001'::uuid$sql$,
  'creating a collaborator emits user_created attributed to the administrator'
);

SELECT tests.assert_raises(
  $sql$SELECT public.create_internal_user('Duplicado', 'nuevo@demo-turismo.test', 'agent', 'TempPass1!')$sql$,
  'EMAIL_ALREADY_EXISTS',
  'a duplicate email is rejected'
);

SELECT public.update_user_role(
  (SELECT id FROM public.user_profiles WHERE email = 'nuevo@demo-turismo.test'),
  'agent'
) AS role_update \gset

SELECT tests.assert_true(
  $sql$SELECT role = 'agent' FROM public.user_profiles WHERE email = 'nuevo@demo-turismo.test'$sql$,
  'update_user_role takes effect immediately'
);

SELECT tests.assert_true(
  $sql$SELECT count(*) = 1 FROM audit.audit_events
       WHERE event_type = 'role_changed'
         AND resource_id = (SELECT id FROM public.user_profiles WHERE email = 'nuevo@demo-turismo.test')
         AND metadata ->> 'to' = 'agent'$sql$,
  'changing a role emits role_changed'
);

SELECT public.toggle_user_status(
  (SELECT id FROM public.user_profiles WHERE email = 'nuevo@demo-turismo.test'),
  'inactive'
) AS status_update \gset

SELECT tests.assert_true(
  $sql$SELECT status = 'inactive' FROM public.user_profiles WHERE email = 'nuevo@demo-turismo.test'$sql$,
  'toggle_user_status deactivates the collaborator'
);

SELECT tests.assert_true(
  $sql$SELECT count(*) = 1 FROM audit.audit_events
       WHERE event_type = 'user_deactivated'
         AND resource_id = (SELECT id FROM public.user_profiles WHERE email = 'nuevo@demo-turismo.test')$sql$,
  'deactivation emits user_deactivated'
);

SELECT tests.assert_raises(
  format('SELECT public.toggle_user_status(%L::uuid, ''inactive'')', :'admin_id'),
  'VALIDATION_ERROR',
  'an administrator cannot deactivate themselves'
);

SELECT tests.assert_raises(
  format('SELECT public.update_user_role(%L::uuid, ''agent'')', :'admin_id'),
  'VALIDATION_ERROR',
  'an administrator cannot change their own role'
);

SELECT tests.assert_raises(
  format('SELECT public.update_user_role(%L::uuid, ''agent'')', :'foreign_user'),
  'VALIDATION_ERROR',
  'an administrator cannot change a collaborator of another tenant'
);

RESET ROLE;

ROLLBACK;
