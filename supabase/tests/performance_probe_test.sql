-- performance_probe_test.sql
-- Local measurements for SC-003 / SC-004. Not a substitute for a production load test:
-- there is no GoTrue here, so "authentication" is represented by the onboarding RPC that
-- the Edge Function calls after createUser, and "session check" is measured in the Angular
-- unit suite (SessionActivityStore.check).
--
-- Run with: supabase/tests/run-sql-tests.sh
-- The suite rolls back.

\set ON_ERROR_STOP on

BEGIN;

\set probe_user 55555555-5555-4000-b000-000000000001

INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000000', :'probe_user'::uuid,
  'authenticated', 'authenticated', 'probe@agencia-perf.test', now(), now()
);

DO $$
DECLARE
  t0 timestamptz;
  t1 timestamptz;
  elapsed_ms numeric;
  v_result jsonb;
  v_event_id bigint;
  v_org uuid := '00000000-0000-4000-a000-000000000001';
BEGIN
  t0 := clock_timestamp();
  v_result := public.register_agency(
    'Agencia Performance Probe',
    '55555555-5555-4000-b000-000000000001'::uuid,
    'Probe Admin',
    'probe@agencia-perf.test'
  );
  t1 := clock_timestamp();
  elapsed_ms := 1000 * extract(epoch from (t1 - t0));
  RAISE NOTICE 'T050 register_agency: % ms (budget auth < 2000 ms)', elapsed_ms;
  IF elapsed_ms >= 2000 THEN
    RAISE EXCEPTION 'register_agency took % ms, exceeding the 2s authentication budget', elapsed_ms;
  END IF;
  IF v_result ->> 'slug' IS DISTINCT FROM 'agencia-performance-probe' THEN
    RAISE EXCEPTION 'performance probe did not create the expected tenant';
  END IF;

  t0 := clock_timestamp();
  v_event_id := audit.log_event(
    p_organization_id => v_org,
    p_event_type      => 'login_success',
    p_result          => 'success',
    p_actor_id        => '00000000-0000-4000-b000-000000000001'::uuid,
    p_resource_type   => 'user_profile',
    p_resource_id     => '00000000-0000-4000-b000-000000000001'::uuid
  );
  t1 := clock_timestamp();
  elapsed_ms := 1000 * extract(epoch from (t1 - t0));
  RAISE NOTICE 'T050 audit.log_event: % ms (budget < 500 ms)', elapsed_ms;
  IF elapsed_ms >= 500 THEN
    RAISE EXCEPTION 'audit.log_event took % ms, exceeding the 500ms audit budget', elapsed_ms;
  END IF;
  IF v_event_id IS NULL THEN
    RAISE EXCEPTION 'performance probe did not persist an audit event';
  END IF;
END;
$$;

ROLLBACK;
