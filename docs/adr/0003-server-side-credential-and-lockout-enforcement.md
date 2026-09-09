# ADR-0003: Rotación de credenciales y bloqueo por intentos fallidos en la base de datos

- **Identifier**: ADR-0003
- **Title**: `change_password` y el conteo de intentos fallidos se ejecutan en PostgreSQL, no en el cliente
- **Status**: Accepted
- **Date**: 2026-09-08
- **Deciders**: Equipo de Arquitectura
- **Affected Chapters**: Cap. 8 (Security Principles), Cap. 13 (Verification & QA)
- **Affected Specs**: `specs/001-auth-tenant-access/data-model.md`,
  `specs/001-auth-tenant-access/contracts/api-contracts.md`,
  `specs/001-auth-tenant-access/research.md` (R-005, R-007, R-010)

## Context

La etapa fundacional dejó tres huecos de seguridad abiertos, todos en el mismo punto: el
control existía en la especificación pero no había ningún componente autorizado para
imponerlo.

1. **`must_change_password` era auto-escribible.** `data-model.md` incluía la columna en la
   lista blanca de auto-actualización, y el trigger `enforce_user_profile_update_scope`
   (migración 007) la permitía. Un colaborador podía limpiar el flag y conservar la contraseña
   temporal que le entregó el administrador, anulando FR-006 por completo. El propio
   `data-model.md` registraba el hueco como riesgo residual conocido.

2. **El bloqueo por intentos fallidos no tenía dónde ejecutarse.** `user_profiles` ya tenía
   `failed_login_attempts` y `locked_until`, pero el login ocurre contra Supabase Auth
   (GoTrue), que la base de datos no intercepta. R-010 indicaba "la lógica de verificación
   ocurre antes de la autenticación de Supabase Auth" sin definir el componente. Contar los
   intentos desde el navegador es inútil: el atacante controla ese código.

3. **La expiración de sesión (8h/24h) no tenía anclaje estable.** R-005 propone comparar el
   `iat` del token con la hora actual, pero Supabase reemite el access token cada hora y cada
   token nuevo trae un `iat` nuevo, con lo que el techo absoluto de 24 horas nunca se alcanza.

## Decision

### 1. `change_password` es una función `SECURITY DEFINER` que escribe `auth.users`

`public.change_password(p_current_password, p_new_password)` (migración 008) verifica la
contraseña actual contra `auth.users.encrypted_password` con `extensions.crypt`, genera el
nuevo hash con bcrypt (`extensions.gen_salt('bf')`), limpia `must_change_password` y elimina
las demás sesiones del usuario, **todo en una sola transacción**.

En consecuencia, `must_change_password` sale de la lista blanca del trigger: el flag ya solo
puede cambiar a `false` a través de esta función, o mediante la política `admin_update` de un
administrador de la misma organización.

El hashing y el almacenamiento siguen delegados a Supabase Auth en el sentido que exige FR-007
—mismo algoritmo, misma columna, jamás texto plano persistido—, pero la operación se ejecuta
en la base de datos porque es el único lugar donde "verificar, rotar y limpiar el flag" es
atómico. Coordinarlo desde el cliente contra la Auth API dejaría una ventana en la que la
contraseña cambió y el flag no, o al revés.

Además, `change_password` rechaza reutilizar la contraseña actual (`PASSWORD_UNCHANGED`) y
contraseñas de más de 72 bytes, longitud a partir de la cual bcrypt trunca en silencio.

### 2. El bloqueo se implementa como Auth Hook "Password Verification Attempt"

`public.password_verification_hook(event jsonb)` (migración 008) recibe
`{"user_id", "valid"}` de Supabase Auth después de comparar la contraseña contra el hash, y
devuelve `{"decision": "continue" | "reject", ...}`.

- Cinco verificaciones fallidas consecutivas fijan `locked_until = now() + 15 minutes`.
- Un bloqueo vigente rechaza el acceso **incluso con la contraseña correcta**.
- Un bloqueo expirado se limpia en el siguiente intento.
- Una cuenta desactivada se rechaza solo después de probar la contraseña, de modo que la
  respuesta no revele el estado de la cuenta a quien no la conoce.
- `login_success` y `login_failure` se emiten desde el hook; `account_locked` y
  `account_unlocked` los emite el trigger de la migración 007 al detectar el cambio de
  `locked_until`, sin actor asociado porque no hay ninguno (FR-005).

El hook solo es ejecutable por `supabase_auth_admin`, igual que `custom_access_token_hook`.
Ningún rol de aplicación puede invocarlo ni tocar los contadores.

Requiere habilitar el hook en el dashboard de Supabase (*Authentication → Hooks → Password
Verification Attempt*), igual que el hook de claims. Sin esa activación los contadores no
avanzan: es configuración obligatoria de despliegue, no opcional.

### 3. La expiración de sesión se ancla en `last_sign_in_at`

