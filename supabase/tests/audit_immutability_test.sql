-- audit_immutability_test.sql
-- Verifies the User Story 4 / FR-005 immutability of audit.audit_events: UPDATE, DELETE and
-- TRUNCATE are rejected for every role, including the table owner. Required by T042.
--
-- The expected message is the one raised by audit.reject_audit_mutation (migration 007) and
-- quoted in specs/001-auth-tenant-access/quickstart.md scenario 7.
--
-- Run with: supabase/tests/run-sql-tests.sh supabase/tests/audit_immutability_test.sql
-- The suite rolls back, so it leaves the database exactly as it found it.

\set ON_ERROR_STOP on

BEGIN;

\set admin_id 00000000-0000-4000-b000-000000000001
\set agent_id 00000000-0000-4000-b000-000000000003

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

-- Seed (supabase/seed.sql) writes organization_created + three user_created rows.
SELECT tests.assert_true(
  'SELECT count(*) > 0 FROM audit.audit_events',
  'fixture: the audit log already holds at least one event'
);

SELECT min(id) AS target_id FROM audit.audit_events \gset

\echo '--- immutability as table owner ---'

SELECT tests.assert_raises(
  format('UPDATE audit.audit_events SET result = ''failure'' WHERE id = %s', :'target_id'),
  'Audit logs are immutable and cannot be modified or deleted.',
  'UPDATE of an audit event is rejected even for the table owner'
);

SELECT tests.assert_raises(
  format('DELETE FROM audit.audit_events WHERE id = %s', :'target_id'),
  'Audit logs are immutable and cannot be modified or deleted.',
  'DELETE of an audit event is rejected even for the table owner'
);

SELECT tests.assert_raises(
  'TRUNCATE audit.audit_events',
  'Audit logs are immutable and cannot be modified or deleted.',
  'TRUNCATE of the audit log is rejected'
);

SELECT tests.assert_true(
  format(
    'SELECT count(*) = 1 FROM audit.audit_events WHERE id = %s AND result IS NOT DISTINCT FROM result',
    :'target_id'
  ),
  'the targeted audit row is still present after the rejected mutations'
);

\echo '--- immutability as an authenticated administrator ---'

SELECT pg_temp.act_as(:'admin_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;

-- authenticated holds SELECT only (migration 004). The privilege layer stops the write
-- before the trigger; either way history cannot change. The trigger message is asserted
-- above against the table owner, who *does* have the privilege.
SELECT tests.assert_raises(
  format('UPDATE audit.audit_events SET result = ''failure'' WHERE id = %s', :'target_id'),
  'permission denied',
  'an authenticated admin has no UPDATE privilege on audit_events'
);

SELECT tests.assert_raises(
  format('DELETE FROM audit.audit_events WHERE id = %s', :'target_id'),
  'permission denied',
  'an authenticated admin has no DELETE privilege on audit_events'
);

SELECT tests.assert_true(
  'SELECT count(*) > 0 FROM audit.audit_events',
  'an authenticated admin can still read their tenant''s audit history'
);

RESET ROLE;

\echo '--- a non-admin still cannot read or mutate ---'

SELECT pg_temp.act_as(:'agent_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT tests.assert_true(
  'SELECT count(*) = 0 FROM audit.audit_events',
  'an agent reads no audit history'
);

SELECT tests.assert_raises(
  format('UPDATE audit.audit_events SET result = ''failure'' WHERE id = %s', :'target_id'),
  'permission denied',
  'an agent has no UPDATE privilege on audit_events'
);

RESET ROLE;

ROLLBACK;
