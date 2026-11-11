# Responsabilidades, locks y handoffs

Establecido: **2026-11-11**. Lectura de arranque obligatoria para los seis agentes junto con RELEASE-ORCHESTRATION.md, QUALITY-GATES.md y DECISIONS.md.

## 1. Agentes persistentes

El padre crea las definiciones Markdown V1 en `.opencode/agents/` y verifica su runtime en OpenCode 1.19.5. Esta tabla especifica responsabilidades, no afirma que las definiciones ya estén cargadas. Heredar el modelo seleccionado; no cambiar `default_agent` ni fijar modelos.

| Agente | Modo/función prevista | Responsabilidad | Límite y entrega |
| --- | --- | --- | --- |
| `ctt-release-orchestrator` | Primario | Leer estado, planificar, asignar locks, delegar fases, pedir auditoría y aplicar gates; solicitar autorizaciones concretas | No sustituye auditoría ni aprobación humana. Mantiene estado y decisiones; no toma código en escritura mientras otro agente lo posea. |
| `ctt-local-e2e` | Especialista fase 2 | Ejecutar desde cero los 18 pasos, suites SQL/frontend y negativos; reproducir defectos sobre recursos locales nuevos autorizados | Informe `docs/qa/reports/local-e2e-report.md`; no resetea Supabase existente. Correcciones solo con lock y alcance explícitos. |
| `ctt-integration-engineer` | Especialista fase 3 | Integrar contratos 003/009 y consumidor Next.js, probar ambos extremos y continuidad del catálogo | Informe `docs/integration/integration-report.md`; bloqueado hasta recibir ruta del segundo repo y autorización de acceso. Sin búsquedas externas implícitas. |
| `ctt-staging-validator` | Especialista fase 4 | Validar candidato en infraestructura staging identificada; configuración, regresión, observabilidad y recuperación | Informe `docs/release/staging-validation-report.md`; no asume destinos ni opera infraestructura sin aprobación. |
| `ctt-release-engineer` | Especialista fases 5A/5B | Preparar candidato y plan; ejecutar posteriormente operaciones de producción individualmente autorizadas | `docs/release/production-release-plan.md` y evidencia de operaciones. La aprobación 5A no habilita 5B por sí sola. |
| `ctt-quality-gate-auditor` | Auditor independiente, solo lectura | Contrastar requisitos, revisión, evidencia fresca, riesgos y aprobaciones; emitir dictamen | No edita código, informes, estado ni evidencia; no corrige lo auditado y no concede autorización operativa. Devuelve texto al padre. |

Las fases 3–5 no se ejecutan durante la inicialización. El padre es dueño exclusivo de `docs/orchestration/RELEASE-STATUS.md` e `initialization-report.md` durante ella. En la operación posterior, el orquestador actúa como padre/coordinador conforme a la transferencia explícita de ownership.

## 2. Reglas de independencia y permisos

- El ejecutor entrega hechos y recomendación; únicamente el auditor produce el dictamen independiente. Si el auditor participó en implementar el objeto de revisión, declarar conflicto y pedir revisión independiente antes de aprobar.
- El auditor consulta snapshots/evidencia y fuentes autorizadas mediante herramientas de solo lectura. No ejecuta tests que generen archivos, levanten servicios o alteren datos. Solicita al ejecutor una nueva comprobación cuando falte evidencia.
- El padre persiste la respuesta del auditor **verbatim**, sin resumir ni corregir el bloque original. Comentarios, discrepancias y decisión del gate van fuera del bloque, con referencias. El auditor nunca escribe el dictamen al filesystem.
- El orquestador no puede convertir `RECHAZADO` o `NO VERIFICABLE` en aprobado por su cuenta. Solicita corrección/evidencia y un dictamen nuevo.
- Toda capacidad de `bash`, `task`, herramientas externas o credenciales debe inspeccionarse en el runtime efectivo. Los permisos no son aislamiento de sistema operativo ni prueba de que el destino sea local.
- La delegación no amplía los permisos ni transmite aprobaciones consumidas. El especialista recibe solo el alcance y la operación aprobados. Nunca usar `--auto`.

## 3. Scope locks: un escritor por recurso

El padre mantiene el registro de locks en RELEASE-STATUS.md. Antes de delegar escritura, adquiere un lock exclusivo de rutas **y** recursos externos; sin confirmación del padre, el agente solo puede leer dentro del alcance permitido. No basta que dos agentes escriban líneas diferentes del mismo archivo.

```text
LOCK_ID / RUN_ID:
PROPIETARIO (agente y sesión):
FASE / OBJETIVO:
REPOSITORIO Y REVISIÓN BASE:
RUTAS EXACTAS O PREFIJOS AUTORIZADOS:
RECURSOS (base, proyecto, volumen, puerto, entorno):
OPERACIONES PERMITIDAS:
FECHA/HORA DE ADQUISICIÓN Y VENCIMIENTO:
DEPENDENCIAS / LOCKS INCOMPATIBLES:
ESTADO (solicitado / adquirido / liberado / vencido):
HANDOFF Y EVIDENCIA DE LIBERACIÓN:
```

