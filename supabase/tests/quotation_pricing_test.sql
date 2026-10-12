-- quotation_pricing_test.sql
-- Server-side pricing tests for US1 (quickstart scenario 1, spec FR-002/FR-009).
-- Run with: ./supabase/tests/run-sql-tests.sh quotation_pricing_test.sql
--
-- Covers: per_person uses adults + children; per_night uses nights x quantity;
-- a package does not sum its components; a per_service add-on uses base 1;
-- 19 % tax rounded per line; a 10 % agent discount passes, 16 % raises
-- ADJUSTMENT_REQUIRES_ADMIN and the same 16 % passes as admin; a different
-- currency without a rate leaves pending_currencies and invents no converted
-- total; anon cannot EXECUTE create_quotation_draft.

\set ON_ERROR_STOP on

BEGIN;

-- Suite-specific fixed UUIDs
\set org_id       05000000-0000-4000-a000-000000000011
\set agent_id     05000000-0000-4000-b000-000000000011
\set admin_id     05000000-0000-4000-b000-000000000012
\set customer_id  05000000-0000-4000-c000-000000000011

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pg_temp.add_collaborator(
  p_user_id uuid,
  p_organization_id uuid,
  p_email text,
  p_full_name text,
  p_role public.app_role,
  p_status public.user_status DEFAULT 'active'
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  VALUES (
    '00000000-0000-0000-0000-000000000000', p_user_id, 'authenticated', 'authenticated',
    p_email, now(), now()
  );

  INSERT INTO public.user_profiles (
    id, organization_id, full_name, email, role, status, must_change_password
  )
  VALUES (p_user_id, p_organization_id, p_full_name, p_email, p_role, p_status, false);
END;
$$;

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
    jsonb_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'app_role', p_app_role,
      'organization_id', p_organization_id::text
    )::text,
    true
  );
END;
$$;

