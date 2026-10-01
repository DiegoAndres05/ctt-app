# Research: Navegación lateral, listados y CMS guiado con vista previa

**Feature**: 010-admin-layout-navigation  
**Date**: 2026-09-30

## 1. Cáscara autenticada vs. menú por pantalla

**Decision**: Una ruta padre protegida (`AdminShellComponent`) envuelve todas las pantallas autenticadas excepto el cambio de contraseña obligatorio. Login y registro siguen fuera.

**Rationale**: Hoy cada pantalla pinta su propio enlace a «Panel». Un solo layout cumple FR-001/FR-002/FR-010 y evita que una pantalla nueva olvide el menú. `passwordChangeGuard` ya aísla `change-password`; esa ruta se deja como hermana, no como hija del shell.

**Alternatives considered**:
- Menú copiado en cada feature: viola Composition Over Duplication.
- Shell en `app.html` con `*ngIf` de sesión: mezcla público y protegido y complica el cambio de contraseña.

## 2. Árbol de navegación como dato, no como plantilla suelta

**Decision**: Un árbol estático en `nav-items.ts` declara grupos, rutas, rol mínimo y si el ítem es de solo consulta para el agente. El sidebar lo filtra con `hasRoleAtLeast`.

**Rationale**: FR-004 y FR-008 piden el mismo criterio en menú y en ruta. Un árbol único es el lugar donde se documenta «quién ve qué». `roleGuard` en la ruta sigue siendo la autorización de UI; RLS sigue siendo la de datos.

**Alternatives considered**:
- Inferir el menú de las rutas de Angular: más mágico, peor de leer, y las redirecciones viejas ensuciarían el menú.
- Permisos por recurso en base de datos: fuera de alcance (FR-032).

## 3. URLs nuevas + redirecciones de las actuales

**Decision**:

| Actual | Nueva |
|--------|-------|
| `/dashboard` | `/dashboard` (igual) |
| `/users` | `/settings/users` |
| `/audit` | `/settings/audit` |
| `/catalog` | `/cms` (hub de ajustes o redirect a experiencias) |
| `/catalog/products` | `/cms/experiences` y `/cms/accommodations` (filtro `type`) |
| `/catalog/products/new` | `/cms/experiences/new` o `/cms/accommodations/new` |
| `/catalog/products/:id` | `/cms/experiences/:id` o `/cms/accommodations/:id` |
| `/catalog/packages` | `/cms/packages` |
| `/catalog/addons` | `/cms/settings/addons` |
| `/catalog/public-categories` | `/cms/settings/public-categories` |
| `/catalog/public-cutover` | `/cms/settings/cutover` |

Las rutas actuales quedan como `redirectTo` (FR-009). Un producto abierto por `/catalog/products/:id` redirige según `type` si hace falta; si no se conoce el tipo, a `/cms/experiences/:id` y el editor corrige.

**Rationale**: El menú pide Configuración y CMS como conceptos; reusar `/catalog` como CMS mezclaría el lenguaje de 002 con el de 009/010.

**Alternatives considered**:
- Dejar `/catalog` y solo añadir sidebar: más barato, pero el usuario pidió separar Configuración y CMS.
- Reescritura sin redirecciones: rompe enlaces y hábitos.

## 4. Listados: 20 por página y estado en la URL

**Decision**: Un componente compartido `data-table` (título, buscar, filtros, tabla, paginación, vacío / sin resultados). El estado `{ q, page, …filters }` vive en query params. La búsqueda escribe tras ~300 ms. `ProductService.list` se extiende a `listPage` con `from/to` (PostgREST range) y un `count: 'exact'`.

**Rationale**: FR-017 exige conservar y compartir el enlace. Query params no requieren almacenamiento nuevo y sobreviven a recargar.

**Alternatives considered**:
- Estado solo en signals: se pierde al volver del editor.
- Paginación en servidor con RPC nueva: innecesaria a esta escala; `range` + `ilike` basta.

