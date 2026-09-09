# Quickstart: 001-auth-tenant-access

**Date**: 2026-09-08 | **Spec**: [spec.md](./spec.md) | **Data Model**: [data-model.md](./data-model.md) | **Contracts**: [contracts/api-contracts.md](./contracts/api-contracts.md)

---

## Prerequisites

- Node.js 20+ instalado (requerido por Angular 22)
- Angular CLI 22+ instalado (`npm install -g @angular/cli`)
- Cuenta de Supabase con proyecto creado
- Variables de entorno configuradas:
  - `SUPABASE_URL`: URL del proyecto Supabase
  - `SUPABASE_ANON_KEY`: Clave pública anon del proyecto
  - `SUPABASE_SERVICE_ROLE_KEY`: Clave de servicio (solo para scripts de migración)

---

## Setup Commands

### 1. Base de Datos (Supabase)

```bash
# Ejecutar migraciones SQL en orden
# Cada archivo de migración se ejecuta en Supabase SQL Editor o via supabase CLI

# 1. Crear esquema de auditoría y enums
supabase db push --db-url $DATABASE_URL

# 2. Verificar que las tablas fueron creadas
supabase db dump --schema public --schema audit
```

### 2. Auth Hook Configuration

```bash
# En Supabase Dashboard:
# 1. Ir a Authentication → Hooks
# 2. Habilitar "Customize Access Token (JWT) Claims"
# 3. Seleccionar la función `custom_access_token_hook`
# 4. Guardar y verificar que el hook está activo

# 5. Habilitar "Password Verification Attempt"
# 6. Seleccionar la función `password_verification_hook`
# 7. Guardar y verificar que el hook está activo
```

> El segundo hook es obligatorio: sin él no hay bloqueo por intentos fallidos ni rechazo de
> cuentas desactivadas (Escenario 6). El contador `failed_login_attempts` solo avanza dentro de
> ese hook.

### 2b. Tests SQL contra PostgreSQL 17

```bash
# Requiere Docker. Levanta un contenedor efímero, aplica el harness, las migraciones
# y el seed, ejecuta las suites y destruye el contenedor.
./supabase/tests/run-sql-tests.sh
```

### 3. Frontend Angular

```bash
# Instalar dependencias del proyecto
npm install

# Instalar Supabase JS client
npm install @supabase/supabase-js

# Iniciar servidor de desarrollo
ng serve
```

---

## Validation Scenarios

### Escenario 1: Registro de Nueva Agencia

**Goal**: Verificar que una nueva agencia puede registrarse y acceder inmediatamente.

```bash
# 1. Navegar al formulario de registro público
# URL: http://localhost:4200/register

# 2. Completar el formulario con:
#    - Nombre de agencia: "Agencia Demo Turismo"
#    - Nombre completo: "Admin Demo"
#    - Email: "admin@demo-turismo.com"
#    - Contraseña: "SecurePass123!"

# 3. Enviar el formulario
```

**Expected Outcome**:
- Se crea la organización "Agencia Demo Turismo" con slug `agencia-demo-turismo`.
- Se crea el usuario con rol `admin` y `must_change_password = false`.
- Se inicia sesión automáticamente y se redirige al dashboard.
- Se genera un evento de auditoría `organization_created`.
- Se genera un evento de auditoría `login_success`.

**Verification SQL**:
```sql
-- Verificar organización
SELECT id, name, slug, status FROM public.organizations WHERE slug = 'agencia-demo-turismo';

-- Verificar perfil de usuario
SELECT id, full_name, role, status, must_change_password
FROM public.user_profiles WHERE email = 'admin@demo-turismo.com';

-- Verificar eventos de auditoría
SELECT event_type, result, created_at
FROM audit.audit_events WHERE organization_id = '<org_id>'
ORDER BY created_at DESC;
```

---

### Escenario 2: Login y Logout

**Goal**: Verificar el flujo completo de autenticación y cierre de sesión.

```bash
# 1. Navegar a: http://localhost:4200/login
# 2. Ingresar credenciales válidas
# 3. Verificar redirección al dashboard
# 4. Verificar que el JWT contiene claims de organization_id y role
# 5. Hacer logout
# 6. Verificar redirección al login
```

**Expected Outcome**:
- Login exitoso redirige al dashboard correspondiente al rol.
- JWT contiene `organization_id` y `role` en claims personalizados.
- Logout invalida la sesión y redirige a `/login`.
- Se generan eventos de auditoría `login_success` y `logout`.

**Verification (Browser DevTools)**:
```javascript
// En la consola del navegador después del login:
const { data: { session } } = await supabase.auth.getSession();
const jwt = JSON.parse(atob(session.access_token.split('.')[1]));
console.log('organization_id:', jwt.organization_id); // Debe mostrar UUID
console.log('app_role:', jwt.app_role); // Debe mostrar 'admin'
console.log('role:', jwt.role); // Debe seguir siendo 'authenticated' (claim reservado)
```

---

### Escenario 3: Aislamiento Multi-Tenant

**Goal**: Verificar que los datos entre organizaciones están completamente aislados.

