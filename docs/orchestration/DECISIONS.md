# Registro de decisiones de orquestación

Fecha inicial: **2026-11-11**. Registro documental, no evidencia de ejecución. Las entradas iniciales tienen precisión de fecha: no se conoce aquí una hora verificable y no se inventa. Las decisiones futuras deben registrar timestamp real ISO 8601 con zona, autor, autoridad, contexto, decisión, consecuencias y referencias. Las aprobaciones operativas usan además el registro completo de RELEASE-ORCHESTRATION.md §7.

## D-001 — Separación entre inicialización y ejecución

- **Fecha:** 2026-11-11 (hora no registrada).
- **Estado:** establecida por instrucción del usuario.
- **Contexto:** se requieren seis agentes OpenCode persistentes y un protocolo de release por fases.
- **Decisión:** el padre crea agentes y verifica runtime; esta entrega crea únicamente cuatro documentos nuevos bajo `docs/orchestration/`. RELEASE-STATUS.md e initialization-report.md pertenecen al padre. Las fases 3, 4, 5A y 5B no se ejecutan durante la inicialización.
- **Consecuencia:** documentos y agentes definidos no equivalen a una fase ejecutada ni aprobada. Los informes de fases se crearán solo bajo ownership y alcance autorizados.

## D-002 — Compatibilidad con OpenCode instalado

- **Fecha:** 2026-11-11 (hora no registrada).
- **Estado:** descubrimiento comunicado por el padre; verificación runtime de agentes pendiente.
- **Contexto:** CLI instalado 1.19.5, V1 activo; `debug config` muestra `agent` singular y configuración efectiva de `permission`, `bash` y `task`. La skill confirmó Markdown V1 en `.opencode/agents/`. La documentación web vigente V2 difiere.
- **Decisión:** usar el formato comprobado para el CLI instalado; no migrar por copiar ejemplos V2. No cambiar `default_agent`; no hardcodear modelo, heredar el seleccionado y verificado. Reiniciar OpenCode tras configurar.
- **Consecuencia:** el padre debe demostrar carga e invocación real, delegación y permisos efectivos. `openai/gpt-6-astra` listado por el CLI permite documentar el ejemplo de invocación, pero no acredita que se haya ejecutado.
- **Evidencia:** descubrimiento recibido en el encargo; no se adjunta ni se fabrica un log de runtime en esta entrega.

## D-003 — Línea base de trabajo protegida

- **Fecha:** 2026-11-11 (hora no registrada).
- **Estado:** línea base comunicada, pendiente de revalidación al ejecutar.
- **Contexto:** rama `main`, HEAD `7c05cd9...`, once archivos modificados y fixes 056/057 sin seguimiento; tests pendientes de repetición.
- **Decisión:** registrar SHA completo y manifestación del estado de trabajo antes de pruebas; preservar todo cambio preexistente. No resetear, limpiar, sobrescribir ni hacer commits de trabajo ajeno.
- **Consecuencia:** ningún informe anterior prueba el candidato actual; los fixes deben identificarse y verificarse en una ejecución nueva. El prefijo de SHA no se completa por conjetura.

## D-004 — Seis funciones e independencia

- **Fecha:** 2026-11-11 (hora no registrada).
- **Estado:** establecida.
- **Decisión:** `ctt-release-orchestrator` primario; `ctt-local-e2e` fase 2; `ctt-integration-engineer` fase 3; `ctt-staging-validator` fase 4; `ctt-release-engineer` fases 5A/5B; `ctt-quality-gate-auditor` independiente y de solo lectura.
- **Fundamento:** Constitución §13, validación independiente y evidencia; Quality Gate 15, revisión y aprobación.
- **Consecuencia:** el ejecutor no se autoaprueba. El auditor devuelve texto y el padre lo persiste íntegro, sin modificaciones al dictamen. Los seis leen los cuatro documentos al iniciar/reanudar.

## D-005 — Gates fail-closed y evidencia fresca

- **Fecha:** 2026-11-11 (hora no registrada).
- **Estado:** establecida.
- **Decisión:** usar estados No iniciada / En ejecución / Bloqueada / Rechazada / Aprobada con observaciones / Aprobada. Dictámenes APROBADO / APROBADO CON OBSERVACIONES / RECHAZADO / NO VERIFICABLE. `NO VERIFICABLE → Bloqueada` sin avance.
- **Fundamento:** Constitución §13 y Quality Gates 11–15; specs 003–006, 008 y 009.
- **Consecuencia:** repetir desde cero los 18 pasos locales, negativos, RBAC/RLS, redacción, consola/red y regresión sobre el candidato identificado. Históricos solo como antecedentes. No inventar umbrales de cobertura ni certificar resultados operativos reales con fixtures. Un cambio de candidato invalida el alcance de la aprobación anterior.

## D-006 — Locks exclusivos y handoff estructurado