`SessionActivityStore` (`src/app/core/auth/interceptors/session.interceptor.ts`) ancla el
límite absoluto de 24 horas en `session.user.last_sign_in_at`, que Supabase Auth fija al
verificar la contraseña y **no** modifica al refrescar el token. El `iat` queda solo como
respaldo. El reloj de inactividad de 8 horas se reanuda desde `user_profiles.last_activity_at`
tras una recarga.

La política se impone en tres puntos que comparten el mismo estado: el interceptor de
`HttpClient`, un envoltorio de `fetch` en `SupabaseService` (el cliente de Supabase no pasa por
`HttpClient`) y `authGuard` en cada navegación.

## Alternatives considered

- **Rotar la contraseña desde el cliente vía `supabase.auth.updateUser()`**: Descartado. No
  verifica la contraseña actual, por lo que cualquier sesión secuestrada podría apropiarse de
  la cuenta, y deja la limpieza del flag como un segundo paso no transaccional.
- **Retirar `must_change_password` de la lista blanca sin implementar `change_password`**:
  Descartado. Cerraría el hueco dejando el flujo obligatorio de FR-006 sin salida: el
  colaborador quedaría atrapado en la pantalla de cambio.
- **Contar intentos fallidos en una RPC invocable por `anon`**: Descartado. Cualquiera podría
  llamarla directamente para bloquear cuentas ajenas sin intentar autenticarse, y nada
  garantizaría que un intento real haya ocurrido.
- **Rate limiting nativo de Supabase Auth**: Insuficiente por sí solo. Limita peticiones
  globales, no intentos por cuenta, que es lo que pide el spec.
- **Usar el `iat` del token como ancla del límite absoluto**, según la redacción de R-005:
  Descartado por incorrecto — el `iat` avanza en cada refresco y el techo de 24 horas nunca se
  alcanzaría.
- **Imponer la expiración de sesión en el servidor** (por ejemplo rechazando tokens en función
  de `last_activity_at`): Descartado para el MVP. Exigiría un hook o proxy en cada petición y
  la ganancia es limitada frente al vencimiento del propio access token. Ver riesgos.

## Consequences

**Positivas**

- `must_change_password` solo puede limpiarse rotando efectivamente la credencial, y la
  verificación es atómica.
- El contador de intentos fallidos solo avanza ante una verificación real de contraseña
  ejecutada por Supabase Auth; el navegador no participa.
- Un bloqueo vigente rechaza credenciales correctas, que es lo que pide el escenario 6 de
  `quickstart.md`.
- La rotación invalida las demás sesiones del usuario, que fueron autenticadas con la
  contraseña retirada.
- El techo absoluto de 24 horas es alcanzable.

**Negativas / Riesgos**

- **Acoplamiento a `auth.users` y `auth.sessions`.** `change_password` escribe tablas que son
  propiedad de GoTrue. Un cambio de esquema en Supabase Auth rompería la función. Mitigación:
  está confinado a una única función, y `supabase/tests/us1_auth_functions_test.sql` lo verifica
  contra un PostgreSQL real en cada ejecución del arnés.
- **La contraseña en texto plano viaja como parámetro de RPC.** Igual que ya viaja hacia
  Supabase Auth al iniciar sesión, y siempre bajo TLS. Consecuencia operativa: el proyecto
  **no** debe ejecutarse con `log_statement = 'all'` ni con `log_min_duration_statement` bajo,
  porque los parámetros de la sentencia acabarían en los logs.
- **Bloqueo dirigido como denegación de servicio.** Quien conozca un correo válido puede
  provocar cinco fallos y dejar la cuenta bloqueada 15 minutos. Es inherente a cualquier
  bloqueo por cuenta; se acota con la duración fija y la expiración automática.
- **La expiración de 8h/24h se impone en el cliente.** Es un control de usabilidad y de
  defensa en profundidad, no un límite: quien manipule el navegador puede seguir usando el
  access token hasta que venza. Las fronteras reales siguen siendo el vencimiento del token y
  RLS. Cerrarlo exigiría validación por petición en el servidor y se difiere hasta que exista
  una necesidad medible.
- **`password_changed` deja de inferirse del flag.** El trigger de la migración 007 emitía el
  evento al ver `must_change_password` pasar de `true` a `false`. Ahora lo emite
  `change_password`. Se retira esa rama del trigger: con la lista blanca vigente, ese cambio ya
  solo puede venir de la propia función (duplicaría el evento) o de un administrador (que no
  rotó ninguna contraseña, con lo que el evento sería falso). La dirección `false → true`
  sigue emitiendo `password_reset_forced`.

**Seguimiento**

- Habilitar el hook *Password Verification Attempt* en cada entorno de Supabase; sin ello el
  bloqueo por cuenta no se aplica.
- Cuando US3 incorpore la gestión de usuarios, el desbloqueo manual por un administrador debe
  pasar por una función `SECURITY DEFINER` y no por una escritura directa de `locked_until`.
