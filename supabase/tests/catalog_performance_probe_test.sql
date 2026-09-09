-- catalog_performance_probe_test.sql
-- Local measurements for SC-004 (catalog list < 1s at 5,000 items) and SC-003
-- (deterministic resolve_price). Not a substitute for a production load test.
-- Pattern follows performance_probe_test.sql: seed in a probe tenant, time the
-- tenant-scoped query under RLS, ROLLBACK.
--
-- Run with: supabase/tests/run-sql-tests.sh supabase/tests/catalog_performance_probe_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set probe_org   77777777-7777-4000-a000-000000000077
\set probe_user  77777777-7777-4000-b000-000000000077

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES (
  :'probe_org'::uuid,
  'Catalog Performance Probe',
  'catalog-performance-probe',
  'active',
  jsonb_build_object('default_currency', 'COP')
);

INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000000', :'probe_user'::uuid,
  'authenticated', 'authenticated', 'catalog-probe@agencia-perf.test', now(), now()
);

INSERT INTO public.user_profiles (
  id, organization_id, full_name, email, role, status, must_change_password
)
VALUES (
  :'probe_user'::uuid, :'probe_org'::uuid,
  'Catalog Probe Admin', 'catalog-probe@agencia-perf.test', 'admin', 'active', false
);

INSERT INTO public.products (organization_id, type, name, status)
SELECT
  :'probe_org'::uuid,
  'experience',
  'Probe ' || lpad(g::text, 4, '0'),
  'draft'
FROM generate_series(1, 5000) AS g;

-- One priced product so resolve_price has a current base + season to choose from.
UPDATE public.products
SET name = 'Probe priced'
WHERE id = (
  SELECT id FROM public.products
  WHERE organization_id = :'probe_org'::uuid
  ORDER BY name
  LIMIT 1
);

INSERT INTO public.pricing_schemes (
  organization_id, product_id, currency, base_amount, charge_type
)
SELECT :'probe_org'::uuid, id, 'COP', 150000, 'per_person'
FROM public.products
WHERE organization_id = :'probe_org'::uuid AND name = 'Probe priced';

INSERT INTO public.pricing_schemes (
  organization_id, product_id, currency, base_amount, charge_type,
  season_start, season_end
)
SELECT :'probe_org'::uuid, id, 'COP', 180000, 'per_person',
       DATE '2026-12-01', DATE '2027-01-15'
FROM public.products
WHERE organization_id = :'probe_org'::uuid AND name = 'Probe priced';

SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', :'probe_user'::text,
    'role', 'authenticated',
    'app_role', 'admin',
    'organization_id', :'probe_org'::text
  )::text,
  true
);

SET LOCAL ROLE authenticated;

DO $$
DECLARE
  t0 timestamptz;
  t1 timestamptz;
  elapsed_ms numeric;
  v_count integer;
  v_product_id uuid;
  v_amount numeric;
  v_source text;
BEGIN
  SELECT id INTO STRICT v_product_id
  FROM public.products
  WHERE name = 'Probe priced';

  t0 := clock_timestamp();
  SELECT count(*) INTO v_count FROM public.products;
  t1 := clock_timestamp();
  elapsed_ms := 1000 * extract(epoch from (t1 - t0));
  RAISE NOTICE 'T045 catalog count (5000, RLS): % ms (budget SC-004 < 1000 ms)', elapsed_ms;
  IF v_count <> 5000 THEN
    RAISE EXCEPTION 'catalog probe expected 5000 tenant products, got %', v_count;
  END IF;
  IF elapsed_ms >= 1000 THEN
    RAISE EXCEPTION 'tenant catalog count took % ms, exceeding the 1s SC-004 budget', elapsed_ms;
  END IF;

  -- Matches ProductService.list: name order, page of 50, against a 5,000-row catalog.
  t0 := clock_timestamp();
  PERFORM p.id, p.name, p.type, p.status, p.created_at
  FROM public.products p
  ORDER BY p.name
  LIMIT 50;
  t1 := clock_timestamp();
  elapsed_ms := 1000 * extract(epoch from (t1 - t0));
  RAISE NOTICE 'T045 catalog list LIMIT 50 (of 5000, RLS): % ms (budget SC-004 < 1000 ms)', elapsed_ms;
  IF elapsed_ms >= 1000 THEN
    RAISE EXCEPTION 'catalog list (limit 50) took % ms, exceeding the 1s SC-004 budget', elapsed_ms;
  END IF;

  t0 := clock_timestamp();
  PERFORM p.id, p.name, p.type, p.status, p.created_at
  FROM public.products p
  ORDER BY p.name;
  t1 := clock_timestamp();
  elapsed_ms := 1000 * extract(epoch from (t1 - t0));
  RAISE NOTICE 'T045 catalog list all 5000 (RLS): % ms (budget SC-004 < 1000 ms)', elapsed_ms;
  IF elapsed_ms >= 1000 THEN
    RAISE EXCEPTION 'full catalog list of 5000 took % ms, exceeding the 1s SC-004 budget', elapsed_ms;
  END IF;

  t0 := clock_timestamp();
  SELECT amount, source INTO v_amount, v_source
  FROM public.resolve_price(v_product_id, DATE '2026-12-20', 'per_person');
  t1 := clock_timestamp();
  elapsed_ms := 1000 * extract(epoch from (t1 - t0));
  RAISE NOTICE 'T045 resolve_price season: % ms (amount=%, source=%)', elapsed_ms, v_amount, v_source;
  IF v_amount IS DISTINCT FROM 180000 OR v_source IS DISTINCT FROM 'season' THEN
    RAISE EXCEPTION 'resolve_price season mismatch: amount=% source=%', v_amount, v_source;
  END IF;
  IF elapsed_ms >= 200 THEN
    RAISE EXCEPTION 'resolve_price (season) took % ms, exceeding the 200ms probe budget', elapsed_ms;
  END IF;

  t0 := clock_timestamp();
  SELECT amount, source INTO v_amount, v_source
  FROM public.resolve_price(v_product_id, DATE '2026-10-15', 'per_person');
  t1 := clock_timestamp();
  elapsed_ms := 1000 * extract(epoch from (t1 - t0));
  RAISE NOTICE 'T045 resolve_price base: % ms (amount=%, source=%)', elapsed_ms, v_amount, v_source;
  IF v_amount IS DISTINCT FROM 150000 OR v_source IS DISTINCT FROM 'base' THEN
    RAISE EXCEPTION 'resolve_price base mismatch: amount=% source=%', v_amount, v_source;
  END IF;
  IF elapsed_ms >= 200 THEN
    RAISE EXCEPTION 'resolve_price (base) took % ms, exceeding the 200ms probe budget', elapsed_ms;
  END IF;
END;
$$;

RESET ROLE;

ROLLBACK;
