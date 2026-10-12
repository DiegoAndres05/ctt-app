-- 041_us4_verification_traceability.sql
-- Read-only views for the immutable verification history and the per-pre-reservation
-- verification times.
-- Source of truth: specs/004-prereservation-availability/data-model.md (§Views),
-- specs/004-prereservation-availability/research.md (R-007, R-010).
--
-- Both views are security_invoker so the tenant RLS of the underlying tables applies.

-- ---------------------------------------------------------------------------
-- availability_verification_history
-- ---------------------------------------------------------------------------

CREATE VIEW public.availability_verification_history WITH (security_invoker = true) AS
SELECT
  e.id,
  e.organization_id,
  e.pre_reservation_id,
  pr.reference,
  e.item_id,
  i.item_label,
  e.event_kind,
  e.from_status,
  e.to_status,
  e.provider_contact_person,
  e.contact_method,
  e.hold_expires_at,
  e.notes,
  e.metadata,
  e.actor_id,
  a.full_name AS actor_name,
  e.created_at
FROM public.availability_verification_events e
JOIN public.pre_reservations pr
  ON pr.id = e.pre_reservation_id AND pr.organization_id = e.organization_id
LEFT JOIN public.pre_reservation_items i
  ON i.id = e.item_id AND i.organization_id = e.organization_id
JOIN public.user_profiles a
  ON a.id = e.actor_id AND a.organization_id = e.organization_id;

COMMENT ON VIEW public.availability_verification_history IS
  'Chronological verification history per pre-reservation with actor name and line label. security_invoker enforces RLS.';

REVOKE ALL ON public.availability_verification_history FROM anon;
GRANT SELECT ON public.availability_verification_history TO authenticated;

-- ---------------------------------------------------------------------------
-- pre_reservation_verification_times
-- ---------------------------------------------------------------------------

CREATE VIEW public.pre_reservation_verification_times WITH (security_invoker = true) AS
SELECT
  pr.id,
  pr.organization_id,
  pr.reference,
  pr.status,
  pr.created_at,
  f.first_started_at,
  pr.first_verified_at,
  CASE
    WHEN f.first_started_at IS NULL THEN NULL
    ELSE round(extract(epoch FROM (f.first_started_at - pr.created_at)) / 3600, 2)
  END AS hours_to_first_start,
  CASE
    WHEN pr.first_verified_at IS NULL THEN NULL
    ELSE round(extract(epoch FROM (pr.first_verified_at - pr.created_at)) / 3600, 2)
  END AS hours_to_verified,
  f.item_count,
  f.verifier_count
FROM public.pre_reservations pr
JOIN LATERAL (
  SELECT
    min(i.verification_started_at) AS first_started_at,
    count(*) AS item_count,
    count(DISTINCT i.verified_by) AS verifier_count
  FROM public.pre_reservation_items i
  WHERE i.pre_reservation_id = pr.id
    AND i.organization_id = pr.organization_id
) f ON true;

COMMENT ON VIEW public.pre_reservation_verification_times IS
  'One row per pre-reservation with elapsed hours from creation to first provider contact and to total verification (SC-002). security_invoker enforces RLS.';

REVOKE ALL ON public.pre_reservation_verification_times FROM anon;
GRANT SELECT ON public.pre_reservation_verification_times TO authenticated;