## 5. Último acceso del colaborador

**Decision**: `UserService.list` enriquece cada perfil con `last_access_at`: el `created_at` más reciente de `audit.audit_events` con `event_type = login_success` y `actor_id` = el usuario. Una consulta adicional por lote, no N+1.

**Rationale**: `user_profiles` no guarda último acceso. `auth.users.last_sign_in_at` no es legible por el cliente (RLS de Auth). La auditoría ya registra `login_success` y el admin ya puede leerla.

**Alternatives considered**:
- Columna nueva en `user_profiles`: migración innecesaria para un dato derivado.
- RPC `SECURITY DEFINER` sobre `auth.users`: más privilegio del que hace falta.

## 6. Editor único que reemplaza create + detail

**Decision**: `ProductEditorComponent` en `/cms/experiences/new|:id` y `/cms/accommodations/new|:id`. El primer «Guardar borrador» llama `create_product` y luego `router.navigate` al `:id` sin destruir el formulario (o actualiza la ruta y habilita imágenes/precio in situ). La ficha pública, tarifas, categorías, adicionales, galería y opiniones se copian del detail actual (1421 líneas) reorganizadas en secciones.

**Rationale**: Clarify: una pantalla para crear y editar; imágenes y precio necesitan el producto. Unificar evita dos UIs que se desincronizan (FR-018a).

**Alternatives considered**:
- Wizard de varios pasos con rutas por paso: más clics, peor para retomar un borrador.
- Dejar create y detail y solo añadir preview al create: no cumple «reemplaza el detalle».

## 7. Vista previa local, no publicada

**Decision**: `ListingPreviewCardComponent` recibe un modelo de vista (`PreviewListing`) derivado de los signals del formulario. Idioma `es | en`. Variante `catalog | lodging | yacht` según `placement`. Recorta título (~70) y descripción (~140) como una card de catálogo típica. Foto: URL pública del bucket `catalog-media` o `external_ref`; si no hay, marcador.

**Rationale**: SC-005 y FR-025–029 piden reflejo inmediato sin guardar. Publicar para previsualizar sería lento y sucio.

**Alternatives considered**:
- iframe del sitio público: no hay sitio en este repo y el cutover puede seguir en `legacy`.
- Llamar `get_public_site`: solo ve fichas publicadas.

## 8. Yates dentro de Experiencias

**Decision**: El listado de experiencias pide productos `type = experience` y une `public_listings.placement`. Filtro y columna: Catálogo / Yates. En el editor, `placement = yacht` cambia la card y hace el precio de vitrina opcional.

**Rationale**: 009 ya modeló yates como experiencias + `placement`. Un tercer submenú duplicaría el tipo.

## 9. Preferencia del menú contraído

**Decision**: `localStorage` key `ctt.sidebar.collapsed` (`true` / `false`). En viewport &lt; 960px el menú es un drawer cerrado por defecto y no usa esa preferencia.

**Rationale**: FR-007 pide recordar en el mismo dispositivo. No es dato de negocio ni de tenant.

## 10. Dashboard vacío

**Decision**: Quitar los enlaces a Catálogo / Usuarios / Auditoría. Dejar saludo + texto de «los indicadores llegarán más adelante». Cerrar sesión se mueve a la barra superior.

**Rationale**: FR-012. Los indicadores son 008.

## 11. Roles y permisos de solo lectura

**Decision**: Matriz estática alineada con `ROLE_RANK` y el árbol de `nav-items.ts`, más un conteo `status = active` por rol vía `UserService.list`. Clic en un rol → `/settings/users?role=`.

**Rationale**: FR-030–032. Inventar roles editables contradice 001.

## 12. Scope que no se toca

- Sin migraciones de dominio ni cambios a `get_public_site`.
- Sin indicadores de 008.
- Sin crear/editar roles.
- WordPress sigue fuera del contenido comercial.
- Tests SQL de 009 no se reescriben; esta feature es UI.
