# Responsabilidades y handoff

Restauración: **2026-11-13**. Los seis agentes leen los cuatro documentos de orquestación al iniciar/reanudar. Sus definiciones persistentes se restauran por separado; su carga/runtime actual requiere verificación del padre.

## Agentes

| Agente | Función | Entrega y límite |
| --- | --- | --- |
| `ctt-release-orchestrator` | Primario; coordina G0, fases, locks, aprobaciones y auditorías | Mantiene estado/decisiones; no se sustituye al auditor ni concede autorización humana. No inicia G2 antes de G0. |
| `ctt-local-e2e` | Fase 2; recorrido fresco, suites, negativos y reproducción | `docs/qa/reports/local-e2e-report.md`; solo recursos locales nuevos autorizados. Correcciones con lock explícito. |
| `ctt-integration-engineer` | Fase 3; contratos 003/009 y consumidor Next.js | `docs/integration/integration-report.md`; requiere ruta/revisión autorizadas, sin búsqueda externa implícita. |
| `ctt-staging-validator` | Fase 4; candidato integrado, configuración, observabilidad y recuperación | `docs/release/staging-validation-report.md`; destino/identidad y operaciones deben estar autorizados. |
| `ctt-release-engineer` | 5A prepara candidato; 5B ejecuta operaciones expresamente autorizadas | `docs/release/production-release-plan.md`; aprobar 5A no autoriza producción. |
| `ctt-quality-gate-auditor` | Revisión independiente de G0 y cada gate posterior, solo lectura | Devuelve dictamen textual; no edita archivos, no corrige el objeto auditado, no ejecuta pruebas mutantes ni autoriza operaciones. |

El padre es propietario de `RELEASE-STATUS.md` e `initialization-report.md`. Otro agente restaura `.opencode/`; esta tarea solo restaura los cuatro documentos. Las fases 3–5 no se ejecutan en inicialización. Heredar modelo seleccionado; no cambiar `default_agent` ni hardcodear modelo. Reiniciar OpenCode tras restaurar configuración.

## Independencia

El ejecutor aporta hechos y recomendación, no se autoaprueba. El auditor contrasta requisitos, candidato, evidencia y permisos; si participó en la implementación auditada, declara conflicto y se obtiene revisión independiente. Puede solicitar una nueva prueba al ejecutor, pero no ejecutar tareas que escriban archivos, levanten servicios o modifiquen datos.

El padre conserva **verbatim** el texto del auditor bajo `docs/orchestration/evidence/`; metadatos y decisión del gate van separados. No resume ni corrige el dictamen original. Ausencia de respuesta o error de CLI no son dictámenes. El orquestador no puede convertir `RECHAZADO`/`NO VERIFICABLE` en aprobado: requiere subsanación y nueva revisión.

La delegación transmite límites, no amplía permisos ni reutiliza aprobaciones consumidas. Inspeccionar los permisos efectivos de `bash`, `task` y demás herramientas: describir al auditor como read-only no demuestra aislamiento real. Nunca `--auto`.

## Scope locks: un escritor por archivo/recurso

Antes de escribir, el padre registra y confirma un lock exclusivo:

```text
LOCK_ID / RUN_ID / PROPIETARIO Y SESIÓN / FASE:
OBJETIVO / REPOSITORIO / REVISIÓN BASE:
RUTAS EXACTAS O PREFIJOS / RECURSOS EXTERNOS:
OPERACIONES PERMITIDAS:
ADQUISICIÓN / VENCIMIENTO (fecha/hora y zona):
DEPENDENCIAS / LOCKS INCOMPATIBLES:
ESTADO (solicitado/adquirido/liberado/vencido):
HANDOFF / EVIDENCIA DE LIBERACIÓN:
```

- Comprobar solapamientos de prefijos, archivos y recursos: bases, migraciones, contratos, lockfiles, puertos, volúmenes y proyectos. Dos secciones del mismo archivo no son scopes independientes.
- Conceder solo rutas necesarias; la tabla de responsabilidades no otorga escritura general. Evidencia por `run_id`/fase, con un escritor por informe.
- Releer estado/diff antes y después de escribir. Cambios ajenos inesperados requieren pausa y conciliación; no revertirlos.
- Liberar lock con archivos, revisión, pruebas y pendientes. Antes de reasignar uno vencido, comprobar que el propietario dejó de escribir y conciliar trabajo parcial.
- Auditar snapshot congelado; cambios posteriores invalidan la aplicabilidad del dictamen. Paralelizar solo lecturas o escrituras/recursos disjuntos.

## Handoff

Toda delegación incluye tarea/run_id, emisor/receptor, fase, objetivo y requisito, revisión, entorno/destino, lock, aprobaciones concretas, evidencia de entrada, gate previo y criterio de salida. Para preparar/auditar G0 **no se exige G2**. Para ejecutar fase 2 sí se exige G0 habilitante.

El receptor confirma alcance, destino y vigencia/no consumo de aprobaciones. Si falta algo, devuelve `Bloqueada`, causa y petición concreta. No busca repositorios o credenciales por inferencia. Al devolver, distingue cambios propios/preexistentes, ejecución real/pendiente, evidencia nueva/histórica y siguiente acción. Una recomendación del ejecutor no habilita el siguiente gate.

## Informe obligatorio

Usar también al informar bloqueos. Completar con `No ejecutado`, `Ninguno` o `Desconocido` y motivo cuando corresponda; no inventar resultados.

```text
AGENTE:
FASE:
ESTADO: No iniciada | En ejecución | Bloqueada | Rechazada | Aprobada con observaciones | Aprobada
OBJETIVO:
REPOSITORIO/REVISIÓN:
ENTORNO:
TAREAS REALIZADAS:
ARCHIVOS MODIFICADOS:
PRUEBAS EJECUTADAS:
RESULTADOS:
EVIDENCIAS:
DEFECTOS:
RIESGOS:
BLOQUEOS:
RECOMENDACIÓN:
```

Incluir ruta/rama/SHA completo, diff y hash del estado probado; ambas revisiones para integración. Entorno incluye run_id, fecha/hora real con zona, versiones, destinos e identidades sin secretos. Pruebas incluye comandos/cwd/exit codes, casos y aprobaciones; separar ejecutadas, fallidas, omitidas y pendientes. Resultados contrasta esperado/observado. Evidencias incluye rutas, hashes y redacciones; históricos se rotulan como antecedentes. Defectos incluye requisito, severidad razonada, reproducción, responsable y retest; riesgos incluye impacto y aceptación explícita si existe. Archivos distingue cambios ajenos y lock; auditor declara `Ninguno; solo lectura`.

El auditor añade: `GATE`, `DICTAMEN: APROBADO | APROBADO CON OBSERVACIONES | RECHAZADO | NO VERIFICABLE`, `ALCANCE/REVISIÓN AUDITADA`, `CRITERIOS VERIFICADOS`, `CRITERIOS NO VERIFICADOS` y `CONDICIONES`. Si el CLI falla antes de responder, el padre registra **sin dictamen**, no atribuye un veredicto al auditor.
