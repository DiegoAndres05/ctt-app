-- 008_us1_auth_functions.sql
-- User Story 1: mandatory credential rotation and per-account lockout, both enforced by the
-- database so that no browser-side code participates in the decision.
-- Source of truth: specs/001-auth-tenant-access/spec.md (FR-001, FR-005, FR-006, FR-007),
-- specs/001-auth-tenant-access/research.md (R-007, R-010),
-- specs/001-auth-tenant-access/contracts/api-contracts.md ("change_password").
-- Design rationale: docs/adr/0003-server-side-credential-and-lockout-enforcement.md.
--
-- ERROR CONTRACT: the RPCs below raise the API contract's error code as the exception message
-- (SQLSTATE P0001). The frontend maps `error.message` back to an `AuthErrorCode`
-- (src/app/core/error/error-handler.ts). Messages are therefore part of the API contract and
-- must not be reworded.
--
-- CLAIM NAMING: the application role travels in `app_role`, never in the reserved `role`
-- claim. See docs/adr/0002-jwt-app-role-claim.md.

-- ---------------------------------------------------------------------------
-- 1. Close the must_change_password self-update hole
-- ---------------------------------------------------------------------------

-- Migration 007 allowed a collaborator to write must_change_password on their own profile,
-- which let them clear the mandatory-change flag while still holding the temporary password
-- an administrator handed them. From here the flag is cleared in exactly one place:
-- public.change_password below, which only clears it after proving knowledge of the current
-- password and replacing it.
--
-- last_activity_at remains self-writable: it is the collaborator's own session bookkeeping
-- (T024) and carries no authority.
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

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.full_name IS DISTINCT FROM OLD.full_name
     OR NEW.email IS DISTINCT FROM OLD.email
     OR NEW.role IS DISTINCT FROM OLD.role
     OR NEW.status IS DISTINCT FROM OLD.status
     OR NEW.must_change_password IS DISTINCT FROM OLD.must_change_password
     OR NEW.failed_login_attempts IS DISTINCT FROM OLD.failed_login_attempts
     OR NEW.locked_until IS DISTINCT FROM OLD.locked_until
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION
      'A collaborator may only update last_activity_at on their own profile.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_user_profile_update_scope() IS
  'Column whitelist for a collaborator self-update: last_activity_at only. RLS cannot restrict columns.';

-- ---------------------------------------------------------------------------
-- 2. password_changed is now emitted by change_password, not inferred from the flag
-- ---------------------------------------------------------------------------

-- With the whitelist above in force, must_change_password can only move true -> false through
-- change_password (which logs the event itself) or through an administrator's direct update,
-- which is not a password change at all. Inferring `password_changed` from the flag would
-- therefore either duplicate the event or attribute a rotation that never happened.
-- The false -> true direction still means "an administrator forced a new temporary password",
-- so `password_reset_forced` stays.
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

-- ---------------------------------------------------------------------------
-- 3. change_password
-- ---------------------------------------------------------------------------

