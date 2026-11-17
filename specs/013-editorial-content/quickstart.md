# Quickstart: validar el blog multiagencia

Guía de validación de punta a punta. Los detalles de las interfaces están en [contracts/](./contracts/) y los del modelo, en [data-model.md](./data-model.md).

## Prerequisites

- ADR-0004 aceptado y Constitución y mainspec enmendados (2026-11-17). Hecho.
- Docker en marcha, para el arnés SQL.
- Dependencias instaladas (`npm ci`) y Supabase local (`supabase start`) con las migraciones aplicadas, para probar el panel.
- Dos agencias de prueba (A y B), cada una con un Administrador, un Operador y un Agente. La agencia A ofrece `es` y `en`; la B, solo `es`.

## Automated validation

```bash
./supabase/tests/run-sql-tests.sh supabase/tests/blog_articles_test.sql supabase/tests/blog_isolation_test.sql supabase/tests/blog_public_read_test.sql supabase/tests/blog_cutover_test.sql
```

```bash
npm test -- --watch=false
```

```bash
npm run lint
```

```bash
npm run build
```

Resultado esperado: todas las suites SQL terminan en `==> all suites passed`. Vitest, lint y build quedan en verde.

## Required scenarios

| # | Escenario | Cómo | Resultado esperado | Spec |
| --- | --- | --- | --- | --- |
| 1 | Borrador incompleto | Operador A crea un artículo solo con el título en español, guarda, cierra sesión y vuelve | Aparece como «Borrador» con el título; se puede seguir editando | US1, FR-002 |
| 2 | Publicar incompleto | Publicar el artículo 1 | `PUBLISH_INCOMPLETE` con los campos faltantes en `es` y `en`; sigue en borrador | FR-004, SC-007 |
| 3 | Publicar válido | Completar `es`, `en`, la portada y los textos alternativos, y publicar | Antes de 5 minutos, `get_public_blog_by_key` de A lo lista y `get_public_blog_article_by_key` lo devuelve con `seoTitle` y `seoDescription` | US2, FR-024, FR-025, SC-002 |
| 4 | Borrador oculto | Pedir por slug un segundo artículo en borrador | `{"found": false}`, igual que un slug inventado | FR-026, SC-003 |
| 5 | Mismo slug | A y B publican `que-ver-en-cartagena` | Cada clave devuelve el artículo de su agencia | US3, FR-014, SC-004 |
| 6 | Permisos | Un Agente llama a `save_blog_article`; el Operador de B llama a `get_blog_article` con un id de A | `FORBIDDEN` y `NOT_FOUND`; nada cambia | FR-018, FR-019, SC-005 |
| 7 | Revisión en curso | Editar el artículo publicado y guardar sin publicar | La web sigue mostrando la versión anterior; el panel muestra «Cambios sin publicar» | US4, FR-011, FR-013, SC-006 |
| 8 | Publicar y descartar cambios | Publicar cambios; en otra edición, descartarlos | La misma URL muestra la versión nueva con el mismo `publishedAt`; al descartar, el panel vuelve a la versión publicada | FR-012, FR-017 |
| 9 | Slug fijo | Enviar otro slug para un artículo publicado | `SLUG_LOCKED` | FR-016 |
| 10 | Conflicto | Dos pestañas guardan con la misma `expectedRevision` | La segunda recibe `ARTICLE_CONFLICT` y el panel avisa | FR-010 |
| 11 | Retirar y republicar | Retirar, y luego republicar | Antes de 5 minutos el artículo deja de listarse y responde `found: false`; al republicar vuelve con la misma URL y la misma fecha | US5, FR-008, FR-029 |
| 12 | Eliminar | Eliminar un borrador nunca publicado, y luego un artículo retirado | El primero se elimina; el segundo recibe `NOT_DELETABLE` | FR-009 |
| 13 | Contenido peligroso | Guardar un cuerpo con un bloque `{"type":"script"}` y un enlace `javascript:` | El bloque se descarta y el enlace pierde su `href`; la lectura pública no los contiene | FR-007, SC-009 |
| 14 | Idiomas del perfil | B (solo `es`) publica sin `en`; A desactiva `en` en su perfil | B publica sin problema; la lectura de A deja de traer la clave `en` | FR-004, FR-023 |
| 15 | Migración | Admin A marca «blog migrado», carga un manifiesto de 3 slugs, copia 2 artículos e intenta completar | `BLOG_CUTOVER_INCOMPLETE` con el slug faltante; la lectura pública devuelve `source: "legacy"` | US6, FR-030, FR-032, SC-010 |
| 16 | Completar la migración | Copiar el tercer artículo (con un slug heredado fuera de formato y su fecha original) y completar | `source: "panel"`; los 3 slugs se resuelven con sus fechas originales | FR-031, FR-033 |
| 17 | Agencia nueva | B publica sin ninguna fila de fuente | Se publica directamente, sin exigir copia | FR-034 |
| 18 | Clave inválida | Llamar con una clave revocada | `PUBLIC_ACCESS_UNAVAILABLE` | FR-028 |
| 19 | Auditoría | Revisar `/settings/audit` como Administrador A | Hay eventos de publicación, cambios, retiro y fuente con el actor y la fecha, sin contenido | FR-020, FR-035, SC-008 |
| 20 | Independencia | Revocar la `EXECUTE` de `get_public_blog_by_key` en local y llamar a `get_public_site_by_key` | El catálogo responde con normalidad | FR-037 |
