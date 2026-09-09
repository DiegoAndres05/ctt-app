-- 006_create_auth_hook.sql
-- Supabase Auth Hook: "Customize Access Token (JWT) Claims".
-- Runs inside the database every time an access token is issued or refreshed, so the tenant
-- and role travel in the JWT itself and RLS never needs a lookup join.
-- Source of truth: specs/001-auth-tenant-access/data-model.md ("Auth Hook: Custom JWT Claims").
--
-- CLAIM NAMING (deviation from data-model.md, see docs/adr/0002-jwt-app-role-claim.md):
-- the application role is written to `app_role`. `role` is reserved: PostgREST reads it to
-- decide which PostgreSQL role to SET ROLE to, and 'admin' | 'operator' | 'agent' are not
-- database roles, so writing there would break every authenticated request.
--
-- Only profiles with status = 'active' receive claims. A deactivated collaborator therefore
-- gets a token with no organization_id, which matches no RLS policy: deactivation takes
-- effect on the next token issuance without any extra revocation machinery.

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  claims jsonb;
  user_org_id uuid;
  user_role text;
BEGIN
  SELECT organization_id, role::text
  INTO user_org_id, user_role
  FROM public.user_profiles
  WHERE id = (event->>'user_id')::uuid
    AND status = 'active';

  claims := event->'claims';

  IF user_org_id IS NOT NULL THEN
    claims := jsonb_set(claims, '{organization_id}', to_jsonb(user_org_id::text));
    claims := jsonb_set(claims, '{app_role}', to_jsonb(user_role));
  END IF;

  event := jsonb_set(event, '{claims}', claims);
  RETURN event;
END;
$$;

COMMENT ON FUNCTION public.custom_access_token_hook(jsonb) IS
  'Auth hook: injects organization_id and app_role claims for active collaborators.';

-- Supabase Auth invokes the hook as supabase_auth_admin; nobody else may call it.
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) FROM authenticated, anon, PUBLIC;