-- Product with a current base tariff, activated after the tariff exists.
CREATE OR REPLACE FUNCTION pg_temp.add_product(
  p_org uuid,
  p_name text,
  p_type public.product_type,
  p_charge public.charge_type,
  p_amount numeric,
  p_currency text
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.products (organization_id, name, type, status)
  VALUES (p_org, p_name, p_type, 'draft')
  RETURNING id INTO v_id;

  INSERT INTO public.pricing_schemes (
    organization_id, product_id, currency, base_amount, charge_type, valid_from
  ) VALUES (
    p_org, v_id, p_currency::char(3), p_amount, p_charge, now() - interval '1 day'
  );

  UPDATE public.products SET status = 'active' WHERE id = v_id;
  RETURN v_id;
END;
$$;

-- Add-on with a current base tariff (is_active defaults to true).
CREATE OR REPLACE FUNCTION pg_temp.add_addon(
  p_org uuid,
  p_name text,
  p_unit public.addon_unit,
  p_charge public.charge_type,
  p_amount numeric,
  p_currency text
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.add_ons (organization_id, name, unit)
  VALUES (p_org, p_name, p_unit)
  RETURNING id INTO v_id;

  INSERT INTO public.pricing_schemes (
    organization_id, product_id, addon_id, currency, base_amount, charge_type, valid_from
  ) VALUES (
    p_org, NULL, v_id, p_currency::char(3), p_amount, p_charge, now() - interval '1 day'
  );

  RETURN v_id;
END;
$$;

-- Marks every line of a pre-reservation as verified with a future hold, which
-- makes assert_pre_reservation_quotable accept it (feature 004). It then
-- refreshes the header status as superuser: assert_pre_reservation_quotable is
-- STABLE, so its internal re-read cannot observe the refresh it triggers, and
-- the header must already say 'verified' before the RPC is called.
CREATE OR REPLACE FUNCTION pg_temp.make_quotable(
  p_pre_reservation_id uuid,
  p_verified_by uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.pre_reservation_items
  SET verification_status = 'available',
      verified_by = p_verified_by,
      verified_at = now(),
      provider_contact_person = 'Proveedor Test',
      contact_method = 'phone',
      hold_expires_at = now() + interval '3 days'
  WHERE pre_reservation_id = p_pre_reservation_id;
  PERFORM public.refresh_pre_reservation_status(p_pre_reservation_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- Setup: organization, collaborators, customer, request
-- ---------------------------------------------------------------------------

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES (
  :'org_id'::uuid, 'Quotation Pricing Org', 'quotation-pricing-org', 'active',
  '{"default_phone_country_code":"57","default_currency":"COP"}'::jsonb
);

SELECT pg_temp.add_collaborator(:'agent_id'::uuid, :'org_id'::uuid, 'agent-quotation-pricing@test.invalid', 'Agent Quotation Pricing', 'agent');
SELECT pg_temp.add_collaborator(:'admin_id'::uuid, :'org_id'::uuid, 'admin-quotation-pricing@test.invalid', 'Admin Quotation Pricing', 'admin');

INSERT INTO public.customers (id, organization_id, first_name, last_name, email, phone_e164, created_by)
VALUES (:'customer_id'::uuid, :'org_id'::uuid, 'Test', 'Pricing', 'quotation-pricing@test.invalid', '+573001114455', :'agent_id'::uuid);

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Test","email":"quotation-pricing@test.invalid","phone":"3001114455"}'::jsonb,
  '{"travel_start_date":"2030-01-10","adults":2}'::jsonb,
  '[{"free_text":"Quotation pricing tour","quantity":1}]'::jsonb,
  :'agent_id'::uuid
) ->> 'request_id') AS req_id \gset

-- ---------------------------------------------------------------------------
-- Setup: catalog (products, add-on, package components) and published listing
-- ---------------------------------------------------------------------------

SELECT pg_temp.add_product(:'org_id'::uuid, 'City tour prueba', 'experience', 'per_person', 100.00, 'COP') AS p_pp \gset
SELECT pg_temp.add_product(:'org_id'::uuid, 'Hotel prueba', 'accommodation', 'per_night', 80.00, 'COP') AS p_hotel \gset
SELECT pg_temp.add_product(:'org_id'::uuid, 'Paquete prueba', 'package', 'per_group', 500.00, 'COP') AS p_pkg \gset
SELECT pg_temp.add_product(:'org_id'::uuid, 'Componente uno', 'experience', 'per_person', 300.00, 'COP') AS p_comp1 \gset
SELECT pg_temp.add_product(:'org_id'::uuid, 'Componente dos', 'experience', 'per_person', 400.00, 'COP') AS p_comp2 \gset
SELECT pg_temp.add_product(:'org_id'::uuid, 'Redondeo uno', 'experience', 'per_person', 100.13, 'COP') AS p_r1 \gset
SELECT pg_temp.add_product(:'org_id'::uuid, 'Redondeo dos', 'experience', 'per_person', 100.13, 'COP') AS p_r2 \gset
SELECT pg_temp.add_product(:'org_id'::uuid, 'Tour USD', 'experience', 'per_person', 50.00, 'USD') AS p_usd \gset
SELECT pg_temp.add_product(:'org_id'::uuid, 'Tour COP', 'experience', 'per_person', 100.00, 'COP') AS p_cop \gset
SELECT pg_temp.add_addon(:'org_id'::uuid, 'Traslado privado', 'per_service', 'per_group', 40.00, 'COP') AS a_svc \gset

-- Published public listing with Spanish inclusions for the city tour (009).
INSERT INTO public.public_listings (
  organization_id, product_id, placement, public_slug, status, includes
) VALUES (
  :'org_id'::uuid, :'p_pp'::uuid, 'catalog', 'city-tour-prueba', 'published',
  '[{"es":"Guía en español","en":"Spanish guide"},{"es":"Transporte","en":"Transport"}]'::jsonb
);

-- ---------------------------------------------------------------------------
-- Setup: three pre-reservations
-- ---------------------------------------------------------------------------

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'p_pp', 'start_date', '2030-01-10', 'adults', 2, 'children', 1, 'quantity', 1),
    jsonb_build_object('product_id', :'p_hotel', 'start_date', '2030-01-10', 'end_date', '2030-01-13', 'adults', 2, 'children', 0, 'quantity', 2),
    jsonb_build_object('product_id', :'p_pkg', 'start_date', '2030-01-10', 'adults', 2, 'children', 0, 'quantity', 1),
    jsonb_build_object('addon_id', :'a_svc', 'start_date', '2030-01-10', 'adults', 1, 'children', 0, 'quantity', 3)
  )),
  :'agent_id'::uuid
) AS pr1_result \gset
SELECT (:'pr1_result'::jsonb ->> 'pre_reservation_id') AS pr1 \gset

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'p_r1', 'start_date', '2030-01-10', 'adults', 1, 'children', 0, 'quantity', 1),
    jsonb_build_object('product_id', :'p_r2', 'start_date', '2030-01-10', 'adults', 1, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr2_result \gset
SELECT (:'pr2_result'::jsonb ->> 'pre_reservation_id') AS pr2 \gset

SELECT public.create_pre_reservation_core(
  :'org_id'::uuid, :'req_id'::uuid,
  jsonb_build_object('items', jsonb_build_array(
    jsonb_build_object('product_id', :'p_usd', 'start_date', '2030-01-10', 'adults', 1, 'children', 0, 'quantity', 1),
    jsonb_build_object('product_id', :'p_cop', 'start_date', '2030-01-10', 'adults', 1, 'children', 0, 'quantity', 1)
  )),
  :'agent_id'::uuid
) AS pr3_result \gset
SELECT (:'pr3_result'::jsonb ->> 'pre_reservation_id') AS pr3 \gset

SELECT pg_temp.make_quotable(:'pr1'::uuid, :'agent_id'::uuid);
SELECT pg_temp.make_quotable(:'pr2'::uuid, :'agent_id'::uuid);
SELECT pg_temp.make_quotable(:'pr3'::uuid, :'agent_id'::uuid);

-- =============================================================================
-- TEST: per_person, per_night, package and per_service bases (R-002)
-- =============================================================================
RESET ROLE;
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.create_quotation_draft(:'pr1'::uuid) AS b1 \gset
SELECT (:'b1'::jsonb ->> 'version_id') AS v1 \gset

SELECT tests.assert_true(
  format($$SELECT jsonb_array_length(%L::jsonb -> 'lines') = 4$$, :'b1'),
  'draft breakdown has the four pre-reservation lines'
);

SELECT tests.assert_true(
  format($$SELECT %L::jsonb ->> 'status' = 'draft'$$, :'b1'),
  'draft breakdown reports status draft'
);

SELECT tests.assert_true(
  format($$SELECT %L::jsonb ->> 'currency' = 'COP'$$, :'b1'),
  'quotation currency comes from the tenant default (COP)'
);

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{lines,0,charge_type}') = 'per_person'
            AND (%L::jsonb #>> '{lines,0,charge_basis}')::numeric = 3
            AND (%L::jsonb #>> '{lines,0,line_base}')::numeric = 300.00$$, :'b1', :'b1', :'b1'),
  'per_person uses adults + children: (2 + 1) x 100.00 = 300.00'
);

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{lines,1,charge_type}') = 'per_night'
            AND (%L::jsonb #>> '{lines,1,charge_basis}')::numeric = 6
            AND (%L::jsonb #>> '{lines,1,line_base}')::numeric = 480.00$$, :'b1', :'b1', :'b1'),
  'per_night uses nights x quantity: 3 nights x 2 x 80.00 = 480.00'
);

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{lines,2,charge_type}') = 'per_group'
            AND (%L::jsonb #>> '{lines,2,charge_basis}')::numeric = 1
            AND (%L::jsonb #>> '{lines,2,line_base}')::numeric = 500.00$$, :'b1', :'b1', :'b1'),
  'package keeps its own per_group tariff: 500.00, not the 700.00 sum of its components'
);

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{lines,3,charge_basis}')::numeric = 1
            AND (%L::jsonb #>> '{lines,3,line_base}')::numeric = 40.00$$, :'b1', :'b1'),
  'per_service add-on uses base 1: 40.00 even with quantity 3'
);

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{subtotal}')::numeric = 1320.00
            AND (%L::jsonb #>> '{tax_total}')::numeric = 0
            AND (%L::jsonb #>> '{adjustment_total}')::numeric = 0
            AND (%L::jsonb #>> '{total}')::numeric = 1320.00$$, :'b1', :'b1', :'b1', :'b1'),
  'header equals the sum of the four rounded lines: 1320.00'
);

SELECT tests.assert_true(
  format($$SELECT jsonb_array_length(%L::jsonb -> 'pending_currencies') = 0$$, :'b1'),
  'no pending currencies when every tariff matches the quotation currency'
);

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb ->> 'party_adults')::numeric = 2
            AND (%L::jsonb ->> 'party_children')::numeric = 1$$, :'b1', :'b1'),
  'party size is the max across lines'
);

-- Draft texts: Spanish inclusions from the published listing, R-009 default terms.
-- The literal text is asserted rather than calling quotation_default_terms(),
-- which is internal (EXECUTE revoked from authenticated) and unavailable here.
SELECT tests.assert_true(
  format($$SELECT v.inclusions = 'Guía en español' || chr(10) || 'Transporte'
          FROM public.quotation_versions v
          WHERE v.id = %L::uuid$$, :'v1'),
  'draft copies the Spanish inclusions of the published public listing'
);

SELECT tests.assert_true(
  format($$SELECT v.terms = 'Esta propuesta es válida hasta la fecha y hora indicadas y queda sujeta a disponibilidad de servicios y tarifas. Esta cotización no es una reserva ni una factura.'
          FROM public.quotation_versions v
          WHERE v.id = %L::uuid$$, :'v1'),
  'draft without a quotation_defaults row uses the fixed R-009 conditions text'
);

-- =============================================================================
-- TEST: 19 % tax is rounded per line (FR-002, R-003)
-- =============================================================================
SELECT public.create_quotation_draft(:'pr2'::uuid) AS b2 \gset
SELECT (:'b2'::jsonb #>> '{lines,0,line_id}') AS l2a \gset
SELECT (:'b2'::jsonb #>> '{lines,1,line_id}') AS l2b \gset

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{lines,0,line_base}')::numeric = 100.13
            AND (%L::jsonb #>> '{lines,1,line_base}')::numeric = 100.13$$, :'b2', :'b2'),
  'odd line bases round to 100.13 each'
);

SELECT public.set_quotation_line_tax(:'l2a'::uuid, 19) AS b2a \gset
SELECT public.set_quotation_line_tax(:'l2b'::uuid, 19) AS b2b \gset

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{lines,0,line_tax}')::numeric = 19.02
            AND (%L::jsonb #>> '{lines,1,line_tax}')::numeric = 19.02$$, :'b2b', :'b2b'),
  'each line rounds its own tax: round(100.13 x 19 %, 2) = 19.02'
);

SELECT tests.assert_equals(
  (:'b2b'::jsonb #>> '{tax_total}'),
  '38.04',
  'tax_total is the sum of per-line rounded taxes: 19.02 + 19.02 = 38.04'
);

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{tax_total}')::numeric <> 38.05$$, :'b2b'),
  'tax_total is not the single rounding of the raw sum (38.05)'
);

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{total}')::numeric = 238.30$$, :'b2b'),
  'total = 200.26 of lines + 38.04 of tax = 238.30'
);

-- =============================================================================
-- TEST: agent discount cap (FR-009, R-005): 10 % passes, 16 % needs admin
-- =============================================================================
SELECT public.upsert_quotation_adjustment(
  :'v1'::uuid, NULL, 'Cortesía', 'discount', 'percent', 10
) AS d1 \gset

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{adjustment_total}')::numeric = -132.00
            AND (%L::jsonb #>> '{total}')::numeric = 1188.00$$, :'d1', :'d1'),
  'agent 10 % discount applies: impact 132.00 under the 198.00 cap, total 1188.00'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.upsert_quotation_adjustment(%L::uuid, NULL, 'Prueba 16', 'discount', 'percent', 16)$$,
    :'v1'
  ),
  'ADJUSTMENT_REQUIRES_ADMIN',
  'agent 16 % discount is rejected with ADJUSTMENT_REQUIRES_ADMIN'
);

RESET ROLE;
SELECT pg_temp.act_as(:'admin_id'::uuid, :'org_id'::uuid, 'admin');
SET LOCAL ROLE authenticated;

SELECT public.upsert_quotation_adjustment(
  :'v1'::uuid, NULL, 'Prueba 16', 'discount', 'percent', 16
) AS d2 \gset

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{adjustment_total}')::numeric = -343.20
            AND (%L::jsonb #>> '{total}')::numeric = 976.80$$, :'d2', :'d2'),
  'the same 16 % discount applies as admin: 132.00 + 211.20 = 343.20, total 976.80'
);

-- =============================================================================
-- TEST: audit events carry codes only, never labels or values
-- =============================================================================
RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT count(*) >= 1 FROM audit.audit_events
      WHERE organization_id = %L::uuid
        AND event_type = 'quotation_created'
        AND resource_id = %L::uuid
        AND NOT (metadata ? 'label')
        AND NOT (metadata ? 'terms')
        AND NOT (metadata ? 'notes')
        AND NOT (metadata ? 'email')
        AND NOT (metadata ? 'phone')$$,
    :'org_id', :'v1'
  ),
  'quotation_created audit carries ids only, no label, terms, notes or contact data'
);

SELECT tests.assert_true(
  format(
    $$SELECT count(*) = 2
         AND bool_and(metadata ? 'direction')
         AND bool_and(metadata ? 'kind')
         AND bool_and(NOT (metadata ? 'label'))
         AND bool_and(NOT (metadata ? 'value'))
      FROM audit.audit_events
      WHERE organization_id = %L::uuid
        AND event_type = 'quotation_adjustment_applied'
        AND resource_id = %L::uuid$$,
    :'org_id', :'v1'
  ),
  'quotation_adjustment_applied audit has direction/kind but never the label or value'
);

-- =============================================================================
-- TEST: a different currency without a rate is pending, never invented (R-003)
-- =============================================================================
SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.create_quotation_draft(:'pr3'::uuid) AS b3 \gset
SELECT (:'b3'::jsonb ->> 'version_id') AS v3 \gset

SELECT tests.assert_equals(
  (:'b3'::jsonb #>> '{pending_currencies}'),
  '["USD"]',
  'the USD tariff without a rate is reported in pending_currencies'
);

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{lines,0,unit_price}')::numeric = 0
            AND (%L::jsonb #>> '{lines,0,line_base}')::numeric = 0
            AND (%L::jsonb #>> '{lines,0,currency_pending}')::boolean$$, :'b3', :'b3', :'b3'),
  'the pending USD line keeps a zero amount instead of an invented conversion'
);

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{subtotal}')::numeric = 100.00
            AND (%L::jsonb #>> '{total}')::numeric = 100.00$$, :'b3', :'b3'),
  'the total only adds the convertible COP line: 100.00, no invented USD total'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.set_quotation_exchange_rate(%L::uuid, 'USD', 0)$$,
    :'v3'
  ),
  'EXCHANGE_RATE_INVALID',
  'a non-positive exchange rate is rejected with EXCHANGE_RATE_INVALID'
);

SELECT public.set_quotation_exchange_rate(:'v3'::uuid, 'USD', 4100) AS b3b \gset

SELECT tests.assert_true(
  format($$SELECT jsonb_array_length(%L::jsonb -> 'pending_currencies') = 0$$, :'b3b'),
  'after the rate is stored the draft has no pending currencies'
);

SELECT tests.assert_true(
  format($$SELECT (%L::jsonb #>> '{lines,0,unit_price}')::numeric = 205000.00
            AND (%L::jsonb #>> '{lines,0,exchange_rate}')::numeric = 4100
            AND (%L::jsonb #>> '{total}')::numeric = 205100.00$$, :'b3b', :'b3b', :'b3b'),
  'the rate converts the USD line: 50.00 x 4100 = 205000.00 and total 205100.00'
);

-- =============================================================================
-- TEST: anon cannot EXECUTE create_quotation_draft
-- =============================================================================
RESET ROLE;
SET LOCAL ROLE anon;

SELECT tests.assert_raises(
  'SELECT public.create_quotation_draft(gen_random_uuid())',
  'permission denied',
  'anon cannot EXECUTE create_quotation_draft'
);

SELECT tests.assert_raises(
  'SELECT public.recalculate_quotation(gen_random_uuid())',
  'permission denied',
  'anon cannot EXECUTE recalculate_quotation'
);

RESET ROLE;
ROLLBACK;
