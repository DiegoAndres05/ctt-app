# ADR-0004: El blog de cada agencia se escribe y se publica en el panel, no en WordPress

- **Identifier**: ADR-0004
- **Title**: Autoría y publicación de artículos de blog en el CMS del panel, con migración desde WordPress
- **Status**: Accepted · implementado (migraciones `066`–`071`, panel `/cms/blog`)
- **Date**: 2026-11-17 (propuesto y aceptado)
- **Deciders**: Responsable del proyecto (dueño de la Constitución), Equipo de Arquitectura
- **Change level**: Nivel 3, cambio de la tecnología responsable de una capacidad (Constitución, *Change Approval Levels*)
- **Affected Chapters**:
  - Constitución: *Technology Direction*, *Content Management* (cap. 1 y sección de arquitectura).
  - Mainspec: cap. 22 *Content Management*, cap. 27.1 *Integrations* y cap. 30.1 *MVP Included*.
- **Affected Specs**:
  - `specs/013-editorial-content/` (spec, plan, research, data-model, contratos).
  - `specs/016-multiagency-public-cms/` (reutiliza la clave pública, la transición de CTT y el modelo de cambio de fuente).
  - `specs/014-public-freshness/` (plazo de 5 minutos).
- **Supersedes**: nada. **Amends**: Constitución *Content Management* y mainspec 22.1.

## Context

La Constitución fija hoy:

> «WordPress SHALL be used as a headless content management system. Its responsibility SHALL be limited to content-oriented capabilities such as: Blog articles, Landing pages, Marketing content, SEO-oriented information.»

El mainspec 22.1 repite que WordPress «SHALL be considered the content management system for» el blog, el contenido de marketing, las páginas SEO y la información editorial. El 30.1 incluye «WordPress content integration» en el MVP.

Esa decisión se tomó cuando el producto atendía a una sola agencia (CTT), que ya tenía su sitio y su blog en WordPress. Desde entonces el producto cambió en tres puntos:

1. **Ahora es multiagencia.** El spec 016 dio a cada agencia su propia configuración pública, su clave de acceso y sus reglas de aislamiento, y un camino para agencias que publican directamente en la plataforma sin un sitio previo. Una agencia nueva no tiene WordPress. Exigirle uno para tener blog contradice la meta de 016 de no imponer a las agencias nuevas un paso que no necesitan.
2. **El blog quedó fuera del modelo multiagencia.** Sin un cambio, cada agencia operaría su propio WordPress, con usuarios, permisos y auditoría ajenos al panel. Las reglas de roles (Operador y Administrador gestionan el contenido público; Agente no), la clave pública, la respuesta genérica ante credenciales inválidas y la auditoría de 016 no alcanzarían al blog.
3. **El spec 013 se reabrió (2026-11-17)** con el objetivo explícito de que una persona autorizada escriba, publique y retire artículos desde el panel y que el sitio conectado los muestre sin cambios de código. En la sesión de aclaraciones del mismo día se decidió que, para una agencia con blog previo, la salida es **migrar con cambio de fuente** hasta que el panel sea la única fuente del blog (D-3).

El plan de 013 dejó la puerta de la Constitución en **FAIL justificado** y bloqueó la implementación hasta aceptar este ADR (`specs/013-editorial-content/plan.md`, *Constitution Check*).

## Decision

### 1. El panel es el gestor de los artículos de blog de cada agencia

- Los artículos se escriben, publican, editan (con revisión en curso) y retiran en la sección «Blog» del CMS del panel.
- Se guardan en PostgreSQL con aislamiento por `organization_id`, RLS y RPC `SECURITY DEFINER`, igual que las fichas públicas.
- El contenido es un documento de bloques validado en la base de datos, no HTML (research de 013, Decisión 1).
- Las imágenes van al bucket `catalog-media` bajo el prefijo de la agencia.

### 2. El sitio de cada agencia lee el blog con el contrato público de 016

- La lectura pública usa la clave de la agencia o, solo para CTT y durante su transición, el identificador de organización.
- Devuelve únicamente artículos publicados de esa agencia y va por llamadas separadas del catálogo, para que un fallo del blog no afecte al catálogo ni a las solicitudes.
- Esta app sigue sin construir un sitio público propio: cada sitio pinta los bloques.

### 3. WordPress deja de ser fuente del blog tras el cambio de fuente

Para una agencia con blog previo:

