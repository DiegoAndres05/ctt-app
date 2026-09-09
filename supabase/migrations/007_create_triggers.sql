-- 007_create_triggers.sql
-- Database-level guarantees that do not depend on the application layer:
--   1. updated_at maintenance
--   2. audit log immutability
--   3. column scope of a collaborator's self-update
--   4. automatic capture of security events
-- Source of truth: specs/001-auth-tenant-access/data-model.md.

-- ---------------------------------------------------------------------------
-- 1. updated_at maintenance
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER organizations_set_updated_at
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER user_profiles_set_updated_at
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. Audit log immutability
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION audit.reject_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'Audit logs are immutable and cannot be modified or deleted.'
    USING ERRCODE = 'insufficient_privilege';
END;
$$;

COMMENT ON FUNCTION audit.reject_audit_mutation() IS
  'Rejects any attempt to rewrite audit history. Fires for every role, including the table owner.';

CREATE TRIGGER audit_events_reject_mutation
  BEFORE UPDATE OR DELETE ON audit.audit_events
  FOR EACH ROW
  EXECUTE FUNCTION audit.reject_audit_mutation();

CREATE TRIGGER audit_events_reject_truncate
  BEFORE TRUNCATE ON audit.audit_events
  FOR EACH STATEMENT
  EXECUTE FUNCTION audit.reject_audit_mutation();

-- ---------------------------------------------------------------------------
-- 3. Column scope of a collaborator's self-update
-- ---------------------------------------------------------------------------

-- The self_update RLS policy (migration 005) grants row access but cannot restrict columns.
-- Without this guard a collaborator could set their own role to 'admin'.
--
-- SECURITY INVOKER on purpose: current_user is what distinguishes a direct PostgREST update
-- ('authenticated') from a SECURITY DEFINER routine or the service role, which run as another
-- database role and enforce their own authorization.
CREATE OR REPLACE FUNCTION public.enforce_user_profile_update_scope()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF current_user <> 'authenticated' THEN
    RETURN NEW;
  END IF;

  IF (auth.jwt() ->> 'app_role') = 'admin'
     AND OLD.organization_id = (auth.jwt() ->> 'organization_id')::uuid
  THEN
    RETURN NEW;
  END IF;

  -- SECURITY NOTE: must_change_password is writable here because data-model.md lists it as a
  -- permitted self-update field. That lets a collaborator clear the flag without actually
  -- rotating the temporary password. Closing it means routing the change through the
  -- change_password SECURITY DEFINER function (T020) and dropping the column from this list.
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.full_name IS DISTINCT FROM OLD.full_name
     OR NEW.email IS DISTINCT FROM OLD.email
     OR NEW.role IS DISTINCT FROM OLD.role
     OR NEW.status IS DISTINCT FROM OLD.status
     OR NEW.failed_login_attempts IS DISTINCT FROM OLD.failed_login_attempts
     OR NEW.locked_until IS DISTINCT FROM OLD.locked_until
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION
      'A collaborator may only update last_activity_at and must_change_password on their own profile.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER user_profiles_enforce_update_scope
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_user_profile_update_scope();

-- ---------------------------------------------------------------------------
-- 4. Automatic capture of security events
-- ---------------------------------------------------------------------------

