# API Contracts: Authentication

**Module**: 001-auth-tenant-access | **Date**: 2026-09-08

---

## POST /auth/v1/signup (Registro de Agencia)

**Public**: Sí (no requiere autenticación)

**Purpose**: Registrar nueva agencia con su usuario administrador inicial.

### Request Body

```json
{
  "agency_name": "string (required, max 255)",
  "full_name": "string (required, max 255)",
  "email": "string (required, valid email)",
  "password": "string (required, min 8 chars)"
}
```

### Response 201 Created

```json
{
  "data": {
    "organization": {
      "id": "uuid",
      "name": "string",
      "slug": "string"
    },
    "user": {
      "id": "uuid",
      "email": "string",
      "full_name": "string",
      "role": "admin"
    },
    "session": {
      "access_token": "string",
      "refresh_token": "string",
      "expires_in": 3600
    }
  }
}
```

### Error Responses

| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Campos inválidos o faltantes |
| 409 | `EMAIL_ALREADY_EXISTS` | El email ya está registrado |
| 409 | `AGENCY_SLUG_EXISTS` | El slug de la agencia ya existe |
| 500 | `REGISTRATION_FAILED` | Error interno durante el registro |

---

## POST /auth/v1/token?grant_type=password (Login)

**Public**: Sí (endpoint nativo de Supabase Auth)

**Purpose**: Autenticar usuario interno con email y contraseña.

### Request Body

```json
{
  "email": "string (required)",
  "password": "string (required)"
}
```

### Response 200 OK

```json
{
  "access_token": "string (JWT con claims organization_id y role)",
  "refresh_token": "string",
  "expires_in": 3600,
  "token_type": "bearer",
  "user": {
    "id": "uuid",
    "email": "string",
    "app_metadata": {
      "organization_id": "uuid",
      "role": "admin | operator | agent"
    }
  }
}
```

### Error Responses

| Status | Code | Description |
|--------|------|-------------|
| 400 | `INVALID_CREDENTIALS` | Email o contraseña incorrectos (genérico) |
| 403 | `ACCOUNT_LOCKED` | Cuenta bloqueada por intentos fallidos |
| 403 | `ACCOUNT_INACTIVE` | Cuenta desactivada por administrador |

> `ACCOUNT_LOCKED` y `ACCOUNT_INACTIVE` los emite el Auth Hook
> `password_verification_hook` como prefijo de su mensaje de rechazo, que Supabase Auth relaya
> tal cual. `ACCOUNT_INACTIVE` solo aparece una vez probada la contraseña, para no revelar el
> estado de la cuenta a quien no la conoce.

---

## POST /auth/v1/logout (Logout)

**Authenticated**: Sí

**Purpose**: Cerrar sesión del usuario actual.

### Request Headers

```
Authorization: Bearer <access_token>
```

### Response 200 OK

```json
{
  "message": "Successfully logged out"
}
```

---

## POST /auth/v1/token?grant_type=refresh_token (Refresh)

**Purpose**: Renovar tokens de acceso.

### Request Body

```json
{
  "refresh_token": "string (required)"
}
```

### Response 200 OK

Misma estructura que el response de Login.

---

## PUT /rest/v1/rpc/change_password (Cambio de Contraseña)

**Authenticated**: Sí

**Purpose**: Cambiar contraseña del usuario actual (obligatorio en primer login o voluntario).

### Request Body

```json
{
  "current_password": "string (required)",
  "new_password": "string (required, min 8 chars)"
}
```

### Response 200 OK

```json
{
  "data": {
    "must_change_password": false
  }
}
```

### Error Responses

| Status | Code | Description |
|--------|------|-------------|
| 400 | `INVALID_CURRENT_PASSWORD` | Contraseña actual incorrecta |
| 400 | `WEAK_PASSWORD` | La nueva contraseña no cumple requisitos (mínimo 8 caracteres, máximo 72 bytes) |
| 400 | `PASSWORD_UNCHANGED` | La nueva contraseña es igual a la actual |
| 403 | `ACCOUNT_INACTIVE` | La cuenta fue desactivada por un administrador |

