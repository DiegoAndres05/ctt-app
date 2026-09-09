-- us5_register_agency_test.sql
-- Verifies the User Story 5 RPC in migration 010: atomic tenant + founding admin,
-- slug generation/collision, email uniqueness, and that anon/authenticated cannot call it.
-- Covers quickstart.md scenario 1 (the database half) and the 409 duplicate-email path.
--
-- Run with: supabase/tests/run-sql-tests.sh supabase/tests/us5_register_agency_test.sql
-- The suite rolls back, so it leaves the database exactly as it found it.

\set ON_ERROR_STOP on

BEGIN;

\set founder_id 44444444-4444-4000-b000-000000000001
\set other_id   44444444-4444-4000-b000-000000000002
\set missing_id 44444444-4444-4000-b000-000000000099
\set admin_id   00000000-0000-4000-b000-000000000001

INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000000', :'founder_id'::uuid,
  'authenticated', 'authenticated', 'admin@agencia-nueva.test', now(), now()
);

INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000000', :'other_id'::uuid,
  'authenticated', 'authenticated', 'otro@agencia-nueva.test', now(), now()
);

\echo '--- happy path: org + founding admin, slug, no forced password change ---'

SELECT public.register_agency(
  'Agencia Nueva Turismo',
  :'founder_id'::uuid,
  'Admin Nueva',
  'admin@agencia-nueva.test'
) AS registered \gset

SELECT tests.assert_true(
  $sql$SELECT name = 'Agencia Nueva Turismo'
         AND slug = 'agencia-nueva-turismo'
         AND status = 'active'
       FROM public.organizations
       WHERE slug = 'agencia-nueva-turismo'$sql$,
  'register_agency creates the organization with a URL-friendly slug'
);

SELECT tests.assert_true(
  $sql$SELECT role = 'admin'
         AND status = 'active'
         AND must_change_password = false
         AND full_name = 'Admin Nueva'
         AND email = 'admin@agencia-nueva.test'
       FROM public.user_profiles
       WHERE id = '44444444-4444-4000-b000-000000000001'::uuid$sql$,
  'the founding admin is active, role admin, and must_change_password is false'
);

SELECT tests.assert_true(
  $sql$SELECT count(*) = 1 FROM audit.audit_events
       WHERE event_type = 'organization_created'
         AND resource_id = (
           SELECT id FROM public.organizations WHERE slug = 'agencia-nueva-turismo'
         )$sql$,
  'creating the agency emits organization_created'
);

SELECT tests.assert_true(
  $sql$SELECT count(*) = 1 FROM audit.audit_events
       WHERE event_type = 'user_created'
         AND resource_id = '44444444-4444-4000-b000-000000000001'::uuid$sql$,
  'creating the founding admin emits user_created'
);

\echo '--- collisions and tenant-safety ---'

SELECT tests.assert_raises(
  $sql$SELECT public.register_agency(
         'Agencia Nueva Turismo',
         '44444444-4444-4000-b000-000000000002'::uuid,
         'Otro Admin',
         'otro@agencia-nueva.test'
       )$sql$,
  'AGENCY_SLUG_EXISTS',
  'a colliding slug is rejected'
);

SELECT tests.assert_true(
  $sql$SELECT count(*) = 0 FROM public.user_profiles
       WHERE id = '44444444-4444-4000-b000-000000000002'::uuid$sql$,
  'a rejected slug collision leaves no partial profile (atomicity)'
);

SELECT tests.assert_true(
  $sql$SELECT count(*) = 1 FROM public.organizations WHERE slug = 'agencia-nueva-turismo'$sql$,
  'a rejected slug collision does not create a second organization'
);

SELECT tests.assert_raises(
  $sql$SELECT public.register_agency(
         'Otra Agencia Distinta',
         '44444444-4444-4000-b000-000000000001'::uuid,
         'Admin Nueva',
         'admin@agencia-nueva.test'
       )$sql$,
  'EMAIL_ALREADY_EXISTS',
  'reusing an already-profiled auth user is rejected'
);

SELECT tests.assert_raises(
  $sql$SELECT public.register_agency(
         'Agencia Demo Turismo',
         '44444444-4444-4000-b000-000000000002'::uuid,
         'Otro Admin',
         'otro@agencia-nueva.test'
       )$sql$,
  'AGENCY_SLUG_EXISTS',
  'a name that slugifies to an existing tenant is rejected'
);

SELECT tests.assert_raises(
  format(
    $sql$SELECT public.register_agency(
           'Agencia Sin Usuario',
           %L::uuid,
           'Nadie',
           'nadie@agencia.test'
         )$sql$,
    :'missing_id'
  ),
  'VALIDATION_ERROR',
  'a user_id that is not in auth.users is rejected'
);

SELECT tests.assert_raises(
  $sql$SELECT public.register_agency(
         'Agencia Email Mismatch',
         '44444444-4444-4000-b000-000000000002'::uuid,
         'Otro Admin',
         'mismatch@agencia.test'
       )$sql$,
  'VALIDATION_ERROR',
  'p_email must match the auth.users row (prevents binding a foreign user_id)'
);

SELECT tests.assert_raises(
  $sql$SELECT public.register_agency(
         '!!!',
         '44444444-4444-4000-b000-000000000002'::uuid,
         'Otro Admin',
         'otro@agencia-nueva.test'
       )$sql$,
  'VALIDATION_ERROR',
  'a name that cannot produce a URL-friendly slug is rejected'
);

SELECT tests.assert_raises(
  $sql$SELECT public.register_agency(
         '',
         '44444444-4444-4000-b000-000000000002'::uuid,
         'Otro Admin',
         'otro@agencia-nueva.test'
       )$sql$,
  'VALIDATION_ERROR',
  'a blank agency name is rejected'
);

\echo '--- anon and authenticated cannot invoke the RPC ---'

SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  $sql$SELECT public.register_agency(
         'Agencia Anonima',
         '44444444-4444-4000-b000-000000000002'::uuid,
         'Anon',
         'otro@agencia-nueva.test'
       )$sql$,
  'permission denied',
  'anon cannot execute register_agency'
);

RESET ROLE;

SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', :'admin_id'::text,
    'role', 'authenticated',
    'app_role', 'admin',
    'organization_id',
      (SELECT organization_id::text FROM public.user_profiles WHERE id = :'admin_id'::uuid)
  )::text,
  true
);

SET LOCAL ROLE authenticated;

SELECT tests.assert_raises(
  $sql$SELECT public.register_agency(
         'Agencia Autenticada',
         '44444444-4444-4000-b000-000000000002'::uuid,
         'Auth',
         'otro@agencia-nueva.test'
       )$sql$,
  'permission denied',
  'authenticated cannot execute register_agency'
);

RESET ROLE;

\echo '--- service_role can invoke the RPC ---'

SET LOCAL ROLE service_role;

SELECT public.register_agency(
  'Agencia Service Role',
  :'other_id'::uuid,
  'Admin Service',
  'otro@agencia-nueva.test'
);

RESET ROLE;

SELECT tests.assert_true(
  $sql$SELECT slug = 'agencia-service-role'
         AND (SELECT role FROM public.user_profiles WHERE id = '44444444-4444-4000-b000-000000000002'::uuid) = 'admin'
       FROM public.organizations
       WHERE slug = 'agencia-service-role'$sql$,
  'service_role is the authorized caller of register_agency'
);

ROLLBACK;