```bash
# 1. Registrar dos agencias diferentes:
#    - "Agencia Alpha" (admin-alpha@test.com)
#    - "Agencia Beta" (admin-beta@test.com)

# 2. Con sesión de Agencia Alpha, crear un colaborador
# 3. Con sesión de Agencia Beta, intentar listar usuarios
# 4. Verificar que Beta NO ve usuarios de Alpha
```

**Expected Outcome**:
- Cada agencia solo ve sus propios datos.
- Las consultas a `user_profiles` filtran automáticamente por `organization_id` del JWT.
- Intentar acceder a un recurso de otra organización por ID directo retorna 404 o vacío.

**Verification SQL**:
```sql
-- Con service_role, verificar que RLS funciona:
-- Setear JWT de Alpha
SET request.jwt.claims = '{"organization_id": "<alpha_org_id>", "app_role": "admin"}';
SELECT * FROM public.user_profiles; -- Solo debe mostrar usuarios de Alpha
```

---

### Escenario 4: RBAC - Control de Acceso por Rol

**Goal**: Verificar que los roles limitan el acceso a funcionalidades.

```bash
# 1. Login como Admin → Verificar acceso a gestión de usuarios
# 2. Login como Operador → Verificar que NO puede gestionar usuarios
# 3. Login como Agente → Verificar acceso limitado

# Acciones de Admin:
# - Crear usuario ✅
# - Cambiar rol ✅
# - Ver auditoría ✅

# Acciones de Operador:
# - Crear usuario ❌ (403)
# - Ver auditoría ❌ (403)

# Acciones de Agente:
# - Crear usuario ❌ (403)
# - Cambiar configuración ❌ (403)
```

**Expected Outcome**:
- Admin puede ejecutar todas las acciones.
- Operador y Agente reciben error 403 al intentar acciones administrativas.
- RLS políticas bloquean el acceso a nivel de base de datos.

---

### Escenario 5: Contraseña Temporal y Cambio Obligatorio

**Goal**: Verificar el flujo de primer login con contraseña temporal.

```bash
# 1. Admin crea colaborador con contraseña temporal "TempPass1!"
# 2. Colaborador hace login con "TempPass1!"
# 3. Verificar redirección forzada a /change-password
# 4. Colaborador cambia contraseña a "NewSecure123!"
# 5. Verificar navegación normal después del cambio
```

**Expected Outcome**:
- Login con contraseña temporal es exitoso.
- El guard funcional detecta `must_change_password = true` y redirige a `/change-password`.
- Toda navegación está bloqueada excepto `/change-password`.
- Después del cambio, `must_change_password` se actualiza a `false`.
- Se genera evento de auditoría `password_changed`.
- El flag solo lo limpia la RPC `change_password`: un `UPDATE` directo del colaborador sobre
  `must_change_password` es rechazado por el trigger `enforce_user_profile_update_scope`.
- Las demás sesiones del usuario quedan invalidadas tras el cambio.

---

### Escenario 6: Bloqueo por Intentos Fallidos

**Goal**: Verificar el mecanismo de bloqueo temporal.

```bash
# 1. Intentar login con contraseña incorrecta 5 veces consecutivas
# 2. Verificar que la cuenta se bloquea
# 3. Intentar login con contraseña correcta → debe fallar (cuenta bloqueada)
# 4. Esperar 15 minutos (o ajustar para prueba)
# 5. Intentar login con contraseña correcta → debe funcionar
```

**Expected Outcome**:
- Después de 5 intentos fallidos, la cuenta se bloquea por 15 minutos.
- Se genera evento de auditoría `account_locked`.
- Durante el bloqueo, incluso credenciales correctas son rechazadas.
- Después del timeout, el login con credenciales correctas funciona.
- Se genera evento `account_unlocked` y `login_success`.
- El formulario de login muestra un mensaje genérico mientras la cuenta no está bloqueada: el
  contador de intentos restantes no se revela.

> El paso 4 no requiere esperar 15 minutos reales: basta con retrasar `locked_until` con
> `UPDATE public.user_profiles SET locked_until = now() - interval '1 minute' WHERE ...`
> usando `service_role`. La cobertura automatizada de este escenario vive en
> `supabase/tests/us1_auth_functions_test.sql`.

---

### Escenario 7: Auditoría Inmutable

**Goal**: Verificar que los registros de auditoría no pueden ser modificados ni eliminados.

```bash
# 1. Ejecutar acciones que generen eventos de auditoría
# 2. Verificar que los eventos se registran correctamente
# 3. Intentar UPDATE/DELETE en audit_events → debe fallar
```

**Verification SQL**:
```sql
-- Intentar modificar un registro de auditoría (debe fallar)
UPDATE audit.audit_events SET result = 'success' WHERE id = 1;
-- Error: "Audit logs are immutable and cannot be modified or deleted."

-- Intentar eliminar un registro (debe fallar)
DELETE FROM audit.audit_events WHERE id = 1;
-- Error: "Audit logs are immutable and cannot be modified or deleted."
```

**Expected Outcome**:
- Todos los eventos se registran con datos completos (actor, timestamp, tipo, resultado).
- Cualquier intento de UPDATE o DELETE en `audit.audit_events` falla con excepción.
- Los eventos son consultables solo por administradores de la misma organización.