- Se marca la agencia como «blog migrado».
- Se carga el manifiesto de slugs que muestra su sitio actual.
- Se copian los artículos conservando slug y fecha original.
- Solo se completa el cambio de fuente cuando todo el manifiesto está publicado.

Hasta entonces, la lectura pública responde `source: "legacy"` y el sitio sigue leyendo WordPress. Después del cambio, el panel es la **única** fuente del blog de esa agencia. No se admite convivencia indefinida de ambas fuentes.

### 4. Alcance acotado al blog

Esta decisión **no** cambia el papel de WordPress en:

- landing pages;
- contenido de marketing;
- páginas orientadas a SEO.

Tampoco cubre guías, destinos ni políticas, que el 013 original contemplaba. Esas piezas siguen en WordPress hasta que un ADR posterior decida otra cosa.

### 5. Enmienda constitucional

Se aprueba, junto con este ADR, la enmienda descrita en [Enmienda constitucional propuesta](#enmienda-constitucional-propuesta). Este ADR cumple también el papel de **propuesta de RFC**: el capítulo 3 exige RFC para «New product capabilities». El análisis de impacto está en la sección [Consequences](#consequences). Aprobar este documento equivale a aceptar el RFC.

## Alternatives considered

1. **Mantener WordPress como único gestor del blog** (sin cambios).
   - Se descarta porque cada agencia tendría que operar su propio WordPress.
   - El blog quedaría fuera de los roles, la clave, la auditoría y el aislamiento de la plataforma.
   - Además, contradice el objetivo de 016 de no imponer pasos innecesarios a las agencias nuevas.
2. **WordPress multisitio administrado por la plataforma.**
   - Una instancia con un sitio por agencia.
   - Se descarta porque añade infraestructura nueva (PHP, MySQL, copias de seguridad, actualizaciones de seguridad y plugins), otra base de usuarios y otro modelo de permisos que habría que sincronizar con el panel.
   - Choca con *Simplicity Over Complexity* y con *Modular Monolith*.
3. **Convivencia indefinida: el sitio combina WordPress y el panel.**
   - Se descartó en la aclaración D-3 del spec 013.
   - Deja dos fuentes de verdad, riesgo de slugs duplicados y reglas de visibilidad distintas según de dónde venga el artículo.
4. **WordPress se queda para las agencias que ya lo usan y el panel solo para las nuevas.**
   - Se descartó en D-3.
   - Fragmenta el producto en dos modos permanentes y deja a CTT, la agencia de referencia, fuera del modelo multiagencia.
5. **Un CMS headless de terceros (SaaS).**
   - Introduce un proveedor y una dependencia externa por agencia, con costos y credenciales que la plataforma tendría que gestionar.
   - No resuelve el aislamiento con las mismas reglas del panel y contradice la preferencia constitucional por evitar dependencias de proveedor innecesarias.

## Consequences

**Positivas**

- Cualquier agencia publica su blog sin instalar ni operar WordPress, y con los mismos roles, clave, auditoría y aislamiento que el catálogo.
- Un solo modelo de contenido público: fichas y artículos comparten el patrón de publicación, la frescura de 5 minutos (014) y el cambio de fuente `legacy` → `panel` (009 y 016).
- El contenido en bloques elimina la superficie de XSS hacia los sitios consumidores: no viaja HTML.
- CTT migra sin romper direcciones: los slugs y las fechas originales se conservan y el cambio de fuente no se completa con contenido faltante.

**Negativas / Riesgos**

- **La plataforma asume un editor de contenido.** El editor por bloques propio (sin WYSIWYG ni librería externa) es más limitado que el de WordPress.
  - Mitigación: SC-001 del spec 013 (≤ 20 minutos por idioma para un artículo de unas 800 palabras) se valida con usuarios.
  - Si no se cumple, se reevalúa una librería de edición en un ADR propio.
- **Migración manual de CTT.** Copiar el blog existente es trabajo de la agencia mientras no exista una importación automática.
  - Mitigación: el manifiesto muestra qué falta y el sitio sigue leyendo WordPress hasta completar la copia. La importación automática desde la API REST de WordPress queda como mejora opcional.
- **Imágenes de borrador con URL pública.** Igual que las fichas, el bucket es de lectura pública. Una imagen de borrador no aparece en ninguna lectura pública, pero cualquiera con la URL exacta (un UUID imposible de adivinar) puede abrirla. No hay requisito de confidencialidad que lo impida. Si apareciera, el cambio sería un bucket privado con URLs firmadas.
- **Imágenes externas en artículos migrados.** Durante la transición, un artículo migrado puede referenciar imágenes que siguen en el servidor de WordPress. Si ese servidor se apaga, las imágenes se pierden.
  - Seguimiento: subir esas imágenes a `catalog-media` antes de dar de baja WordPress.
- **El SEO depende del sitio consumidor.** La plataforma entrega título y descripción SEO, pero metadatos, sitemap y redirecciones son responsabilidad del sitio.
- **Dos gestores durante un tiempo.** Mientras landing pages y marketing sigan en WordPress, el equipo de una agencia como CTT usará dos herramientas. Es una consecuencia aceptada del alcance acotado (Decisión 4).

**Análisis de impacto (RFC)**

| Área | Impacto |
| --- | --- |
| Base de datos | Seis migraciones nuevas (`066`–`071`): cuatro tablas, dos enums y seis tipos de evento de auditoría. No se modifica ninguna migración existente. |
| Seguridad | RLS por agencia, sin acceso de `anon` a tablas, RPC con `search_path = ''` y no enumeración. Se reutilizan la clave y la transición de 016 sin cambiarlas. |
| Panel Angular | Rutas `/cms/blog` y `/cms/settings/blog-migration`, una entrada en la navegación y etiquetas de auditoría. Sin dependencias npm nuevas. |
| Sitios consumidores | Nuevo contrato `specs/013-editorial-content/contracts/public-consumer.md`. El sitio de CTT debe pintar los bloques y respetar una caché de 300 s como máximo. |
| Operación | La migración de CTT requiere preparar el manifiesto y copiar los artículos. WordPress sigue activo para landing pages y marketing. |
| Specs existentes | No contradice 009, 014, 015 ni 016. Retira las tareas obsoletas del 013 original. |

## Enmienda constitucional propuesta

Sigue el *Amendment Process* del capítulo 16.

- **Motivation**: El producto pasó a ser multiagencia (016) y el blog debe seguir las mismas reglas de aislamiento, roles, clave pública y auditoría que el resto del contenido público.
- **Current limitation**: *Content Management* asigna los «Blog articles» a WordPress. Eso obliga a cada agencia a operar su propio WordPress y deja el blog fuera de los controles de la plataforma.
- **Proposed modification**:
  - En *Technology Direction*, cambiar la línea «Content Management: WordPress (Headless CMS)» por:
    > Content Management
    > - Platform CMS (blog articles and public listings, per agency)
    > - WordPress (Headless CMS) for landing pages, marketing and SEO-oriented content
  - En la sección *Content Management* de la arquitectura, sustituir el texto actual por:
    > Blog articles SHALL be authored, published and retired in the platform CMS, isolated per agency and exposed to each agency's public site through the public access model.
    >
    > WordPress MAY be used as a headless content management system for landing pages, marketing content and SEO-oriented information.
    >
    > An agency that already publishes a blog in WordPress SHALL migrate it through an explicit source switch; until the switch is completed, its public site MAY keep reading WordPress.
    >
    > Business data SHALL NOT be managed within WordPress.
- **Expected benefits**: Un único modelo multiagencia para el contenido público, sin infraestructura nueva y con la misma postura de seguridad.
- **Potential risks**: Los que se listan en *Consequences*: alcance del editor, esfuerzo de migración y dos gestores durante la transición.
- **Impacted chapters**: Constitución, cap. 1 (*Technology Direction*) y la sección *Content Management* de la arquitectura.

**Alineación del mainspec** (se actualiza al aceptar este ADR, según *Backward Compatibility*):

- **22.1**: «Blog content SHALL be managed in the platform CMS per agency. WordPress SHALL be considered the content management system for marketing content, SEO-oriented pages and other editorial information not covered by the platform CMS.»
- **27.1**: WordPress se mantiene como integración, para landing pages y marketing.
- **30.1**: «WordPress content integration» pasa a «Content management: platform blog and WordPress integration for marketing content».

## Approval checklist

- [x] El responsable del proyecto acepta este ADR (2026-11-17).
- [x] Se aplica la enmienda en `.specify/memory/constitution.md` (cap. 1 y sección *Content Management*).
- [x] Se alinea `.specify/mainspec.md` (22.1, 27.1 y 30.1).
- [x] El *Constitution Check* de `specs/013-editorial-content/plan.md` pasa de FAIL justificado a PASS, con referencia a este ADR.
- [x] Recién entonces arrancan las tareas de implementación de `specs/013-editorial-content/tasks.md`.
