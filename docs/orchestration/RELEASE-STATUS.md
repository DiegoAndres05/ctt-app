# Estado de CTT Release

Actualizado 2026-11-13. Repo `ctt-app`, rama `main`,
HEAD `2844c6fc7a361ee821d9b118abf4d34fdb4f7868`.
Estabilización integrada mediante `62bf01c`; fix de lint posterior `2844c6f`.
Los agentes/docs anteriores no sobrevivieron en el working tree: restaurados de
evidencia; todavía sin commit. No se realizaron commits/push en esta tarea.

| Fase | Estado | Responsable | Prerrequisitos | Resultados verificables | Defectos abiertos / gate | Siguiente acción permitida | Aprobaciones pendientes |
|---|---|---|---|---|---|---|---|
| G0 estabilización | En ejecución | orquestador + auditor | D1/D2, regresión, salud local | Histórico 143/143 y 45/45 en 84375d3; nueva ejecución pendiente | Auditoría anterior interrumpida por HTTP429, sin dictamen | Revalidar revisión actual y auditar | Solo recursos nuevos autorizados |
| 2 | Bloqueada | ctt-local-e2e | G0 habilitante | Sin E2E nuevo aprobado | G2: falta auditoría G0 | Esperar G0; luego stack aislado y flujo nuevo | Ampliaciones de alcance |
| 3 | No iniciada | ctt-integration-engineer | G2, repo público autorizado | Ninguno | G3: ubicación Next.js pendiente | Solo preparación documental | Ruta/acceso y orden de fase |
| 4 | No iniciada | ctt-staging-validator | G3, infraestructura aislada autorizada | Ninguno | G4: staging desconocido | Solo preparación documental | Recursos remotos |
| 5A | No iniciada | ctt-release-engineer | G4 | Ninguno | Sin candidata | Solo preparación documental | Orden de fase |
| 5B | No iniciada | ctt-release-engineer | 5A + autorización específica actual | Ninguno | Sin deploy autorizado | Ninguna operación productiva | Cada operación/destino/revisión/ventana |

Autorización del usuario en este hilo: crear recursos Docker NUEVOS
`ctt-release-qa-*` con datos sintéticos y eliminar solo esos recursos. No autoriza
resets de Supabase existente, volúmenes preexistentes ni recursos remotos.
Los logs de noviembre11 son históricos; no sustituyen evidencia actual.

Riesgos históricos aún abiertos: D3 `alternative_of:null`, O1 estado de aceptación
público, O2 UUID malformado y enlaces antiguos crudos con `/`. Evaluar severidad
contra specs y comportamiento real, sin minimizar ni dar por cerrados.

Locks: instalador posee documentación de orquestación y definiciones de agentes;
auditor solo lectura; pruebas SQL usan ID único sin host mounts/puertos/red.
No hay autorización para modificar código de aplicación en paralelo.
