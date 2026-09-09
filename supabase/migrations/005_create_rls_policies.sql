-- 005_create_rls_policies.sql
-- Multi-tenant isolation enforced in the database, so a defect in application code cannot
-- leak data across organizations.
-- Source of truth: specs/001-auth-tenant-access/data-model.md ("RLS Policies Overview").
--
-- CLAIM NAMING (deviation from data-model.md, see docs/adr/0002-jwt-app-role-claim.md):
-- the application role travels in the `app_role` claim, not `role`. PostgREST reserves
-- `role` to choose the PostgreSQL role for the request (SET ROLE), so overwriting it with
-- 'admin' | 'operator' | 'agent' would make every authenticated request fail.
--
-- Every policy is scoped `TO authenticated`. `anon` matches no policy and therefore reads
-- nothing: Default Deny holds for unauthenticated callers. Likewise, a session whose JWT
-- carries no `organization_id` yields NULL on the comparison, which is not TRUE, so it is
-- denied. Operations without a policy below (INSERT/DELETE on organizations, DELETE on
-- user_profiles) are denied outright and must go through SECURITY DEFINER functions.

-- ---------------------------------------------------------------------------
-- organizations
-- ---------------------------------------------------------------------------

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

-- A collaborator sees only their own agency.
CREATE POLICY tenant_isolation_select ON public.organizations
  FOR SELECT
  TO authenticated
  USING (id = (auth.jwt() ->> 'organization_id')::uuid);

-- Only an administrator may modify their own agency, and cannot repoint it to another one.
CREATE POLICY tenant_isolation_update ON public.organizations
  FOR UPDATE
  TO authenticated
  USING (
    id = (auth.jwt() ->> 'organization_id')::uuid
    AND (auth.jwt() ->> 'app_role') = 'admin'
  )
  WITH CHECK (
    id = (auth.jwt() ->> 'organization_id')::uuid
    AND (auth.jwt() ->> 'app_role') = 'admin'
  );

-- ---------------------------------------------------------------------------
-- user_profiles
-- ---------------------------------------------------------------------------

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- Collaborators see the roster of their own agency only.
CREATE POLICY tenant_isolation_select ON public.user_profiles
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'organization_id')::uuid);

CREATE POLICY admin_insert ON public.user_profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() ->> 'app_role') = 'admin'
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

-- USING and WITH CHECK both pin the tenant, so an admin can neither reach into another
-- agency nor move a collaborator out of their own.
CREATE POLICY admin_update ON public.user_profiles
  FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'app_role') = 'admin'
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  )
  WITH CHECK (
    (auth.jwt() ->> 'app_role') = 'admin'
    AND organization_id = (auth.jwt() ->> 'organization_id')::uuid
  );

-- Row-level permission for a collaborator to maintain their own session bookkeeping.
-- RLS cannot express "only these columns", so the column whitelist (last_activity_at,
-- must_change_password) is enforced by trigger enforce_user_profile_update_scope in
-- migration 007. Without it this policy would let any collaborator promote themselves.
CREATE POLICY self_update ON public.user_profiles
  FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- ---------------------------------------------------------------------------
-- audit.audit_events
-- ---------------------------------------------------------------------------

ALTER TABLE audit.audit_events ENABLE ROW LEVEL SECURITY;

-- Administrators read their own agency's log; operators and agents read nothing.
CREATE POLICY admin_select ON audit.audit_events
  FOR SELECT
  TO authenticated
  USING (
    organization_id = (auth.jwt() ->> 'organization_id')::uuid
    AND (auth.jwt() ->> 'app_role') = 'admin'
  );

-- Events are written by SECURITY DEFINER triggers and functions (migration 007), which run
-- as the table owner and bypass RLS. This policy covers the service role only; `authenticated`
-- has no INSERT privilege at all (migration 004), so no browser session can forge an event.
CREATE POLICY system_insert ON audit.audit_events
  FOR INSERT
  TO service_role
  WITH CHECK (true);

-- No UPDATE or DELETE policy exists for any role, and the immutability trigger in
-- migration 007 rejects those operations even for privileged connections.
