-- request_workflow_test.sql
-- Status transitions, assignment, notes, and customer edits.
--
-- Run with: ./supabase/tests/run-sql-tests.sh request_workflow_test.sql

\set ON_ERROR_STOP on

BEGIN;

\set org_id         03000000-0000-4000-a000-000000000041
\set org_b_id       03000000-0000-4000-a000-000000000042
\set agent_id       03000000-0000-4000-b000-000000000041
\set other_agent_id 03000000-0000-4000-b000-000000000042
\set inactive_id    03000000-0000-4000-b000-000000000043

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

INSERT INTO public.organizations (id, name, slug, status, settings)
VALUES
  (
    :'org_id'::uuid, 'Workflow', 'workflow-org', 'active',
    '{"default_phone_country_code":"57"}'::jsonb
  ),
  (
    :'org_b_id'::uuid, 'Workflow B', 'workflow-org-b', 'active',
    '{"default_phone_country_code":"57"}'::jsonb
  );

SELECT pg_temp.add_collaborator(
  :'agent_id'::uuid, :'org_id'::uuid, 'agente-wf@test.invalid', 'Agente WF', 'agent'
);
SELECT pg_temp.add_collaborator(
  :'other_agent_id'::uuid, :'org_b_id'::uuid, 'agente-wf-b@test.invalid', 'Agente WFB', 'agent'
);
SELECT pg_temp.add_collaborator(
  :'inactive_id'::uuid, :'org_id'::uuid, 'inactivo-wf@test.invalid', 'Inactivo WF', 'agent', 'inactive'
);

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Laura","email":"laura-wf@test.invalid","phone":"3001000001"}'::jsonb,
  '{"special_requirements":"Recibida"}'::jsonb,
  '[{"free_text":"Tour","quantity":1}]'::jsonb,
  NULL
) ->> 'request_id') AS received_id \gset

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Mario","email":"mario-wf@test.invalid"}'::jsonb,
  '{"special_requirements":"Para descartar"}'::jsonb,
  '[{"free_text":"Tour 2","quantity":1}]'::jsonb,
  NULL
) ->> 'request_id') AS discard_id \gset

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'in_person', NULL,
  '{"first_name":"Nora","phone":"3001000003"}'::jsonb,
  '{"special_requirements":"En gestión"}'::jsonb,
  '[{"free_text":"Tour 3","quantity":1}]'::jsonb,
  NULL
) ->> 'request_id') AS review_id \gset

SELECT (public.capture_request_core(
  :'org_id'::uuid, 'phone', NULL,
  '{"first_name":"Omar","phone":"3001000004"}'::jsonb,
  '{"special_requirements":"Cerrada"}'::jsonb,
  '[{"free_text":"Tour 4","quantity":1}]'::jsonb,
  NULL
) ->> 'request_id') AS closed_id \gset

SELECT customer_id AS laura_id
FROM public.customer_requests
WHERE id = :'received_id'::uuid \gset

SELECT customer_id AS mario_id
FROM public.customer_requests
WHERE id = :'discard_id'::uuid \gset

SELECT pg_temp.act_as(:'agent_id'::uuid, :'org_id'::uuid, 'agent');
SET LOCAL ROLE authenticated;

SELECT public.set_request_status(:'received_id'::uuid, 'in_review', NULL);
SELECT public.set_request_status(:'review_id'::uuid, 'in_review', NULL);
SELECT public.set_request_status(:'review_id'::uuid, 'discarded', 'Ya no viaja');
SELECT public.set_request_status(:'discard_id'::uuid, 'discarded', 'El cliente desistió');
SELECT public.set_request_status(:'closed_id'::uuid, 'discarded', 'Duplicada');

SELECT tests.assert_raises(
  format(
    $$SELECT public.set_request_status(%L::uuid, 'discarded', '   ')$$,
    :'received_id'
  ),
  'DISCARD_REASON_REQUIRED',
  'discarding without a reason is rejected'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.set_request_status(%L::uuid, 'pre_reservation', NULL)$$,
    :'received_id'
  ),
  'PRE_RESERVATION_REQUIRES_CONVERSION',
  'pre_reservation cannot be set manually from an open request'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.set_request_status(%L::uuid, 'pre_reservation', NULL)$$,
    :'closed_id'
  ),
  'PRE_RESERVATION_REQUIRES_CONVERSION',
  'pre_reservation cannot be set manually from a discarded request'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.set_request_status(%L::uuid, 'received', NULL)$$,
    :'received_id'
  ),
  'INVALID_STATUS_TRANSITION',
  'in_review cannot return to received'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.set_request_status(%L::uuid, 'in_review', NULL)$$,
    :'closed_id'
  ),
  'REQUEST_CLOSED',
  'a discarded request cannot change status'
);

SELECT public.assign_request(:'received_id'::uuid, :'agent_id'::uuid);
SELECT public.assign_request(:'received_id'::uuid, NULL);
SELECT public.assign_request(:'received_id'::uuid, :'agent_id'::uuid);

