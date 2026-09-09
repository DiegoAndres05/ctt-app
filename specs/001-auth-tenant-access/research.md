# Research: 001-auth-tenant-access

**Date**: 2026-09-08 | **Spec**: [spec.md](./spec.md)

---

## R-001: Estrategia de Autenticación

**Decision**: Supabase Auth con email/password para usuarios internos.

**Rationale**:
- La Constitución establece Supabase como servicio de autenticación oficial.
- Supabase Auth maneja de forma nativa: hash de contraseñas (bcrypt), gestión de sesiones JWT, refresh tokens y expiración configurable.
- Soporta `onAuthStateChange` para integración reactiva con Angular Signals.
- Elimina la necesidad de implementar lógica criptográfica propia (cumple FR-007).

**Alternatives considered**:
- Auth0/Firebase Auth: Descartado por violar el principio de consistencia y añadir dependencia externa innecesaria.
- Implementación custom JWT: Descartado por complejidad, riesgo de seguridad y violación del principio de simplicidad.

---

## R-002: Estrategia de Multi-Tenancy

**Decision**: Shared Database, Shared Schema con columna `organization_id` en todas las tablas de negocio + Row Level Security (RLS).

**Rationale**:
- La Constitución exige aislamiento multi-tenant desde el día cero.
- El modelo shared-schema con `organization_id` es el más costo-efectivo y escalable para SaaS.
- RLS de PostgreSQL actúa como un `WHERE` obligatorio a nivel de base de datos, garantizando aislamiento incluso si la lógica de aplicación falla.
- Supabase soporta RLS de forma nativa con integración directa al JWT de autenticación.

**Alternatives considered**:
- Schema-per-tenant: Descartado por complejidad operativa excesiva para el MVP y dificultad en migraciones.
- Database-per-tenant: Descartado por costo de infraestructura desproporcionado y complejidad de gestión.

---

## R-003: Inyección de Claims en JWT

**Decision**: Usar Supabase Auth Hook ("Customize Access Token") para inyectar `organization_id` y `role` en el JWT.

**Rationale**:
- Elimina consultas adicionales a la base de datos en cada request para obtener tenant y rol.
- Los claims quedan disponibles dentro de las políticas RLS vía `auth.jwt()`.
- Mejora significativa de rendimiento al evitar JOINs con tablas de permisos en cada consulta.
- Patrón recomendado por la documentación oficial de Supabase para RBAC multi-tenant.

**Alternatives considered**:
- Lookup en tabla `user_roles` desde cada política RLS: Descartado por impacto en rendimiento (query adicional por cada operación).
- `user_metadata` en Supabase: Descartado porque es modificable desde el cliente; `app_metadata` + Auth Hook es más seguro.

---

## R-004: Modelo de Roles (RBAC)

**Decision**: Enum PostgreSQL con tres roles fijos (`admin`, `operator`, `agent`) + un solo rol por usuario con herencia jerárquica.

**Rationale**:
- El spec define un modelo de rol único y jerárquico: Admin > Operator > Agent.
- La clarificación confirma que la herencia es directa: Admin puede ejecutar acciones de Operador y Agente.
- Un enum PostgreSQL (`app_role`) es simple, type-safe y evita tablas intermedias innecesarias.
- Los roles dinámicos están explícitamente diferidos para fases SaaS avanzadas.

**Alternatives considered**:
- Tabla de roles con permisos granulares (PBAC): Descartado por violar "Evolution Over Prediction" — los roles son fijos para el MVP.
- Bitfield de permisos: Descartado por complejidad innecesaria y falta de legibilidad.

---

## R-005: Expiración y Gestión de Sesiones

**Decision**: JWT con expiración de 1 hora + refresh token gestionado por Supabase SDK. Invalidación por inactividad (8h) y máximo absoluto (24h) controlada a nivel de aplicación.

**Rationale**:
- Supabase Auth gestiona tokens JWT de corta duración (configurable, recomendado 1h) con refresh automático.
- La política de 8h de inactividad se implementa almacenando `last_activity_at` en la sesión de aplicación y validando en middleware/guard.
- La política de 24h máximo absoluto se controla comparando la hora de emisión original del token (`iat` del JWT) con la hora actual.
- `onAuthStateChange` en Angular mantiene el estado de sesión reactivo con Signals.

**Alternatives considered**:
- Sesión server-side con cookies: Descartado por no alinear con la arquitectura stateless de Supabase.
- JWT con expiración de 8h sin refresh: Descartado por mala experiencia de usuario durante jornadas laborales.

**Corrección durante la implementación (T024)**: el máximo absoluto **no** puede anclarse en el
`iat` del token. Supabase reemite el access token aproximadamente cada hora y cada token nuevo
trae un `iat` nuevo, por lo que el techo de 24 horas nunca se alcanzaría. El ancla es
`session.user.last_sign_in_at`, que Supabase Auth fija al verificar la contraseña y no modifica
al refrescar; el `iat` queda como respaldo. El reloj de inactividad se reanuda desde
`user_profiles.last_activity_at` tras una recarga. Ver
[ADR-0003](../../docs/adr/0003-server-side-credential-and-lockout-enforcement.md).

---

## R-006: Registro y Onboarding de Agencias