-- Single write path into the audit log. SECURITY DEFINER so that capture triggers running
-- under `authenticated` (which holds no INSERT privilege on audit.audit_events) can record.
CREATE OR REPLACE FUNCTION audit.log_event(
  p_organization_id uuid,
  p_event_type audit.audit_event_type,
  p_result audit.audit_result,
  p_actor_id uuid DEFAULT NULL,
  p_resource_type text DEFAULT NULL,
  p_resource_id uuid DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_event_id bigint;
  v_actor_id uuid;
  v_headers jsonb;
  v_ip inet;
  v_user_agent text;
BEGIN
  -- actor_id is a foreign key, so an unknown actor is recorded as a system event rather than
  -- aborting the business transaction that triggered the audit write.
  SELECT p.id INTO v_actor_id
  FROM public.user_profiles p
  WHERE p.id = coalesce(p_actor_id, auth.uid());

  -- Request headers are only present when the statement arrives through PostgREST.
  BEGIN
    v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
    v_ip := nullif(split_part(v_headers ->> 'x-forwarded-for', ',', 1), '')::inet;
    v_user_agent := v_headers ->> 'user-agent';
  EXCEPTION WHEN others THEN
    v_headers := NULL;
    v_ip := NULL;
    v_user_agent := NULL;
  END;

  INSERT INTO audit.audit_events (
    organization_id, actor_id, event_type, resource_type, resource_id,
    result, metadata, ip_address, user_agent
  )
  VALUES (
    p_organization_id, v_actor_id, p_event_type, p_resource_type, p_resource_id,
    p_result, coalesce(p_metadata, '{}'::jsonb), v_ip, v_user_agent
  )
  RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$$;

COMMENT ON FUNCTION audit.log_event IS
  'Only supported way to append to the audit log. Never pass credentials or secrets in p_metadata.';

REVOKE EXECUTE ON FUNCTION audit.log_event FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION audit.log_event TO service_role;

-- Organization provisioning.
CREATE OR REPLACE FUNCTION public.audit_organization_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM audit.log_event(
    p_organization_id => NEW.id,
    p_event_type      => 'organization_created',
    p_result          => 'success',
    p_resource_type   => 'organization',
    p_resource_id     => NEW.id,
    p_metadata        => jsonb_build_object('name', NEW.name, 'slug', NEW.slug)
  );
  RETURN NULL;
END;
$$;

CREATE TRIGGER organizations_audit_created
  AFTER INSERT ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_organization_created();

-- Collaborator provisioning.
CREATE OR REPLACE FUNCTION public.audit_user_profile_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM audit.log_event(
    p_organization_id => NEW.organization_id,
    p_event_type      => 'user_created',
    p_result          => 'success',
    p_resource_type   => 'user_profile',
    p_resource_id     => NEW.id,
    p_metadata        => jsonb_build_object('email', NEW.email, 'role', NEW.role)
  );
  RETURN NULL;
END;
$$;

CREATE TRIGGER user_profiles_audit_created
  AFTER INSERT ON public.user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_user_profile_created();

-- Collaborator lifecycle. One update may carry several independent facts, so each detected
-- change is recorded as its own event.
CREATE OR REPLACE FUNCTION public.audit_user_profile_changed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    PERFORM audit.log_event(
      p_organization_id => NEW.organization_id,
      p_event_type      => 'role_changed',
      p_result          => 'success',
      p_resource_type   => 'user_profile',
      p_resource_id     => NEW.id,
      p_metadata        => jsonb_build_object('from', OLD.role, 'to', NEW.role)
    );
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    PERFORM audit.log_event(
      p_organization_id => NEW.organization_id,
      p_event_type      => CASE NEW.status
                             WHEN 'active' THEN 'user_activated'::audit.audit_event_type
                             ELSE 'user_deactivated'::audit.audit_event_type
                           END,
      p_result          => 'success',
      p_resource_type   => 'user_profile',
      p_resource_id     => NEW.id,
      p_metadata        => jsonb_build_object('from', OLD.status, 'to', NEW.status)
    );
  END IF;

  IF OLD.must_change_password AND NOT NEW.must_change_password THEN
    PERFORM audit.log_event(
      p_organization_id => NEW.organization_id,
      p_event_type      => 'password_changed',
      p_result          => 'success',
      p_resource_type   => 'user_profile',
      p_resource_id     => NEW.id
    );
  END IF;

  IF NOT OLD.must_change_password AND NEW.must_change_password THEN
    PERFORM audit.log_event(
      p_organization_id => NEW.organization_id,
      p_event_type      => 'password_reset_forced',
      p_result          => 'success',
      p_resource_type   => 'user_profile',
      p_resource_id     => NEW.id
    );
  END IF;

  IF NEW.locked_until IS DISTINCT FROM OLD.locked_until THEN
    IF NEW.locked_until IS NOT NULL AND NEW.locked_until > now() THEN
      PERFORM audit.log_event(
        p_organization_id => NEW.organization_id,
        p_event_type      => 'account_locked',
        p_result          => 'success',
        p_resource_type   => 'user_profile',
        p_resource_id     => NEW.id,
        p_metadata        => jsonb_build_object(
                               'locked_until', NEW.locked_until,
                               'failed_login_attempts', NEW.failed_login_attempts
                             )
      );
    ELSIF OLD.locked_until IS NOT NULL THEN
      PERFORM audit.log_event(
        p_organization_id => NEW.organization_id,
        p_event_type      => 'account_unlocked',
        p_result          => 'success',
        p_resource_type   => 'user_profile',
        p_resource_id     => NEW.id
      );
    END IF;
  END IF;

  -- Descriptive attributes: no dedicated event type exists for them.
  IF NEW.full_name IS DISTINCT FROM OLD.full_name OR NEW.email IS DISTINCT FROM OLD.email THEN
    PERFORM audit.log_event(
      p_organization_id => NEW.organization_id,
      p_event_type      => 'user_updated',
      p_result          => 'success',
      p_resource_type   => 'user_profile',
      p_resource_id     => NEW.id,
      p_metadata        => jsonb_strip_nulls(jsonb_build_object(
                             'full_name_changed', NEW.full_name IS DISTINCT FROM OLD.full_name,
                             'email_changed', NEW.email IS DISTINCT FROM OLD.email
                           ))
    );
  END IF;

  RETURN NULL;
END;
$$;

-- last_activity_at alone must not produce audit noise: every authenticated request touches it.
CREATE TRIGGER user_profiles_audit_changed
  AFTER UPDATE ON public.user_profiles
  FOR EACH ROW
  WHEN (
    OLD.role IS DISTINCT FROM NEW.role
    OR OLD.status IS DISTINCT FROM NEW.status
    OR OLD.must_change_password IS DISTINCT FROM NEW.must_change_password
    OR OLD.locked_until IS DISTINCT FROM NEW.locked_until
    OR OLD.full_name IS DISTINCT FROM NEW.full_name
    OR OLD.email IS DISTINCT FROM NEW.email
  )
  EXECUTE FUNCTION public.audit_user_profile_changed();
