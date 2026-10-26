-- 055_analytics_rpcs.sql
-- Feature 008: funnel, ops times, stale queue, sales summary, product ranking.
-- Specs: specs/008-analytics-reporting/{research,data-model,contracts}.

CREATE OR REPLACE FUNCTION public.analytics_bounds(p_from date, p_to date)
RETURNS TABLE (range_start timestamptz, range_end timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_from IS NULL OR p_to IS NULL OR p_from > p_to THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;
  IF (p_to - p_from) > 366 THEN
    RAISE EXCEPTION 'DATE_RANGE_TOO_LONG' USING ERRCODE = 'raise_exception';
  END IF;
  range_start := (p_from::timestamp AT TIME ZONE 'America/Bogota');
  range_end := ((p_to + 1)::timestamp AT TIME ZONE 'America/Bogota');
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.analytics_bounds(date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.analytics_bounds(date, date) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.analytics_scope()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role text := auth.jwt() ->> 'app_role';
BEGIN
  IF v_role IN ('admin', 'operator') THEN
    RETURN 'org';
  END IF;
  RETURN 'self';
END;
$$;

REVOKE ALL ON FUNCTION public.analytics_scope() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.analytics_scope() FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.analytics_funnel(p_from date, p_to date, p_channel text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_start timestamptz;
  v_end timestamptz;
  v_scope text;
  v_actor uuid := auth.uid();
  v_channel public.request_channel;
  v_req int := 0;
  v_pr int := 0;
  v_ver int := 0;
  v_q int := 0;
  v_rsv int := 0;
  v_ch text;
BEGIN
  v_org := public.require_tenant_member();
  SELECT b.range_start, b.range_end INTO v_start, v_end
  FROM public.analytics_bounds(p_from, p_to) b;
  v_scope := public.analytics_scope();
  v_ch := nullif(btrim(coalesce(p_channel, '')), '');
  IF v_ch IS NOT NULL THEN
    BEGIN
      v_channel := v_ch::public.request_channel;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
    END;
  END IF;

  SELECT count(*)::int INTO v_req
  FROM public.customer_requests r
  WHERE r.organization_id = v_org
    AND r.created_at >= v_start AND r.created_at < v_end
    AND (v_channel IS NULL OR r.channel = v_channel)
    AND (v_scope = 'org' OR r.created_by = v_actor);

  SELECT count(*)::int INTO v_pr
  FROM public.pre_reservations pr
  JOIN public.customer_requests r
    ON r.id = pr.request_id AND r.organization_id = pr.organization_id
  WHERE pr.organization_id = v_org
    AND pr.created_at >= v_start AND pr.created_at < v_end
    AND (v_channel IS NULL OR r.channel = v_channel)
    AND (v_scope = 'org' OR pr.created_by = v_actor);

  SELECT count(*)::int INTO v_ver
  FROM public.pre_reservations pr
  JOIN public.customer_requests r
    ON r.id = pr.request_id AND r.organization_id = pr.organization_id
  WHERE pr.organization_id = v_org
    AND pr.status = 'verified'::public.pre_reservation_status
    AND coalesce(pr.verified_at, pr.updated_at) >= v_start
    AND coalesce(pr.verified_at, pr.updated_at) < v_end
    AND (v_channel IS NULL OR r.channel = v_channel)
    AND (v_scope = 'org' OR pr.created_by = v_actor);

  SELECT count(*)::int INTO v_q
  FROM public.quotation_versions qv
  JOIN public.quotation_families qf
    ON qf.id = qv.family_id AND qf.organization_id = qv.organization_id
  JOIN public.pre_reservations pr
    ON pr.id = qf.pre_reservation_id AND pr.organization_id = qv.organization_id
  JOIN public.customer_requests r
    ON r.id = pr.request_id AND r.organization_id = qv.organization_id
  WHERE qv.organization_id = v_org
    AND qv.issued_at IS NOT NULL
    AND qv.issued_at >= v_start AND qv.issued_at < v_end
    AND (v_channel IS NULL OR r.channel = v_channel)
    AND (v_scope = 'org' OR qv.created_by = v_actor);

  SELECT count(*)::int INTO v_rsv
  FROM public.reservation_families f
  JOIN public.pre_reservations pr
    ON pr.id = f.pre_reservation_id AND pr.organization_id = f.organization_id
  JOIN public.customer_requests r
    ON r.id = pr.request_id AND r.organization_id = f.organization_id
  WHERE f.organization_id = v_org
    AND f.created_at >= v_start AND f.created_at < v_end
    AND (v_channel IS NULL OR r.channel = v_channel)
    AND (v_scope = 'org' OR f.created_by = v_actor);

  RETURN jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'channel', v_ch,
    'scope', v_scope,
    'stages', jsonb_build_array(
      public.analytics_stage('requests', 'Solicitudes', v_req, NULL, v_req),
      public.analytics_stage('pre_reservations', 'Pre-reservas', v_pr, v_req, v_req),
      public.analytics_stage('verified', 'Verificadas', v_ver, v_pr, v_req),
      public.analytics_stage('quotations_issued', 'Cotizaciones emitidas', v_q, v_ver, v_req),
      public.analytics_stage('reservations_confirmed', 'Reservas confirmadas', v_rsv, v_q, v_req)
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.analytics_stage(
  p_stage text, p_label text, p_count int, p_prev int, p_top int
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'stage', p_stage,
    'label', p_label,
    'count', p_count,
    'conversion_from_previous', CASE WHEN p_prev IS NULL THEN NULL
      WHEN p_prev > 0 THEN round((p_count::numeric / p_prev), 4) ELSE NULL END,
    'conversion_from_top', CASE WHEN p_top > 0 THEN round((p_count::numeric / p_top), 4) ELSE NULL END
  );
$$;

REVOKE ALL ON FUNCTION public.analytics_stage(text, text, int, int, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.analytics_stage(text, text, int, int, int) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.analytics_funnel(date, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.analytics_funnel(date, date, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.analytics_ops_times(p_from date, p_to date, p_channel text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_start timestamptz;
  v_end timestamptz;
  v_scope text;
  v_actor uuid := auth.uid();
  v_channel public.request_channel;
  v_ch text;
  v_avg_req numeric;
  v_n_req int;
  v_avg_ver numeric;
  v_n_ver int;
  v_avg_q numeric;
  v_n_q int;
BEGIN
  v_org := public.require_tenant_member();
  SELECT b.range_start, b.range_end INTO v_start, v_end FROM public.analytics_bounds(p_from, p_to) b;
  v_scope := public.analytics_scope();
  v_ch := nullif(btrim(coalesce(p_channel, '')), '');
  IF v_ch IS NOT NULL THEN
    v_channel := v_ch::public.request_channel;
  END IF;

  SELECT avg(extract(epoch FROM (r.first_handled_at - r.created_at)) / 3600.0), count(*)::int
  INTO v_avg_req, v_n_req
  FROM public.customer_requests r
  WHERE r.organization_id = v_org
    AND r.first_handled_at IS NOT NULL
    AND r.created_at >= v_start AND r.created_at < v_end
    AND (v_channel IS NULL OR r.channel = v_channel)
    AND (v_scope = 'org' OR r.created_by = v_actor);

  SELECT avg(extract(epoch FROM (coalesce(pr.verified_at, pr.updated_at) - pr.created_at)) / 3600.0),
         count(*)::int
  INTO v_avg_ver, v_n_ver
  FROM public.pre_reservations pr
  JOIN public.customer_requests r ON r.id = pr.request_id AND r.organization_id = pr.organization_id
  WHERE pr.organization_id = v_org
    AND pr.status = 'verified'::public.pre_reservation_status
    AND pr.created_at >= v_start AND pr.created_at < v_end
    AND (v_channel IS NULL OR r.channel = v_channel)
    AND (v_scope = 'org' OR pr.created_by = v_actor);

  SELECT avg(extract(epoch FROM (qv.issued_at - qv.created_at)) / 3600.0), count(*)::int
  INTO v_avg_q, v_n_q
  FROM public.quotation_versions qv
  JOIN public.quotation_families qf ON qf.id = qv.family_id AND qf.organization_id = qv.organization_id
  JOIN public.pre_reservations pr ON pr.id = qf.pre_reservation_id AND pr.organization_id = qv.organization_id
  JOIN public.customer_requests r ON r.id = pr.request_id AND r.organization_id = qv.organization_id
  WHERE qv.organization_id = v_org
    AND qv.issued_at IS NOT NULL
    AND qv.issued_at >= v_start AND qv.issued_at < v_end
    AND (v_channel IS NULL OR r.channel = v_channel)
    AND (v_scope = 'org' OR qv.created_by = v_actor);

  RETURN jsonb_build_object(
    'avg_request_response_hours', CASE WHEN v_n_req > 0 THEN round(v_avg_req, 2) ELSE NULL END,
    'avg_verification_hours', CASE WHEN v_n_ver > 0 THEN round(v_avg_ver, 2) ELSE NULL END,
    'avg_quotation_issue_hours', CASE WHEN v_n_q > 0 THEN round(v_avg_q, 2) ELSE NULL END,
    'sample_request', coalesce(v_n_req, 0),
    'sample_verification', coalesce(v_n_ver, 0),
    'sample_quotation', coalesce(v_n_q, 0)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.analytics_ops_times(date, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.analytics_ops_times(date, date, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.analytics_stale_queue()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_scope text;
  v_actor uuid := auth.uid();
  v_items jsonb;
BEGIN
  v_org := public.require_tenant_member();
  v_scope := public.analytics_scope();

  SELECT coalesce(jsonb_agg(x.obj ORDER BY x.age_hours DESC), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT jsonb_build_object(
      'kind', 'request',
      'id', r.id,
      'reference', r.reference,
      'age_hours', round((extract(epoch FROM (now() - r.created_at)) / 3600.0)::numeric, 1),
      'status', r.status::text
    ) AS obj,
    extract(epoch FROM (now() - r.created_at)) / 3600.0 AS age_hours
    FROM public.customer_requests r
    WHERE r.organization_id = v_org
      AND r.status IN ('received'::public.request_status, 'in_review'::public.request_status)
      AND r.created_at < now() - interval '24 hours'
      AND (v_scope = 'org' OR r.created_by = v_actor)
    UNION ALL
    SELECT jsonb_build_object(
      'kind', 'pre_reservation',
      'id', pr.id,
      'reference', pr.reference,
      'age_hours', round((extract(epoch FROM (now() - pr.created_at)) / 3600.0)::numeric, 1),
      'status', pr.status::text
    ),
    extract(epoch FROM (now() - pr.created_at)) / 3600.0
    FROM public.pre_reservations pr
    WHERE pr.organization_id = v_org
      AND pr.status NOT IN (
        'verified'::public.pre_reservation_status,
        'cancelled'::public.pre_reservation_status
      )
      AND pr.created_at < now() - interval '24 hours'
      AND (v_scope = 'org' OR pr.created_by = v_actor)
    ORDER BY 2 DESC
    LIMIT 50
  ) x;

  RETURN jsonb_build_object('items', v_items);
END;
$$;

REVOKE ALL ON FUNCTION public.analytics_stale_queue() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.analytics_stale_queue() TO authenticated;

CREATE OR REPLACE FUNCTION public.analytics_require_finance()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_role text := auth.jwt() ->> 'app_role';
BEGIN
  v_org := public.require_tenant_member();
  IF v_role NOT IN ('operator', 'admin') THEN
    RAISE EXCEPTION 'INSUFFICIENT_PERMISSIONS' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN v_org;
END;
$$;

REVOKE ALL ON FUNCTION public.analytics_require_finance() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.analytics_require_finance() FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.analytics_sales_summary(p_from date, p_to date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_start timestamptz;
  v_end timestamptz;
  v_rows jsonb;
BEGIN
  v_org := public.analytics_require_finance();
  SELECT b.range_start, b.range_end INTO v_start, v_end FROM public.analytics_bounds(p_from, p_to) b;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'currency', s.currency,
    'gross', s.gross,
    'cancelled', s.cancelled,
    'net', s.net,
    'paid_total', s.paid_total,
    'balance', s.balance
  ) ORDER BY s.currency), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      v.currency::text AS currency,
      coalesce(sum(v.total), 0)::numeric(14, 2) AS gross,
      coalesce(sum(v.total) FILTER (WHERE v.status = 'cancelled'::public.reservation_status), 0)::numeric(14, 2) AS cancelled,
      (coalesce(sum(v.total), 0)
        - coalesce(sum(v.total) FILTER (WHERE v.status = 'cancelled'::public.reservation_status), 0)
      )::numeric(14, 2) AS net,
      coalesce(sum(l.paid_total), 0)::numeric(14, 2) AS paid_total,
      coalesce(sum(l.balance), 0)::numeric(14, 2) AS balance
    FROM public.reservation_versions v
    JOIN public.reservation_families f ON f.id = v.family_id AND f.organization_id = v.organization_id
    LEFT JOIN public.reservation_list l ON l.version_id = v.id
    WHERE v.organization_id = v_org
      AND v.status <> 'superseded'::public.reservation_status
      AND f.created_at >= v_start AND f.created_at < v_end
    GROUP BY v.currency
  ) s;

  RETURN jsonb_build_object('currencies', v_rows);
END;
$$;

REVOKE ALL ON FUNCTION public.analytics_sales_summary(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.analytics_sales_summary(date, date) TO authenticated;

CREATE OR REPLACE FUNCTION public.analytics_product_ranking(p_from date, p_to date, p_limit int)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_org uuid;
  v_start timestamptz;
  v_end timestamptz;
  v_limit int := least(greatest(coalesce(p_limit, 20), 1), 100);
  v_rows jsonb;
BEGIN
  v_org := public.analytics_require_finance();
  SELECT b.range_start, b.range_end INTO v_start, v_end FROM public.analytics_bounds(p_from, p_to) b;

  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      i.product_id,
      i.item_label,
      i.item_kind,
      sum(i.adults + i.children)::int AS traveler_count,
      count(DISTINCT i.version_id)::int AS reservation_count,
      sum(i.line_total)::numeric(14, 2) AS revenue,
      v.currency::text AS currency
    FROM public.reservation_items i
    JOIN public.reservation_versions v ON v.id = i.version_id AND v.organization_id = i.organization_id
    JOIN public.reservation_families f ON f.id = v.family_id AND f.organization_id = i.organization_id
    WHERE i.organization_id = v_org
      AND v.status NOT IN (
        'superseded'::public.reservation_status,
        'cancelled'::public.reservation_status
      )
      AND f.created_at >= v_start AND f.created_at < v_end
    GROUP BY i.product_id, i.item_label, i.item_kind, v.currency
    ORDER BY sum(i.line_total) DESC, sum(i.adults + i.children) DESC
    LIMIT v_limit
  ) t;

  RETURN jsonb_build_object('rows', v_rows);
END;
$$;

REVOKE ALL ON FUNCTION public.analytics_product_ranking(date, date, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.analytics_product_ranking(date, date, int) TO authenticated;
