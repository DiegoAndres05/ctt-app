# CTT Release — Estado persistente

Actualizado: 2026-11-11. Inicialización en curso; ninguna aprobación heredada.

## Identidad y alcance

- Panel: workspace actual `ctt-app`, `main`, HEAD `7c05cd9f3c43002ae25287c708fa4cfa9f8bc0a9`.
- Working tree preexistente: 11 archivos tracked modificados; informes de noviembre,
  migraciones 056/057, dos suites SQL y `.claude/agents/` sin seguimiento. Conservar.
- Sitio Next.js: declarado por usuario, ubicación/revisión/acceso pendientes.
- Supabase local existente: `cttadmin`, socket Docker Unix `desktop-linux`, API
  54321, DB 54322. Consulta de solo lectura confirma migraciones hasta 057.
- No se ha autorizado ningún recurso remoto, staging ni producción.
- Autorización de esta inicialización: crear y eliminar exclusivamente recursos
  Docker NUEVOS `ctt-release-qa-*` con datos sintéticos. No reset ni borrado de
  Supabase existente. Cada ejecución futura requiere revalidar autorización.

## Gates

| Fase | Estado | Responsable | Prerrequisito | Resultado verificable | Defectos/bloqueos | Gate | Siguiente acción permitida | Aprobaciones pendientes |
|---|---|---|---|---|---|---|---|---|
| Estabilización | En ejecución | Orquestador + local-e2e + auditor | Git/código/migraciones reales | Fixes presentes; 056/057 registradas en DB local | Ejecuciones nuevas y auditoría pendientes; D3/O1/O2 históricos | Entrada | Unitarias/SQL aisladas y auditoría | Solo recursos nuevos aprobados |
| 2 E2E local | No iniciada | ctt-local-e2e | Estabilización verificada | Ninguno actual | Flujo nuevo de 18 pasos pendiente | 2 | Esperar entrada aprobada | Cualquier ampliación de recursos |
| 3 Integración | No iniciada | ctt-integration-engineer | Gate 2 y repos autorizados | Ninguno | Ubicación Next.js pendiente | 3 | Preparación documental; no ejecutar | Acceso repo público y orden de fase |
| 4 Preproducción | No iniciada | ctt-staging-validator | Gate 3 y staging aislado | Ninguno | Infraestructura no descubierta | 4 | Preparación documental; no ejecutar | Recursos/destinos remotos |
| 5A Candidata | No iniciada | ctt-release-engineer | Gate 4 | Ninguno | Sin revisiones candidatas aprobadas | 5A | Preparación documental; no ejecutar | Orden de fase |
| 5B Producción | No iniciada | ctt-release-engineer | 5A + autorización específica actual | Ninguno | Sin despliegue autorizado | 5B | Ninguna operación productiva | Cada operación/destino/revisión/ventana |

## Evidencia

- Antecedentes (no ejecuciones de esta inicialización): `docs/e2e-2026-11-09.md`,
  `docs/stabilization-2026-11-11.md`.
- Evidencias nuevas se almacenan en `docs/orchestration/evidence/` con run ID,
  timestamps, HEAD, hashes del working tree, comandos, exit codes y logs.
- Cualquier cambio de código/destino invalida la aprobación afectada.

## Bloqueos y observaciones por verificar

- D1/D2: candidatos de fix locales sin commit, no declarar cierre por informe.
- D3: `alternative_of: null`; O1: estado público tras aceptar; O2: UUID de
  `source_request_item_id`; vouchers antiguos crudos con `/`. Severidad/cierre
  sujetos a comprobación y auditoría, no aprobación implícita.
- Harness SQL simula JWT y no sustituye Supabase Auth ni navegador.
- Prohibido reusar pre-reservas para evitar defectos, borrar por nombres genéricos
  o ejecutar fases 3–5 durante esta inicialización.

## Locks

- Orquestador: `docs/orchestration/`, `.opencode/agents/` solo durante instalación.
- Pruebas SQL: contenedor nuevo con run ID; nunca `cttadmin-sqlcheck` compartido.
- No hay lock/autorización para modificar aplicación o datos existentes.