**Decision**: Formulario público que invoca una función Edge de Supabase (o RPC) para crear atómicamente la Organización y el usuario Administrador.

**Rationale**:
- La operación de registro requiere atomicidad: si falla la creación del usuario, la organización no debe existir (y viceversa).
- Una función PostgreSQL (`rpc`) ejecutada con permisos de servicio garantiza transaccionalidad.
- Supabase Auth crea el usuario, y un trigger `after_insert` en `auth.users` o la función RPC crea la organización y el perfil con rol admin.

**Alternatives considered**:
- Crear organización desde el frontend y luego el usuario: Descartado por riesgo de estados inconsistentes.
- Edge Function serverless: Viable como alternativa si la lógica crece, pero la función RPC es más simple para el MVP.

---

## R-007: Contraseñas Temporales y Cambio Obligatorio

**Decision**: Flag `must_change_password` en la tabla `user_profiles` + Angular Guard que intercepta toda navegación hasta completar el cambio.

**Rationale**:
- Al crear un colaborador, el admin asigna una contraseña temporal.
- La tabla `user_profiles` almacena `must_change_password: boolean DEFAULT true`.
- Un guard funcional de Angular verifica este flag al inicio de cada navegación y redirige a `/change-password` si es `true`.
- Al completar el cambio, se actualiza el flag a `false` y se permite la navegación normal.

**Alternatives considered**:
- Magic link / invitación por email: Descartado porque el spec indica explícitamente contraseña temporal asignada por admin.
- Campo en `user_metadata` de Supabase: Descartado porque es modificable desde el cliente.

---

## R-008: Bitácora de Auditoría Inmutable

**Decision**: Tabla `audit.audit_events` en esquema separado `audit`, capturada por triggers PostgreSQL, protegida contra UPDATE/DELETE con trigger de inmutabilidad.

**Rationale**:
- La Constitución y el spec exigen registros inmutables de eventos de seguridad.
- Triggers a nivel de base de datos garantizan captura independiente de la capa de aplicación.
- Un trigger `BEFORE UPDATE OR DELETE` que lanza `RAISE EXCEPTION` impide toda mutación.
- El esquema separado `audit` facilita la gestión de permisos y el cumplimiento.
- Index BRIN en `created_at` para rendimiento en consultas temporales.

**Alternatives considered**:
- Logging a nivel de aplicación (servicio Angular/API): Descartado por riesgo de bypass y falta de garantía de captura.
- Servicio externo de auditoría: Excesivo para el MVP; se puede agregar como destino secundario en el futuro.

---

## R-009: Estructura del Frontend Angular

**Decision**: Standalone Components, Angular Signals, Functional Guards, servicio centralizado `AuthService` con signal de estado.

**Rationale**:
- La Constitución establece Angular con Standalone Components y Signals como tecnología oficial.
- Angular 22 (última versión estable) usa componentes standalone por defecto (comportamiento por defecto desde Angular 19).
- Los guards funcionales (`CanActivateFn`) son el patrón moderno recomendado.
- Un `AuthService` centralizado con `signal<User | null>` reactivo simplifica la gestión de estado de autenticación.
- `computed()` signals para derivar datos del usuario (organización, rol, permisos).

**Alternatives considered**:
- NgModules + class-based guards: Descartado por ser patrón legacy en Angular moderno (20+).
- State management externo (NgRx/NGXS): Descartado por el principio de simplicidad — Signals nativos son suficientes para auth state.

---

## R-010: Bloqueo por Intentos Fallidos

**Decision**: Implementar rate limiting de intentos de login a nivel de función PostgreSQL/Edge Function con contador `failed_login_attempts` y `locked_until` en `user_profiles`.

**Rationale**:
- El spec requiere bloqueo temporal ante intentos fallidos consecutivos para mitigar fuerza bruta.
- Campos `failed_login_attempts` (integer) y `locked_until` (timestamptz) en `user_profiles`.
- La lógica de verificación ocurre antes de la autenticación de Supabase Auth.
- Después de N intentos fallidos (configurable, inicialmente 5), se bloquea la cuenta por un período configurable (inicialmente 15 minutos).
- Login exitoso resetea el contador.

**Alternatives considered**:
- Rate limiting a nivel de CDN/proxy: Complementario pero no suficiente — no previene ataques distribuidos contra una sola cuenta.
- Supabase Auth built-in rate limiting: Limita requests globales pero no es específico por cuenta.

**Corrección durante la implementación (T020)**: la lógica **no** puede ejecutarse antes de la
autenticación. Una comprobación previa invocable desde el cliente le permitiría al atacante
saltársela llamando directo a `/auth/v1/token`, y una que incremente el contador sin haber
probado la contraseña convierte el login en un oráculo de existencia de cuentas y en un vector
de denegación de servicio contra usuarios legítimos. El contador avanza dentro del Auth Hook
*Password Verification Attempt* (`public.password_verification_hook`), que Supabase Auth ejecuta
como `supabase_auth_admin` después de comparar la contraseña y cuya decisión respeta. El hook
es inalcanzable desde `authenticated` y `anon`. Requiere habilitar el hook en la configuración
del proyecto. Ver
[ADR-0003](../../docs/adr/0003-server-side-credential-and-lockout-enforcement.md).