> **Transporte del código de error**: la RPC lanza el código como mensaje de la excepción
> (`SQLSTATE P0001`), y el frontend lo traduce en `src/app/core/error/error-handler.ts`. Los
> mensajes de estas excepciones forman parte del contrato y no deben reescribirse.
>
> **Efecto adicional**: un cambio exitoso elimina las demás sesiones del usuario, autenticadas
> con la contraseña retirada. Ver
> [ADR-0003](../../../docs/adr/0003-server-side-credential-and-lockout-enforcement.md).

---

## GET /rest/v1/user_profiles (Listar Usuarios de la Organización)

**Authenticated**: Sí | **Role**: admin

**Purpose**: Listar todos los usuarios internos de la organización actual.

### Response 200 OK

```json
{
  "data": [
    {
      "id": "uuid",
      "full_name": "string",
      "email": "string",
      "role": "admin | operator | agent",
      "status": "active | inactive",
      "created_at": "timestamptz",
      "last_activity_at": "timestamptz | null"
    }
  ]
}
```

> **Nota**: RLS filtra automáticamente por `organization_id` del JWT.

---

## POST /rest/v1/rpc/create_internal_user (Crear Colaborador)

**Authenticated**: Sí | **Role**: admin

**Purpose**: Crear nuevo usuario interno con contraseña temporal.

### Request Body

```json
{
  "full_name": "string (required, max 255)",
  "email": "string (required, valid email)",
  "role": "operator | agent (required)",
  "temporary_password": "string (required, min 8 chars)"
}
```

### Response 201 Created

```json
{
  "data": {
    "id": "uuid",
    "full_name": "string",
    "email": "string",
    "role": "string",
    "status": "active",
    "must_change_password": true
  }
}
```

### Error Responses

| Status | Code | Description |
|--------|------|-------------|
| 400 | `VALIDATION_ERROR` | Campos inválidos |
| 403 | `INSUFFICIENT_PERMISSIONS` | El usuario no es admin |
| 409 | `EMAIL_ALREADY_EXISTS` | El email ya está registrado |

---

## PATCH /rest/v1/rpc/update_user_role (Cambiar Rol)

**Authenticated**: Sí | **Role**: admin

**Purpose**: Modificar el rol de un usuario interno.

### Request Body

```json
{
  "user_id": "uuid (required)",
  "new_role": "admin | operator | agent (required)"
}
```

### Response 200 OK

```json
{
  "data": {
    "id": "uuid",
    "role": "string",
    "updated_at": "timestamptz"
  }
}
```

---

## PATCH /rest/v1/rpc/toggle_user_status (Activar/Desactivar Usuario)

**Authenticated**: Sí | **Role**: admin

**Purpose**: Activar o desactivar un usuario interno. La desactivación invalida su sesión en la siguiente interacción.

### Request Body

```json
{
  "user_id": "uuid (required)",
  "status": "active | inactive (required)"
}
```

### Response 200 OK

```json
{
  "data": {
    "id": "uuid",
    "status": "string",
    "updated_at": "timestamptz"
  }
}
```

---

## GET /rest/v1/audit_events (Consultar Bitácora de Auditoría)

**Authenticated**: Sí | **Role**: admin

**Purpose**: Consultar eventos de auditoría de la organización.

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `event_type` | `string` | No | Filtrar por tipo de evento |
| `actor_id` | `uuid` | No | Filtrar por usuario actor |
| `from` | `timestamptz` | No | Fecha desde |
| `to` | `timestamptz` | No | Fecha hasta |
| `limit` | `integer` | No | Cantidad de registros (default 50, max 200) |
| `offset` | `integer` | No | Desplazamiento para paginación |

### Response 200 OK

```json
{
  "data": [
    {
      "id": "bigint",
      "event_type": "string",
      "actor_id": "uuid | null",
      "actor_name": "string | null",
      "resource_type": "string | null",
      "resource_id": "uuid | null",
      "result": "success | failure | error",
      "metadata": {},
      "ip_address": "string | null",
      "created_at": "timestamptz"
    }
  ],
  "count": "integer (total count for pagination)"
}
```

> **Nota**: RLS filtra automáticamente por `organization_id` del JWT. Solo admins pueden consultar.