1. Comparar solapamientos de rutas, prefijos y recursos, incluyendo migraciones, contratos, lockfiles y bases compartidas. Una colisión bloquea la segunda escritura.
2. Dar al especialista solo rutas necesarias. La matriz de agentes no concede por sí misma acceso de escritura a todo un directorio.
3. Separar evidencia por `run_id` y fase; no permitir dos escritores sobre un informe. Si el padre persiste un informe delegado, el especialista entrega texto y el padre conserva el lock.
4. Releer estado/diff antes y después de escribir; un cambio ajeno inesperado requiere pausa y conciliación con el padre. No sobrescribir ni revertir trabajo del usuario.
5. Liberar el lock al entregar archivos, revisión, pruebas y pendientes. Un lock vencido no se reasigna hasta comprobar que el dueño dejó de escribir y conciliar cambios parciales.
6. Auditar una revisión/snapshot congelado. Una modificación concurrente invalida la aplicabilidad del dictamen a la nueva revisión.
7. Paralelizar solo lecturas o trabajos con locks disjuntos y sin recursos mutantes compartidos. Integración, migraciones y correcciones que afecten el mismo candidato se serializan.

Durante esta creación documental, el alcance de escritura está limitado a los cuatro documentos nuevos de orquestación; no implica permiso para modificar aplicación, configuración de agentes, informes existentes ni archivos del usuario.

## 4. Handoff obligatorio

Cada delegación incluye: identificador de tarea y ejecución, agente emisor/receptor, fase, objetivo verificable, requisito/spec, repositorio y revisión, entorno/destino, lock concedido, operaciones autorizadas y sus IDs, evidencia de entrada, gate previo, restricciones, criterios de salida y ruta del informe. Debe explicitar lo desconocido.

Al aceptar, el receptor confirma que el lock y el destino coinciden, que las aprobaciones siguen vigentes y no consumidas, y que puede producir evidencia nueva. Si falta una entrada necesaria, devuelve estado `Bloqueada`, motivo y petición concreta; no busca credenciales ni repositorios por iniciativa propia.

Al devolver, identifica qué cambió respecto a la entrada, los comandos realmente ejecutados, sus efectos, qué evidencia es nueva y qué queda pendiente. La siguiente fase comienza solo tras dictamen y transición de gate documentada; una recomendación del ejecutor no es un handoff habilitante.

## 5. Plantilla de informe y respuesta de agente

Todos los campos son obligatorios, incluidos en informes de bloqueo. Usar `No ejecutado`, `Ninguno` o `Desconocido` con explicación cuando corresponda; nunca rellenar resultados por expectativa.

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

Contenido mínimo adicional, dentro de esos campos o anexos:

- `REPOSITORIO/REVISIÓN`: ruta autorizada, rama, SHA completo, manifestación del diff/archivos sin seguimiento y hash del candidato probado; ambas revisiones para integración.
- `ENTORNO`: `run_id`, fecha/hora real con zona, versiones, recursos, destinos e identidades referenciadas sin secretos.
- `ARCHIVOS MODIFICADOS`: rutas propias, cambios preexistentes distinguidos y lock utilizado; si el agente es auditor: `Ninguno; solo lectura`.
- `PRUEBAS EJECUTADAS`: comandos exactos, cwd, fecha/hora, exit code, suites/casos, aprobaciones si corresponden. Separar ejecutadas, fallidas, omitidas y pendientes.
- `RESULTADOS`: esperado frente a observado por caso; reconciliación de negocio, no solo resumen de exit codes.
- `EVIDENCIAS`: rutas nuevas en `docs/orchestration/evidence/<run_id>/<fase>/`, identificadores de casos, hashes, redacciones y límites. Referencias históricas rotuladas como antecedentes.
- `DEFECTOS`: ID, requisito afectado, severidad razonada, reproducción, responsable, corrección y retest; no ocultar fallos tras reintentos.
- `RIESGOS`: impacto, responsable y aceptación humana explícita si existe. `BLOQUEOS`: causa y entrada/autorización requerida.
- `RECOMENDACIÓN`: siguiente acción concreta; no declarar gate aprobado sin dictamen y decisión persistidos.

El auditor usa los mismos campos y añade `DICTAMEN: APROBADO | APROBADO CON OBSERVACIONES | RECHAZADO | NO VERIFICABLE`, `GATE`, `ALCANCE/REVISIÓN AUDITADA`, `CRITERIOS VERIFICADOS`, `CRITERIOS NO VERIFICADOS` y `CONDICIONES`. El padre conserva todo el texto original en un artefacto de evidencia y enlaza su decisión por separado.
