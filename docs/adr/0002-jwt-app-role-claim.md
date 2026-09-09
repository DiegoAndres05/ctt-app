# ADR-0002: Uso del claim `app_role` en lugar de `role` en el JWT

- **Identifier**: ADR-0002
- **Title**: El rol de aplicación viaja en el claim `app_role`, no en `role`
- **Status**: Accepted
- **Date**: 2026-09-08
- **Deciders**: Equipo de Arquitectura
- **Affected Chapters**: Cap. 8 (Security Principles), Cap. 10 (Multi-Tenant Readiness)
- **Affected Specs**: `specs/001-auth-tenant-access/data-model.md`

## Context

`data-model.md` especificaba que el Auth Hook `custom_access_token_hook` inyectara el rol de
aplicación en el claim `role` del JWT, y que las políticas RLS lo leyeran con
`(auth.jwt() ->> 'role')`.

`role` es un claim **reservado** en la plataforma Supabase. PostgREST lo interpreta como el
rol de PostgreSQL bajo el cual debe ejecutar la petición y emite `SET ROLE <valor>`. Los
valores válidos son `anon`, `authenticated` y `service_role`; `admin`, `operator` y `agent`
no existen como roles de base de datos.

Implementar la especificación literalmente produce que **toda** petición autenticada falle
con `role "admin" does not exist`, dejando inutilizables el aislamiento multi-tenant, la
gestión de usuarios y la consulta de auditoría. Además, Supabase Auth valida que los claims
requeridos (`iss`, `aud`, `exp`, `iat`, `sub`, `role`, `aal`, `session_id`, `email`, `phone`,
`is_anonymous`) estén presentes y bien formados tras ejecutar el hook.

La documentación oficial de Supabase (*Custom Claims & Role-based Access Control*) resuelve
exactamente este problema usando un claim propio (`user_role` en sus ejemplos) y preservando
`role` intacto.

Se trata de un defecto de especificación con impacto en seguridad y en corrección funcional,
no de una preferencia de implementación, por lo que se resuelve actualizando la especificación
en lugar de aplicar un workaround en el código (Cap. 3, *Conflict Resolution*).

## Decision

El rol de aplicación se transporta en el claim **`app_role`**. El claim `role` conserva el
valor que emite Supabase Auth (`authenticated`).

- Auth Hook (`supabase/migrations/006_create_auth_hook.sql`):
  `claims := jsonb_set(claims, '{app_role}', to_jsonb(user_role));`
- Políticas RLS (`supabase/migrations/005_create_rls_policies.sql`):
  `(auth.jwt() ->> 'app_role') = 'admin'`
- Frontend: constante `APP_ROLE_CLAIM` en `src/app/core/auth/models/auth.model.ts`.

Se elige `app_role` sobre `user_role` porque coincide con el nombre del enum de dominio
`public.app_role`, preservando el lenguaje ubicuo (Cap. 6).

El claim `organization_id` no presenta conflicto y se mantiene sin cambios.

## Alternatives considered

- **Mantener `role` según la especificación**: Descartado. Rompe toda petición autenticada;
  viola el atributo de calidad de mayor prioridad (Correctness) y el principio *Secure by
  Default*.
- **Crear roles de PostgreSQL `admin`, `operator` y `agent`**: Descartado. Obliga a otorgarlos
  a `authenticator`, multiplica la superficie de privilegios de base de datos y complica las
  políticas RLS, contraviniendo *Least Privilege* y *Simplicity Over Complexity*.
- **Anidar el rol en `app_metadata.app_role`**: Descartado. Añade un nivel de indirección en
  cada política RLS sin beneficio de seguridad, ya que el claim de primer nivel también es
  inyectado server-side y no es modificable por el cliente.
- **Usar `user_role`** (nombre de los ejemplos de Supabase): Descartado por consistencia con
  el enum de dominio `app_role`.

## Consequences

**Positivas**
- Las peticiones autenticadas funcionan y las políticas RLS pueden evaluar el rol.
- Se preserva el contrato de claims requeridos por Supabase Auth.
- El nombre del claim coincide con el enum de dominio.

**Negativas / Riesgos**
- Divergencia respecto a la redacción original de `data-model.md`; se actualiza dicho
  documento junto con este ADR.
- Cualquier consulta o política escrita a mano contra `auth.jwt() ->> 'role'` obtendrá
  `authenticated` y evaluará siempre a falso. Las revisiones de seguridad deben buscar ese
  patrón.

**Seguimiento**
- Los tests de aislamiento RLS (T030) deben cubrir explícitamente que una sesión sin claim
  `organization_id` no accede a ningún dato.
