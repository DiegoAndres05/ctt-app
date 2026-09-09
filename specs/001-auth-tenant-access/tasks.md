---
description: "Task list for 001-auth-tenant-access implementation"
---

# Tasks: 001-auth-tenant-access (Autenticación, Multi-Tenant, RBAC y Auditoría)

**Input**: Design documents from `/specs/001-auth-tenant-access/`

**Prerequisites**: plan.md (required), spec.md, research.md, data-model.md, contracts/api-contracts.md, quickstart.md

**Tech Stack**: Angular 22 (Standalone Components, Signals, Signal Forms), TypeScript 6.x, Supabase (PostgreSQL + Auth + RLS + Edge Functions)

**Tests**: Solo se incluyen tests explícitamente exigidos por criterios de éxito (SC-002 aislamiento multi-tenant, FR-005/US4 inmutabilidad de auditoría). No se aplica TDD completo.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Puede ejecutarse en paralelo (archivos distintos, sin dependencias pendientes)
- **[Story]**: Historia de usuario a la que pertenece (US1–US5)
- Rutas de archivo exactas incluidas en cada tarea

## Path Conventions

- **Frontend**: `src/app/...` (Angular workspace en la raíz del repositorio)
- **Backend**: `supabase/migrations/`, `supabase/functions/`, `supabase/tests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Inicialización del proyecto y estructura base

- [X] T001 Crear workspace Angular 22 standalone e inicializar estructura de carpetas (`src/app/core/`, `src/app/features/`, `src/app/shared/`, `src/environments/`) según plan.md
- [X] T002 Instalar dependencias base del frontend (`@angular/*` 22, `@supabase/supabase-js`) y verificar Node.js 20+ en `package.json`
- [X] T003 [P] Configurar ESLint + Prettier para Angular en `eslint.config.js` (flat config; `.eslintrc.json` fue eliminado en ESLint 9+) y `.prettierrc`
- [X] T004 [P] Crear archivos de entorno `src/environments/environment.ts` y `src/environments/environment.development.ts` con `SUPABASE_URL` y `SUPABASE_ANON_KEY`
- [X] T005 Inicializar estructura Supabase (`supabase/` con `config.toml`, carpetas `migrations/`, `functions/`, `tests/`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Esquema de base de datos, RLS, JWT claims y servicios base requeridos por TODAS las historias

**⚠️ CRITICAL**: Ninguna historia de usuario puede comenzar hasta completar esta fase

- [X] T006 Crear migración de enums en `supabase/migrations/001_create_enums.sql` (`app_role`, `organization_status`, `user_status`, `audit.audit_event_type`, `audit.audit_result`)
- [X] T007 Crear tabla `organizations` en `supabase/migrations/002_create_organizations.sql` (campos, índices `slug` unique, `status`)
- [X] T008 Crear tabla `user_profiles` en `supabase/migrations/003_create_user_profiles.sql` (FK a `auth.users` y `organizations`, índices por `organization_id`, `email` unique)
- [X] T009 Crear esquema `audit` y tabla `audit.audit_events` en `supabase/migrations/004_create_audit_schema.sql` (índice BRIN en `created_at`, índices por tenant y `event_type`)
- [X] T010 Crear políticas RLS de aislamiento multi-tenant en `supabase/migrations/005_create_rls_policies.sql` (organizations, user_profiles, audit_events según data-model.md) — depende de T007, T008, T009
- [X] T011 Crear Auth Hook `custom_access_token_hook` (inyección de `organization_id` y `app_role` en JWT — ver ADR-0002) en `supabase/migrations/006_create_auth_hook.sql`
- [X] T012 Crear triggers en `supabase/migrations/007_create_triggers.sql` (auto-`updated_at`, inmutabilidad de auditoría `BEFORE UPDATE OR DELETE`, captura automática de eventos de seguridad)
- [X] T013 Crear `supabase/seed.sql` con datos de prueba mínimos (organización demo + usuarios por rol)
- [X] T014 [P] Implementar `SupabaseService` singleton (cliente + `onAuthStateChange`; delega hashing/almacenamiento de credenciales a Supabase Auth — FR-007) en `src/app/core/auth/services/supabase.service.ts`
- [X] T015 [P] Crear modelos de dominio en `src/app/core/auth/models/user.model.ts`, `organization.model.ts` y `auth.model.ts`
- [X] T016 [P] Crear modelo de auditoría en `src/app/core/audit/models/audit-event.model.ts`
- [X] T017 Implementar `AuthService` base con `signal<Session|null>` reactivo y `computed()` de usuario en `src/app/core/auth/services/auth.service.ts` (depende de T014, T015)
- [X] T018 Configurar routing y providers de la aplicación en `src/app/app.config.ts` y `src/app/app.routes.ts` (rutas públicas vs. protegidas)
- [X] T019 [P] Configurar manejo de errores y logging base en `src/app/core/error/error-handler.ts`

**Checkpoint**: Fundación lista — las historias de usuario pueden iniciar

---

## Phase 3: User Story 1 - Autenticación y Gestión de Sesiones (Priority: P1) 🎯 MVP

**Goal**: Login/logout seguros, contexto de identidad, expiración de sesión (8h inactividad / 24h absoluto) y bloqueo por intentos fallidos.

**Independent Test**: Login con credenciales válidas redirige al panel; credenciales inválidas se rechazan con mensaje genérico; 5 intentos fallidos bloquean la cuenta; logout invalida la sesión.

- [X] T020 [US1] Crear funciones de login seguro en `supabase/migrations/008_us1_auth_functions.sql` (`change_password`, control `failed_login_attempts`/`locked_until`, reset en login exitoso)
- [X] T021 [P] [US1] Implementar `LoginComponent` con Signal Forms en `src/app/features/auth/login/login.component.ts`
- [X] T022 [US1] Implementar métodos `signIn`/`signOut` y contexto de identidad en `src/app/core/auth/services/auth.service.ts` (depende de T017)
- [X] T023 [P] [US1] Implementar `authGuard` (`CanActivateFn`) en `src/app/core/auth/guards/auth.guard.ts`
- [X] T024 [US1] Implementar `sessionInterceptor` (expiración 8h inactividad / 24h absoluto, actualización de `last_activity_at`) en `src/app/core/auth/interceptors/session.interceptor.ts`
- [X] T025 [US1] Implementar manejo de bloqueo por intentos fallidos y mensajes genéricos en el flujo de login (`login.component.ts` + `auth.service.ts`)
- [X] T026 [P] [US1] Implementar `ChangePasswordComponent` con Signal Forms en `src/app/features/auth/change-password/change-password.component.ts`
- [X] T027 [US1] Implementar `passwordChangeGuard` (intercepta navegación si `must_change_password = true`) en `src/app/core/auth/guards/password-change.guard.ts`

**Checkpoint**: US1 funcional y testeable de forma independiente (login/logout, sesión, bloqueo, cambio obligatorio)

---

## Phase 4: User Story 2 - Aislamiento Multi-Tenant (Priority: P1)

**Goal**: Garantizar 0% de fuga de datos entre organizaciones (SC-002) mediante RLS + claims de JWT.

**Independent Test**: Crear dos organizaciones; verificar que un usuario de A no puede leer/modificar datos de B; solicitudes sin claim de organización se rechazan.

- [X] T028 [US2] Exponer contexto de tenant en `AuthService` con `computed()` `organizationId` y `role` derivados del JWT en `src/app/core/auth/services/auth.service.ts`
- [X] T029 [US2] Añadir verificación de claim de organización en `authGuard`/`sessionInterceptor` (rechazo si falta `organization_id`) en `src/app/core/auth/guards/auth.guard.ts`
- [X] T030 [P] [US2] Escribir tests SQL de aislamiento RLS en `supabase/tests/rls_isolation_test.sql` (usuario de A no ve datos de B en `user_profiles`, `organizations`, `audit_events`) — requerido por SC-002
- [X] T031 [US2] Documentar y validar acceso por ID directo cross-tenant (retorna 404/vacío) en `supabase/tests/rls_isolation_test.sql`

**Checkpoint**: US1 + US2 funcionan; aislamiento verificado por pruebas automatizadas

---

## Phase 5: User Story 3 - Control de Acceso Basado en Roles / RBAC (Priority: P2)

**Goal**: Roles jerárquicos (Admin > Operador > Agente); gestión de usuarios internos restringida a Admin.

**Independent Test**: Agente/Operador reciben 403 en acciones administrativas; Admin puede crear usuarios y cambiar roles con efecto inmediato.

- [X] T032 [US3] Crear funciones de gestión de usuarios en `supabase/migrations/009_us3_user_management.sql` (`create_internal_user`, `update_user_role`, `toggle_user_status`, con eventos de auditoría)
- [X] T033 [P] [US3] Implementar `roleGuard` (verificación de rol/jerarquía) en `src/app/core/auth/guards/role.guard.ts`
- [X] T034 [US3] Implementar `UserService` (listar/crear/actualizar/rol/estado) en `src/app/features/users/services/user.service.ts`
- [X] T035 [P] [US3] Implementar `UserListComponent` en `src/app/features/users/user-list/user-list.component.ts`
- [X] T036 [P] [US3] Implementar `UserCreateComponent` con Signal Forms (contraseña temporal, rol) en `src/app/features/users/user-create/user-create.component.ts`
- [X] T037 [P] [US3] Implementar `UserDetailComponent` (editar rol/estado) en `src/app/features/users/user-detail/user-detail.component.ts`
- [X] T038 [US3] Aplicar `roleGuard` a rutas de administración y ocultar UI no autorizada en `src/app/app.routes.ts`

**Checkpoint**: US1–US3 funcionan de forma independiente

---

## Phase 6: User Story 4 - Registro Inmutable de Auditoría Base (Priority: P2)

**Goal**: Eventos de seguridad registrados de forma inmutable y consultables por administradores.

**Independent Test**: Ejecutar acciones sensibles genera eventos con actor/org/timestamp/tipo/resultado; UPDATE/DELETE sobre `audit_events` falla.

- [X] T039 [US4] Implementar `AuditService` (consulta con filtros por `event_type`, `actor_id`, rango de fechas, paginación) en `src/app/core/audit/services/audit.service.ts`
- [X] T040 [P] [US4] Implementar `AuditLogComponent` (visor con filtros, solo Admin) en `src/app/features/audit/audit-log/audit-log.component.ts`
- [X] T041 [US4] Aplicar `roleGuard` admin a la ruta de auditoría en `src/app/app.routes.ts`
- [X] T042 [P] [US4] Escribir test SQL de inmutabilidad en `supabase/tests/audit_immutability_test.sql` (UPDATE/DELETE lanzan excepción)

**Checkpoint**: US1–US4 funcionan de forma independiente

---

## Phase 7: User Story 5 - Registro y Onboarding de Nueva Agencia (Priority: P2)

**Goal**: Formulario público que crea atómicamente Organización + usuario Administrador con sesión activa.

**Independent Test**: Completar el formulario crea org + admin y accede al panel; email duplicado se rechaza con 409.

- [X] T043 [US5] Crear RPC transaccional `register_agency(p_agency_name, p_admin_user_id, p_full_name, p_email)` que recibe el `user_id` ya creado en auth.users e inserta atómicamente `organizations` + `user_profiles` (rol admin, must_change_password=false), con rollback si falla cualquier paso, en `supabase/migrations/010_us5_register_agency.sql`
- [X] T044 [US5] Implementar Edge Function `register-agency` que: (1) crea el usuario vía Supabase Admin API, (2) invoca la RPC `register_agency` con el `user_id` resultante, (3) revierte el usuario auth si la RPC falla; en `supabase/functions/register-agency/index.ts`
- [X] T045 [P] [US5] Implementar `RegisterComponent` con Signal Forms en `src/app/features/auth/register/register.component.ts`
- [X] T046 [US5] Integrar registro en `AuthService` (`registerAgency`) y manejar errores `EMAIL_ALREADY_EXISTS`/`AGENCY_SLUG_EXISTS` en `src/app/core/auth/services/auth.service.ts`

**Checkpoint**: Todas las historias (US1–US5) funcionan de forma independiente

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Mejoras transversales

- [X] T047 [P] Crear componentes compartidos (feedback de errores, spinner de carga) en `src/app/shared/components/`
- [X] T048 Ejecutar validación completa de `specs/001-auth-tenant-access/quickstart.md` (7 escenarios)
- [X] T049 [P] Revisión de seguridad: verificar Default Deny, claims server-side y ausencia de secretos hardcodeados
- [X] T050 [P] Verificar objetivos de rendimiento (auth < 2s, verificación de sesión < 500ms, auditoría < 500ms) por SC-003/SC-004
- [X] T051 Actualizar documentación de módulo y sincronizar `AGENTS.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Sin dependencias — inicio inmediato
- **Foundational (Phase 2)**: Depende de Setup — BLOQUEA todas las historias
- **User Stories (Phase 3–7)**: Dependen de Foundational
  - US1 (P1) y US2 (P1) forman el MVP; US2 se apoya en el contexto de identidad de US1
  - US3, US4, US5 (P2) pueden desarrollarse en paralelo tras Foundational
- **Polish (Phase 8)**: Depende de las historias entregadas

### User Story Dependencies

- **US1 (P1)**: Solo Foundational
- **US2 (P1)**: Foundational + contexto de identidad de US1 (integra, pero se testea independientemente)
- **US3 (P2)**: Foundational (reutiliza `passwordChangeGuard` de US1 para colaboradores)
- **US4 (P2)**: Foundational (triggers de auditoría ya creados en T012)
- **US5 (P2)**: Foundational — independiente

### Parallel Opportunities

- Setup: T003, T004 en paralelo
- Foundational: T014, T015, T016, T019 en paralelo (tras migraciones)
- US1: T021, T023, T026 en paralelo
- US3: T035, T036, T037 en paralelo (tras T034)
- Con equipo: US3, US4 y US5 en paralelo por desarrolladores distintos tras Foundational

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Completar Phase 1 (Setup) y Phase 2 (Foundational)
2. Completar Phase 3 (US1) → validar login/logout/sesión
3. Completar Phase 4 (US2) → validar aislamiento (SC-002)
4. **STOP y VALIDAR**: MVP autenticación + tenant isolation

### Incremental Delivery

1. Foundational listo
2. US1 → validar → demo (MVP auth)
3. US2 → validar aislamiento → demo
4. US3 → RBAC → demo
5. US4 → auditoría → demo
6. US5 → onboarding self-service → demo

---

## Notes

- `[P]` = archivos distintos, sin dependencias pendientes
- Todos los formularios usan **Signal Forms** (Angular 22) — ver ADR-0001
- Migraciones SQL son secuenciales; respetar el orden numérico de archivos
- Verificar tests de aislamiento (T030) e inmutabilidad (T042) antes de dar por cerradas US2 y US4
- Commit tras cada tarea o grupo lógico
