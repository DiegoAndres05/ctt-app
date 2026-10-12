-- 01_assertions.sql
-- Assertion helpers shared by the SQL suites in supabase/tests/.
--
-- A suite fails by raising, which stops psql when it runs with ON_ERROR_STOP=1. Every
-- assertion prints the expectation it checked so that a passing run doubles as the evidence
-- of what was verified.

CREATE SCHEMA IF NOT EXISTS tests;

COMMENT ON SCHEMA tests IS
  'Verification helpers. Installed by supabase/tests/run-sql-tests.sh; not part of the application schema.';

-- Statements are passed as text so that a suite can assert under a switched role: the dynamic
-- EXECUTE runs with the caller's privileges, which is what makes the RLS checks meaningful.
CREATE OR REPLACE FUNCTION tests.assert_true(p_query text, p_description text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_result boolean;
BEGIN
  EXECUTE 'SELECT (' || p_query || ')' INTO v_result;

  IF v_result IS NOT TRUE THEN
    RAISE EXCEPTION 'FAILED: % (returned %; query: %)',
      p_description, coalesce(v_result::text, 'NULL'), p_query;
  END IF;

  RAISE NOTICE 'ok   %', p_description;
END;
$$;

-- Text twin of the bigint version, so a suite can compare references and statuses without
-- dropping them into a dynamic query. The first argument is typed text so a call never
-- becomes ambiguous with the bigint overload above.
CREATE OR REPLACE FUNCTION tests.assert_equals(
  p_actual text,
  p_expected text,
  p_description text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION 'FAILED: % (expected %, got %)', p_description, p_expected, p_actual;
  END IF;

  RAISE NOTICE 'ok   %', p_description;
END;
$$;

-- Companion to psql's `:ROW_COUNT`, which is how a suite checks that a statement was a no-op.
-- A policy that grants no visibility makes SELECT, UPDATE and DELETE reach zero rows rather
-- than fail, so "nothing happened" is the assertion that matters for those.
CREATE OR REPLACE FUNCTION tests.assert_equals(
  p_actual bigint,
  p_expected bigint,
  p_description text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION 'FAILED: % (expected %, got %)', p_description, p_expected, p_actual;
  END IF;

  RAISE NOTICE 'ok   %', p_description;
END;
$$;

CREATE OR REPLACE FUNCTION tests.assert_raises(
  p_statement text,
  p_expected_message text,
  p_description text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_message text;
BEGIN
  BEGIN
    EXECUTE p_statement;
  EXCEPTION
    WHEN others THEN
      v_message := SQLERRM;
  END;

  IF v_message IS NULL THEN
    RAISE EXCEPTION 'FAILED: % (statement succeeded but should have been rejected: %)',
      p_description, p_statement;
  END IF;

  IF position(p_expected_message IN v_message) = 0 THEN
    RAISE EXCEPTION 'FAILED: % (expected message containing "%", got "%")',
      p_description, p_expected_message, v_message;
  END IF;

  RAISE NOTICE 'ok   %', p_description;
END;
$$;

GRANT USAGE ON SCHEMA tests TO anon, authenticated, service_role, supabase_auth_admin;
GRANT EXECUTE ON FUNCTION tests.assert_true(text, text) TO anon, authenticated, service_role, supabase_auth_admin;
GRANT EXECUTE ON FUNCTION tests.assert_equals(bigint, bigint, text) TO anon, authenticated, service_role, supabase_auth_admin;
GRANT EXECUTE ON FUNCTION tests.assert_equals(text, text, text) TO anon, authenticated, service_role, supabase_auth_admin;
GRANT EXECUTE ON FUNCTION tests.assert_raises(text, text, text) TO anon, authenticated, service_role, supabase_auth_admin;
