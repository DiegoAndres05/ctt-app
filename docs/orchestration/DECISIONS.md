# Decisiones de orquestación

Restaurado el **2026-11-13**. Fechas con precisión de día; no se inventan horas ni evidencia. Nuevas decisiones/operaciones registran timestamp real ISO 8601 con zona, autor, autoridad, contexto, decisión, consecuencias y referencias. Este registro no aprueba gates.

| ID / fecha | Decisión y fundamento | Consecuencia/estado |
| --- | --- | --- |
| D-001 / 2026-11-11 | Separar inicialización de ejecución; seis agentes persistentes y auditor independiente conforme Constitución §13. | Regla conservada: fases 3–5 fuera de inicialización; el padre verifica runtime. |
| D-002 / 2026-11-11 | Descubrimiento previo OpenCode 1.19.5 V1, `agent` singular, permisos `permission`/`bash`/`task`, Markdown `.opencode/agents/`; web V2 diferente. | Antecedente, no nueva verificación. Modelo heredado, sin `default_agent` ni modelo hardcodeado; reiniciar tras cambios. |
| D-003 / 2026-11-11 | Verificación basada en riesgo y evidencia nueva, auditoría independiente y gates fail-closed, según §13 y Quality Gates 11–15. | Históricos no sustituyen ejecución actual; no inventar cobertura ni convertir fixtures en aceptación de negocio real. |
| D-004 / 2026-11-13 | Restaurar únicamente RELEASE-ORCHESTRATION.md, AGENT-RESPONSIBILITIES.md, QUALITY-GATES.md y DECISIONS.md por instrucción actual. | RELEASE-STATUS.md e initialization-report.md son del padre; otro agente restaura los seis agentes. Preservar evidence/ y trabajo concurrente. |
| D-005 / 2026-11-13 | Nueva baseline comunicada: `main` HEAD `2844c6fc7a361ee821d9b118abf4d34fdb4f7868`; estabilización integrada por `62bf01c`, lint corregido en `2844c6f`. | Sustituye la baseline inicial `7c05cd9...`; revalidar SHA/diff/untracked al ejecutar. No mantener como actuales los once cambios/fixes sin seguimiento del contexto inicial. |
| D-006 / 2026-11-13 | Clasificar 143 unitarios y 45 SQL de `84375d3` (2026-11-11) y smoke previo 5/5 como evidencia histórica. Última auditoría real CLI falló 429 por cuota, sin dictamen. | Ningún resultado aprueba la revisión actual. Registrar fallo sin atribuir veredicto al auditor; nueva comprobación runtime/auditoría pendiente. |
| D-007 / 2026-11-13 | Introducir G0 explícito: baseline, documentos/agentes, configuración/runtime, permisos, plan local, destinos previstos, autorización y locks, auditados independientemente. | G0 no exige ejecución/resultados G2; G2 sí exige G0 habilitante. No hay dependencia circular. G0 bloqueado mientras falte dictamen actual. |
| D-008 / 2026-11-13 | Mantener estados No iniciada / En ejecución / Bloqueada / Rechazada / Aprobada con observaciones / Aprobada; dictámenes APROBADO / APROBADO CON OBSERVACIONES / RECHAZADO / NO VERIFICABLE. | `NO VERIFICABLE → Bloqueada`. Error sin dictamen también bloquea, sin inventar dictamen. Observaciones no dispensan requisitos obligatorios. |
| D-009 / 2026-11-13 | Usuario autoriza en este hilo recursos Docker locales nuevos `ctt-release-qa...` para creación/disposición. | Alcance limitado: nombres exactos y contexto local verificados; datos sintéticos; no reset de Supabase existente, volúmenes ajenos ni limpieza global. Registrar operaciones concretas; fuera del alcance pedir aprobación nueva. |
| D-010 / 2026-11-13 | Un lock exclusivo por ruta/recurso, handoff estructurado y snapshot congelado para auditoría. | Evitar escrituras solapadas, preservar trabajo ajeno y conciliar locks vencidos antes de reasignar. Auditor solo lectura; padre persiste su texto verbatim. |
| D-011 / 2026-11-13 | Ruta Next.js e infraestructura staging siguen desconocidas; no hay autoridad de búsqueda externa por inferencia. | Pedir ruta/revisión y destinos/identidades autorizados. URL en spec009 no autoriza extracción de catálogo ni copia real. Fases 3–5 no se ejecutan en restauración. |
| D-012 / 2026-11-13 | Separar 5A candidato de 5B producción. Aprobación humana de uso único por operación con comando/cwd, destino, revisión, ventana y máximo alcance. | «Continúa» o aprobación de plan/gate no autorizan producción. Sin commits, push, deploy, reset o copia real automáticos. Reintento, recuperación y siguiente operación requieren autorización propia. |
| D-013 / 2026-11-13 | Permisos OpenCode no son sandbox; inspeccionar credenciales/destinos efectivos y scripts/procesos hijos sin exponer secretos. | Permisos solo una vez, nunca `--auto`; `allow` no sustituye autorización. Destino/identidad desconocidos bloquean. |
| D-014 / 2026-11-13 | Evidencia nueva por run_id/fase, informes estructurados y redacción antes de persistir. | Rutas canónicas abajo; no crear evidencia ficticia ni declarar éxito por restaurar documentación. |

## Entregables y continuidad

- Evidencia: `docs/orchestration/evidence/<run_id>/<fase>/`.
- Local: `docs/qa/reports/local-e2e-report.md`.
- Integración: `docs/integration/integration-report.md`.
- Staging: `docs/release/staging-validation-report.md`.
- Plan de producción: `docs/release/production-release-plan.md`.

Los seis agentes deben leer los cuatro documentos al iniciar/reanudar. Sus informes incluyen AGENTE, FASE, ESTADO, OBJETIVO, REPOSITORIO/REVISIÓN, ENTORNO, TAREAS REALIZADAS, ARCHIVOS MODIFICADOS, PRUEBAS EJECUTADAS, RESULTADOS, EVIDENCIAS, DEFECTOS, RIESGOS, BLOQUEOS y RECOMENDACIÓN.

El padre añade decisiones posteriores bajo lock, preservando historial e indicando qué decisión reemplaza. Las aprobaciones operativas usan el registro completo de RELEASE-ORCHESTRATION.md; no se completan retrospectivamente para justificar efectos ya realizados. No almacenar secretos ni atribuir horas, autorizaciones o resultados no comprobados.