SELECT tests.assert_raises(
  format(
    $$SELECT public.assign_request(%L::uuid, %L::uuid)$$,
    :'received_id', :'inactive_id'
  ),
  'ASSIGNEE_NOT_IN_ORGANIZATION',
  'an inactive collaborator cannot be assigned'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.assign_request(%L::uuid, %L::uuid)$$,
    :'received_id', :'other_agent_id'
  ),
  'ASSIGNEE_NOT_IN_ORGANIZATION',
  'a collaborator from another organization cannot be assigned'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.assign_request(%L::uuid, %L::uuid)$$,
    :'closed_id', :'agent_id'
  ),
  'REQUEST_CLOSED',
  'a closed request cannot be reassigned'
);

SELECT (public.add_request_note(
  :'received_id'::uuid, NULL, 'Llamar mañana'
) ->> 'note_id') AS note_id \gset

SELECT tests.assert_raises(
  $$SELECT public.add_request_note(NULL, NULL, 'Sin destino')$$,
  'VALIDATION_ERROR',
  'a note needs exactly one target'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.add_request_note(%L::uuid, %L::uuid, 'Dos destinos')$$,
    :'received_id', :'laura_id'
  ),
  'VALIDATION_ERROR',
  'a note cannot target a request and a customer together'
);

SELECT public.update_customer(
  :'laura_id'::uuid,
  jsonb_build_object(
    'first_name', 'Laura',
    'email', ' Laura-WF@Example.COM ',
    'phone', '3001000001',
    'country_code', 'co'
  )
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.update_customer(%L::uuid, jsonb_build_object(
        'first_name', 'Mario',
        'email', 'laura-wf@example.com'
      ))$$,
    :'mario_id'
  ),
  'CUSTOMER_CONTACT_TAKEN',
  'update_customer rejects an email that belongs to someone else'
);

SELECT tests.assert_raises(
  format(
    $$SELECT public.update_customer(%L::uuid, jsonb_build_object(
        'first_name', ' ',
        'email', 'mario-wf@test.invalid'
      ))$$,
    :'mario_id'
  ),
  'CONTACT_REQUIRED',
  'update_customer requires a name'
);

RESET ROLE;

SELECT tests.assert_true(
  format(
    $$SELECT status = 'in_review'
         AND first_handled_at IS NOT NULL
         AND assigned_to = %L::uuid
         AND assigned_at IS NOT NULL
       FROM public.customer_requests
       WHERE id = %L::uuid$$,
    :'agent_id', :'received_id'
  ),
  'in_review keeps first_handled_at and the latest assignment'
);

SELECT tests.assert_true(
  format(
    $$SELECT status = 'discarded'
         AND closed_at IS NOT NULL
         AND discard_reason = 'El cliente desistió'
         AND first_handled_at IS NOT NULL
       FROM public.customer_requests
       WHERE id = %L::uuid$$,
    :'discard_id'
  ),
  'discarding from received sets the reason, first_handled_at, and closed_at'
);

SELECT tests.assert_true(
  format(
    $$SELECT author_id = %L::uuid AND content = 'Llamar mañana'
       FROM public.request_notes
       WHERE id = %L::uuid$$,
    :'agent_id', :'note_id'
  ),
  'the note author is auth.uid()'
);

SELECT tests.assert_raises(
  $$UPDATE public.request_notes SET content = 'Cambiada'$$,
  'append-only',
  'notes cannot be updated, even by the table owner'
);

SELECT tests.assert_raises(
  'DELETE FROM public.request_notes',
  'append-only',
  'notes cannot be deleted, even by the table owner'
);

SELECT tests.assert_raises(
  'TRUNCATE public.request_notes',
  'append-only',
  'notes cannot be truncated'
);

SELECT tests.assert_true(
  format(
    $$SELECT email = 'laura-wf@example.com' AND country_code = 'CO'
       FROM public.customers
       WHERE id = %L::uuid$$,
    :'laura_id'
  ),
  'update_customer normalizes email and country code'
);

SELECT tests.assert_true(
  format(
    $$SELECT metadata ? 'from'
         AND metadata ? 'to'
         AND NOT (metadata ? 'reason')
         AND metadata::text NOT ILIKE '%%desistió%%'
         AND metadata::text NOT ILIKE '%%laura%%'
       FROM audit.audit_events
       WHERE event_type = 'request_status_changed'
         AND resource_id = %L::uuid
       ORDER BY id DESC
       LIMIT 1$$,
    :'discard_id'
  ),
  'status audit stores from/to and omits the reason and the customer name'
);

SELECT tests.assert_true(
  format(
    $$SELECT bool_and(
           metadata ? 'from'
           AND metadata ? 'to'
           AND metadata::text NOT ILIKE '%%agente-wf@test.invalid%%'
         )
       FROM audit.audit_events
       WHERE event_type = 'request_assigned'
         AND resource_id = %L::uuid$$,
    :'received_id'
  ),
  'assignment audit stores ids and omits the collaborator email'
);

SELECT tests.assert_true(
  format(
    $$SELECT metadata -> 'fields' ? 'email'
         AND metadata::text NOT ILIKE '%%laura-wf@example.com%%'
       FROM audit.audit_events
       WHERE event_type = 'customer_updated'
         AND resource_id = %L::uuid$$,
    :'laura_id'
  ),
  'customer update audit lists field names and omits the email value'
);

ROLLBACK;