-- Rotates the caller's own password and clears the mandatory-change flag as one transaction,
-- so the flag can never be cleared without the credential actually changing (FR-006).
--
-- The new hash is produced with bcrypt through pgcrypto, the same algorithm and column
-- Supabase Auth uses (auth.users.encrypted_password), so credentials remain in Supabase Auth's
-- store and no plaintext is ever persisted or logged (FR-007). Doing this in the database
-- rather than through the Auth API is what makes the whole operation atomic; see ADR-0003.
CREATE OR REPLACE FUNCTION public.change_password(
  p_current_password text,
  p_new_password text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  -- bcrypt hashes at most 72 bytes; anything beyond that is silently ignored, so a longer
  -- password would be weaker than it looks.
  c_max_password_bytes constant integer := 72;
  c_min_password_length constant integer := 8;

  v_user_id uuid := auth.uid();
  v_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  v_organization_id uuid;
  v_stored_hash text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'SESSION_EXPIRED' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT organization_id INTO v_organization_id
  FROM public.user_profiles
  WHERE id = v_user_id
    AND status = 'active';

  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'ACCOUNT_INACTIVE' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT encrypted_password INTO v_stored_hash
  FROM auth.users
  WHERE id = v_user_id;

  IF v_stored_hash IS NULL
     OR v_stored_hash <> extensions.crypt(p_current_password, v_stored_hash)
  THEN
    -- Not audited: the RAISE rolls the transaction back, which would discard the audit row
    -- anyway, and FR-005 scopes auditing to authentication attempts rather than failed
    -- rotations. A wrong current password still shows up as a failed login attempt upstream.
    RAISE EXCEPTION 'INVALID_CURRENT_PASSWORD' USING ERRCODE = 'raise_exception';
  END IF;

  IF p_new_password IS NULL
     OR char_length(p_new_password) < c_min_password_length
     OR octet_length(p_new_password) > c_max_password_bytes
  THEN
    RAISE EXCEPTION 'WEAK_PASSWORD' USING ERRCODE = 'raise_exception';
  END IF;

  -- The point of the mandatory change is to retire the temporary password. Re-submitting it
  -- would clear the flag while leaving the shared credential in place.
  IF p_new_password = p_current_password THEN
    RAISE EXCEPTION 'PASSWORD_UNCHANGED' USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE auth.users
  SET encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
      updated_at = now()
  WHERE id = v_user_id;

  UPDATE public.user_profiles
  SET must_change_password = false,
      failed_login_attempts = 0,
      locked_until = NULL,
      last_activity_at = now()
  WHERE id = v_user_id;

  -- Every other session of this user was authenticated with the retired password.
  -- A missing session_id claim means the caller's own session cannot be identified, so all
  -- sessions go: failing closed is the safe direction.
  DELETE FROM auth.sessions
  WHERE user_id = v_user_id
    AND (v_session_id IS NULL OR id <> v_session_id);

  PERFORM audit.log_event(
    p_organization_id => v_organization_id,
    p_event_type      => 'password_changed',
    p_result          => 'success',
    p_actor_id        => v_user_id,
    p_resource_type   => 'user_profile',
    p_resource_id     => v_user_id
  );

  RETURN jsonb_build_object('must_change_password', false);
END;
$$;

COMMENT ON FUNCTION public.change_password(text, text) IS
  'Rotates the caller''s own password and clears must_change_password atomically. Never logs password material.';

REVOKE EXECUTE ON FUNCTION public.change_password(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.change_password(text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. Failed-login accounting and temporary lockout
-- ---------------------------------------------------------------------------

-- Supabase Auth Hook: "Password Verification Attempt". Supabase Auth calls this after
-- comparing the submitted password against the stored hash, passing
-- {"user_id": uuid, "valid": boolean}, and honours the returned decision.
--
-- Running the counter here rather than in an RPC is what makes it trustworthy: the hook is
-- invoked by supabase_auth_admin as part of the sign-in flow, so the counter can only advance
-- on a real verification attempt and the browser has no way to reach it. See ADR-0003.
--
-- Threshold and lock duration come from research.md R-010.
CREATE OR REPLACE FUNCTION public.password_verification_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  c_max_failed_attempts constant integer := 5;
  c_lock_duration constant interval := interval '15 minutes';

  -- Deliberately uniform for a locked account and an inactive one: the wording must not help
  -- an attacker tell the two apart, and the sentinel prefix is what the client maps to an
  -- error code (src/app/core/error/error-handler.ts).
  c_locked_message constant text :=
    'ACCOUNT_LOCKED: la cuenta está bloqueada temporalmente. Inténtalo más tarde.';
  c_inactive_message constant text :=
    'ACCOUNT_INACTIVE: la cuenta está desactivada. Contacta a un administrador.';

  v_user_id uuid := nullif(event ->> 'user_id', '')::uuid;
  v_valid boolean := coalesce((event ->> 'valid')::boolean, false);
  v_profile public.user_profiles;
  v_attempts integer;
  v_locked_until timestamptz;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('decision', 'continue');
  END IF;

  SELECT * INTO v_profile
  FROM public.user_profiles
  WHERE id = v_user_id;

  -- No profile means no tenant claim will be issued either (migration 006), so the session
  -- would reach no data. Nothing to account for here.
  IF NOT FOUND THEN
    RETURN jsonb_build_object('decision', 'continue');
  END IF;

  -- A live lock rejects even a correct password, which is the whole point of the control.
  IF v_profile.locked_until IS NOT NULL AND v_profile.locked_until > now() THEN
    PERFORM audit.log_event(
      p_organization_id => v_profile.organization_id,
      p_event_type      => 'login_failure',
      p_result          => 'failure',
      p_actor_id        => v_user_id,
      p_resource_type   => 'user_profile',
      p_resource_id     => v_user_id,
      p_metadata        => jsonb_build_object('reason', 'ACCOUNT_LOCKED',
                                              'locked_until', v_profile.locked_until)
    );
    RETURN jsonb_build_object(
      'decision', 'reject',
      'message', c_locked_message,
      'should_logout_user', true
    );
  END IF;

  -- The lock has run its course. Clearing it here emits `account_unlocked` through the
  -- trigger installed in migration 007.
  IF v_profile.locked_until IS NOT NULL THEN
    UPDATE public.user_profiles
    SET failed_login_attempts = 0,
        locked_until = NULL
    WHERE id = v_user_id;

    v_profile.failed_login_attempts := 0;
    v_profile.locked_until := NULL;
  END IF;

  IF NOT v_valid THEN
    UPDATE public.user_profiles
    SET failed_login_attempts = failed_login_attempts + 1,
        locked_until = CASE
                         WHEN failed_login_attempts + 1 >= c_max_failed_attempts
                           THEN now() + c_lock_duration
                       END
    WHERE id = v_user_id
    RETURNING failed_login_attempts, locked_until
    INTO v_attempts, v_locked_until;

    PERFORM audit.log_event(
      p_organization_id => v_profile.organization_id,
      p_event_type      => 'login_failure',
      p_result          => 'failure',
      p_actor_id        => v_user_id,
      p_resource_type   => 'user_profile',
      p_resource_id     => v_user_id,
      p_metadata        => jsonb_build_object('reason', 'INVALID_CREDENTIALS',
                                              'failed_login_attempts', v_attempts)
    );

    IF v_locked_until IS NOT NULL THEN
      RETURN jsonb_build_object(
        'decision', 'reject',
        'message', c_locked_message,
        'should_logout_user', true
      );
    END IF;

    -- Supabase Auth rejects the wrong password on its own; `continue` keeps the response
    -- indistinguishable from any other failed attempt.
    RETURN jsonb_build_object('decision', 'continue');
  END IF;

  -- From here the password was correct.

  -- Naming the deactivation is only safe once the password has been proven: it tells the
  -- legitimate owner why they cannot get in without leaking anything to a guesser.
  IF v_profile.status <> 'active' THEN
    PERFORM audit.log_event(
      p_organization_id => v_profile.organization_id,
      p_event_type      => 'login_failure',
      p_result          => 'failure',
      p_actor_id        => v_user_id,
      p_resource_type   => 'user_profile',
      p_resource_id     => v_user_id,
      p_metadata        => jsonb_build_object('reason', 'ACCOUNT_INACTIVE')
    );
    RETURN jsonb_build_object(
      'decision', 'reject',
      'message', c_inactive_message,
      'should_logout_user', true
    );
  END IF;

  UPDATE public.user_profiles
  SET failed_login_attempts = 0,
      locked_until = NULL,
      last_activity_at = now()
  WHERE id = v_user_id;

  PERFORM audit.log_event(
    p_organization_id => v_profile.organization_id,
    p_event_type      => 'login_success',
    p_result          => 'success',
    p_actor_id        => v_user_id,
    p_resource_type   => 'user_profile',
    p_resource_id     => v_user_id
  );

  RETURN jsonb_build_object('decision', 'continue');
END;
$$;

COMMENT ON FUNCTION public.password_verification_hook(jsonb) IS
  'Auth hook: per-account failed-login accounting, 15-minute lockout after 5 attempts, and login auditing.';

-- Same privilege shape as the access-token hook (migration 006): only Supabase Auth may call it.
GRANT EXECUTE ON FUNCTION public.password_verification_hook(jsonb) TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.password_verification_hook(jsonb)
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Session termination auditing
-- ---------------------------------------------------------------------------

-- Sign-out and session expiry are decided in the browser (FR-001 timeouts, R-005), but
-- `authenticated` holds no INSERT privilege on the audit log, so the event has to be recorded
-- through a definer function. The reason is whitelisted and the actor is always taken from the
-- token, so a caller can only ever record one of two facts about their own session.
CREATE OR REPLACE FUNCTION public.record_session_end(p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_organization_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'SESSION_EXPIRED' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_reason IS NULL OR p_reason NOT IN ('logout', 'session_expired') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR' USING ERRCODE = 'raise_exception';
  END IF;

  SELECT organization_id INTO v_organization_id
  FROM public.user_profiles
  WHERE id = v_user_id;

  IF v_organization_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM audit.log_event(
    p_organization_id => v_organization_id,
    p_event_type      => p_reason::audit.audit_event_type,
    p_result          => 'success',
    p_actor_id        => v_user_id,
    p_resource_type   => 'user_profile',
    p_resource_id     => v_user_id
  );
END;
$$;

COMMENT ON FUNCTION public.record_session_end(text) IS
  'Records a logout or session_expired event for the calling session. Reason is whitelisted.';

REVOKE EXECUTE ON FUNCTION public.record_session_end(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_session_end(text) TO authenticated;