- **Fecha:** 2026-11-11 (hora no registrada).
- **Estado:** establecida.
- **Decisión:** un escritor por ruta/recurso; el padre registra locks con propietario, revisión, alcance, vigencia y liberación. Prohibir solapamientos de prefijos, archivos o recursos mutantes; auditar snapshots congelados.
- **Consecuencia:** la delegación incluye permisos y entradas concretas; la devolución usa todos los campos AGENTE, FASE, ESTADO, OBJETIVO, REPOSITORIO/REVISIÓN, ENTORNO, TAREAS REALIZADAS, ARCHIVOS MODIFICADOS, PRUEBAS EJECUTADAS, RESULTADOS, EVIDENCIAS, DEFECTOS, RIESGOS, BLOQUEOS y RECOMENDACIÓN. Las tareas paralelas no pueden compartir escrituras.

## D-007 — Alcance Docker local concedido en esta sesión

- **Fecha:** 2026-11-11 (hora no registrada).
- **Estado:** autorización limitada comunicada por el usuario; sin operación ejecutada en esta entrega.
- **Contexto:** el usuario aprobó crear y desechar recursos Docker locales nuevos con nombres `ctt-release-qa...` para QA aislado.
- **Decisión:** inventariar recursos exactos y registrar cada operación concreta bajo esa autorización antes de ejecutarla; usar datos sintéticos. Comprobar contexto Docker local y ausencia de colisión con recursos existentes.
- **Límite:** no autoriza resetear Supabase existente, reutilizar/borrar volúmenes ajenos, limpiar globalmente Docker, copiar datos reales ni operar destinos remotos. Fuera de ese límite, pedir nueva aprobación.
- **Consecuencia:** creación y disposición son operaciones rastreables separadas; no se ejecutan comandos con comodines que afecten recursos no inventariados. No inventar comandos, ventanas ni constancias de consumo para esta autorización inicial.

## D-008 — Destinos desconocidos bloquean integración y staging

- **Fecha:** 2026-11-11 (hora no registrada).
- **Estado:** bloqueos abiertos de prerrequisitos.
- **Contexto:** ruta del repositorio Next.js desconocida; infraestructura staging desconocida.
- **Decisión:** solicitar al usuario ubicación autorizada/revisión del repo y datos de infraestructura/destinos/credenciales referenciadas. No realizar búsqueda externa, clonado, descubrimiento de cuentas ni exploración del sitio por inferencia.
- **Consecuencia:** no iniciar fase 3 ni 4 durante inicialización; después, continuar solo con sus gates y autorizaciones. La URL de 009 no concede permiso para extraer datos reales. Fixtures no prueban continuidad del catálogo de producción.

## D-009 — Separar candidato de producción

- **Fecha:** 2026-11-11 (hora no registrada).
- **Estado:** establecida.
- **Decisión:** fase 5A prepara y audita candidato/plan sin efectos en producción. Fase 5B exige aprobación humana explícita por operación con comando, destino, revisión, ventana y alcance máximo.
- **Consecuencia:** ni «continúa» ni aprobar el plan/gate autorizan producción. No hay commit, push, deploy, reset o copia de datos reales automáticos. Reintentos, migraciones, cambio de fuente y recuperación requieren sus propias autorizaciones; una autorización consumida no se reutiliza.

## D-010 — Permisos no equivalen a sandbox

- **Fecha:** 2026-11-11 (hora no registrada).
- **Estado:** establecida.
- **Decisión:** inspeccionar credenciales efectivas y destinos sin exponer secretos antes de efectos laterales; conceder permisos de herramienta solo una vez, nunca `--auto`. Revisar scripts/procesos hijos y herramientas que puedan eludir límites de alto nivel.
- **Consecuencia:** un `allow` no concede autorización de negocio y un `deny` no prueba aislamiento completo. Si destino o identidad efectiva no pueden verificarse, bloquear. Mantener la auditoría realmente sin escritura, no solo descrita como tal.

## D-011 — Evidencia, informes y aceptación

- **Fecha:** 2026-11-11 (hora no registrada).
- **Estado:** establecida; entregables de ejecución pendientes.
- **Decisión:** evidencias nuevas bajo `docs/orchestration/evidence/<run_id>/<fase>/`; informe local `docs/qa/reports/local-e2e-report.md`; integración `docs/integration/integration-report.md`; staging `docs/release/staging-validation-report.md`; plan `docs/release/production-release-plan.md`.
- **Consecuencia:** registrar tiempos reales, comandos, salidas, revisiones y destinos; redactar secretos/PII antes de persistir. Separar validación técnica de aceptación de negocio. No crear evidencia vacía como si fuera resultado, ni declarar éxito de gates a partir de este registro.

## Registro de decisiones posteriores

Añadir entradas con ID nuevo y referencia a la decisión reemplazada cuando corresponda; preservar el historial. Resolver por el padre bajo lock de DECISIONS.md. Un registro de autorización no puede omitir aprobación humana explícita ni rellenarse retrospectivamente para justificar una operación ya realizada. Los secretos nunca forman parte del registro.
