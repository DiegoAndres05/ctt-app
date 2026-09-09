-- 015_create_product_subtypes.sql
-- 1:1 subtype tables sharing products.id. organization_id is denormalized for RLS.
-- Source of truth: specs/002-catalog-pricing/data-model.md ("2. Experience", "3. Accommodation").

CREATE TABLE public.experiences (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  duration_minutes integer NOT NULL,
  difficulty public.experience_difficulty,
  meeting_point text,
  min_capacity integer NOT NULL,
  max_capacity integer NOT NULL,
  CONSTRAINT experiences_product_tenant_fkey
    FOREIGN KEY (id, organization_id)
    REFERENCES public.products (id, organization_id)
    ON DELETE CASCADE,
  CONSTRAINT experiences_duration_positive CHECK (duration_minutes > 0),
  CONSTRAINT experiences_min_capacity_positive CHECK (min_capacity >= 1),
  CONSTRAINT experiences_max_gte_min CHECK (max_capacity >= min_capacity)
);

COMMENT ON TABLE public.experiences IS
  'Experience-specific attributes. Primary key is the parent products.id.';

CREATE INDEX experiences_organization_id_idx ON public.experiences (organization_id);

ALTER TABLE public.experiences ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.experiences FROM anon;

CREATE POLICY tenant_isolation_select ON public.experiences
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_insert ON public.experiences
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY operator_update ON public.experiences
  FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  )
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE TABLE public.accommodations (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  property_type text NOT NULL,
  location text NOT NULL,
  check_in time,
  check_out time,
  max_occupancy integer NOT NULL,
  occupancy_rules jsonb,
  CONSTRAINT accommodations_product_tenant_fkey
    FOREIGN KEY (id, organization_id)
    REFERENCES public.products (id, organization_id)
    ON DELETE CASCADE,
  CONSTRAINT accommodations_property_type_not_blank CHECK (btrim(property_type) <> ''),
  CONSTRAINT accommodations_location_not_blank CHECK (btrim(location) <> ''),
  CONSTRAINT accommodations_max_occupancy_positive CHECK (max_occupancy >= 1)
);

COMMENT ON TABLE public.accommodations IS
  'Accommodation-specific attributes. Primary key is the parent products.id.';

CREATE INDEX accommodations_organization_id_idx ON public.accommodations (organization_id);

ALTER TABLE public.accommodations ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.accommodations FROM anon;

CREATE POLICY tenant_isolation_select ON public.accommodations
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY operator_insert ON public.accommodations
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

CREATE POLICY operator_update ON public.accommodations
  FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  )
  WITH CHECK (
    (auth.jwt() ->> 'app_role') IN ('operator', 'admin')
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );
