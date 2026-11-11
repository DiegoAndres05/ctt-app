# Gates de calidad y auditoría independiente

Establecido: **2026-11-11**. Este documento define criterios; **no declara ningún gate aprobado**.

## 1. Fuentes y trazabilidad

Fuente normativa: [Constitución](../../.specify/memory/constitution.md), §13 «Verification & Quality Assurance» y §15, Quality Gates 11–15. La verificación incluye especificación, dominio, arquitectura, revisión, automatización, comprobación manual, aceptación de negocio y operación. Ningún mecanismo aislado basta; la validación independiente es obligatoria también para trabajo generado por IA.

| Gate constitucional | Aplicación a esta orquestación |
| --- | --- |
| 11 — Verification | Evidencia de revisión, validación, tests y aceptación ligada al requisito y candidato; ejecutar un comando no acredita corrección. |
| 12 — Testing | Selección por riesgo; automatización de funciones críticas y suites existentes pasando sin regresión. No se inventan porcentajes mínimos de cobertura. |
| 13 — Documentation | Contratos, procedimientos, decisiones e informes sincronizados con lo realmente implementado/probado. |
| 14 — Operational Readiness | Configuración, monitorización, logging, despliegue y recuperación documentados y comprobables; sin pasos manuales ocultos. |
| 15 — Review & Approval | Revisión independiente, incidencias críticas resueltas o aceptación explícita por autoridad competente, y aprobación sustentada en evidencia. |

La aceptación de un riesgo no acredita que un test pasó ni elimina un requisito obligatorio. Un defecto crítico no puede cerrarse por decisión unilateral de un agente. Si la aceptación propuesta contradice un requisito obligatorio o deja inseguro el destino, detener y resolver por gobernanza; no usar «observaciones» para saltar el gate. Los demás gates constitucionales aplicables siguen vigentes.

## 2. Estados y dictámenes

Estados únicos de gate: **No iniciada**, **En ejecución**, **Bloqueada**, **Rechazada**, **Aprobada con observaciones**, **Aprobada**.

| Dictamen independiente | Estado resultante | Efecto |
| --- | --- | --- |
| `APROBADO` | `Aprobada` | Habilita el siguiente gate solo para alcance y revisión auditados; aún se requieren autorizaciones operativas. |
| `APROBADO CON OBSERVACIONES` | `Aprobada con observaciones` | Avance condicionado a observaciones no bloqueantes, responsables/plazos y aceptación explícita del responsable; nunca dispensa criterios obligatorios. |
| `RECHAZADO` | `Rechazada` | Hay incumplimiento demostrado; corregir y volver a auditar. |
| `NO VERIFICABLE` | `Bloqueada` | Falta evidencia, acceso, trazabilidad o prerrequisito; no permite avanzar. |

Flujo normal: `No iniciada → En ejecución → dictamen → estado resultante`. Un bloqueo de prerrequisitos puede producir `Bloqueada` antes de ejecutar. Tras resolverlo o corregir un rechazo, volver a `En ejecución` con nueva evidencia y auditoría. Si cambia la revisión, entorno, configuración relevante o alcance, la aprobación anterior no cubre ese cambio: invalidar el gate afectado y sus dependientes hasta revalidar.

**Fail-closed:** falta de pruebas, ejecución omitida, informe histórico, destino desconocido, runtime no verificado, permiso insuficiente o auditoría ausente impiden aprobar. Lo no verificado no se convierte en observación no bloqueante. El silencio del auditor y la disponibilidad de herramientas no son aprobación.

## 3. Matriz de gates de release

### Prerrequisito G0 — Estabilización local

Antes de ejecutar fase 2: verificar D1 y D2 en Git/código actual, migraciones
efectivas, regresiones específicas y suites unitarias/SQL completas, y comprobar
que el entorno local está operativo. Informe histórico no basta. Auditoría
independiente obligatoria; si falta corrección o evidencia, bloquear G2 y entregar
diagnóstico. La prueba de entrada puede usar PostgreSQL desechable sin red para
regresiones SQL y consulta de salud local; no acredita todavía el E2E de Supabase.
Una aprobación de entrada permite preparar y ejecutar el stack E2E aislado, no
reutilizar datos existentes. Hashes de archivos permiten reconciliar un commit
concurrente sin repetir suites cuando sus entradas no cambiaron.

| Gate | Entrada y comprobaciones obligatorias | Evidencia de salida |
| --- | --- | --- |
| G2 — Local | Runtime y alcance confirmados; línea base completa; entorno nuevo autorizado; recorrido fresco de 18 pasos; suites existentes pertinentes SQL/frontend/build; matriz de negativos, RBAC/RLS, redacción y consola/red; defectos y regresiones examinados | Informe local, manifiesto de ejecución nueva, trazabilidad requisito/caso/resultado y dictamen independiente |
| G3 — Integración | G2 habilitante; repo Next.js autorizado y revisión identificada; contratos reales 003/009, consumidor y backend conectados; idiomas, publicación, caché, imágenes, solicitudes e idempotencia; ambas suites y aislamiento | Informe de integración, revisiones de ambos repos, pruebas de contrato y navegador, dictamen |
| G4 — Staging | G3 habilitante; infraestructura y credenciales efectivas verificadas; operaciones autorizadas; candidato reproducible desplegado en staging; configuración, recorrido integrado, negativos, regresión, rendimiento de specs, observabilidad y recuperación | Informe staging, destino/candidato/operaciones, evidencia de monitorización y recuperación, dictamen |
| G5A — Candidato | G4 habilitante; revisiones/artefactos congelados; plan operativo, backup/recuperación, aceptación de negocio, riesgos y continuidad de catálogo documentados; sin efectos de producción | Plan de producción, manifiesto de candidato, aprobaciones de calidad y dictamen limitado a preparación |
| G5B — Producción | G5A habilitante; aprobaciones humanas de uso único por operación con comando, destino, revisión, ventana y máximo alcance; precondiciones y respaldo verificados; ejecución y comprobaciones posteriores autorizadas | Registro de efectos reales, salud/monitorización, incidencias/recuperación cuando proceda y dictamen final |

Situación inicial: G2 no tiene evidencia fresca de repetición; G3 carece de ruta Next.js; G4 carece de infraestructura identificada; G5A/G5B dependen de gates anteriores y autorizaciones. El padre registra los estados actuales en RELEASE-STATUS.md. Esta matriz no ejecuta ni aprueba ninguna fase y las fases 3–5 quedan fuera de la inicialización.

## 4. Criterios de negocio derivados de specs

Consultar los escenarios y contratos completos antes de ejecutar; esta matriz resume mínimos, no reemplaza las especificaciones.

| Fuente | Criterios comprobables y negativos imprescindibles |
| --- | --- |
| [003](../../specs/003-customer-requests-channels/spec.md), FR-001–010, SC-001–004 | Captura pública por organización/ficha; cliente/canal asociados; solicitud no es reserva; deduplicación de 2 minutos/idempotency key; email antes de teléfono, completar solo vacíos y marcar conflictos; WhatsApp simulado idempotente, anexado a abierta e inactivo sin credenciales; transiciones manuales restringidas y descarte con motivo; conversión a pre-reserva solo por 004; primera gestión y bandeja sin recarga; PII privada y anonimización admin con integridad histórica. |
| [004](../../specs/004-prereservation-availability/spec.md), FR-001–007 y escenarios | Pre-reserva pendiente con líneas concretas; cola operator/admin; verificación humana por línea con responsable/contacto/tiempos; consolidación de estados, no disponibilidad y expiración; bloqueo de cotización no elegible salvo excepción admin auditada según contrato. Un agente sin permiso no puede forzarla por API. |
| [005](../../specs/005-quotation-proposals/spec.md), FR-001–008, SC-001–004 | Cálculo de líneas/totales/descuentos sin discrepancias; referencia y versión; vigencia y términos obligatorios y límite del proveedor más restrictivo; importes congelados al emitir; versionado conserva anteriores; vista móvil y resumen WhatsApp; rechazo de aceptación expirada, cambios directos sobre emitida y accesos públicos indebidos. |
| [006](../../specs/006-reservation-lifecycle/spec.md), FR-001–008, SC-001–004 | Confirmación desde cotización aceptada vigente y depósito registrado; rechazar expirada/rechazada; localizador único, pasajeros y servicios coherentes, voucher; transiciones válidas, cancelación/modificación/contingencia auditadas; orden de proveedor sin precios finales ni datos de otros prestadores; cancelación en ejecución exige privilegio admin e informe. |
| [008](../../specs/008-analytics-reporting/spec.md), FR-001–007, SC-001–004; [plan](../../specs/008-analytics-reporting/plan.md) | Embudo por fechas/canal, tiempos y alertas, ranking, reconciliación monetaria por moneda y tratamiento explícito de cancelaciones; periodo vacío sin división por cero; CSV coherente con datos servidor; agente solo estadísticas propias, finanzas/auditoría para supervisión; aislamiento tenant en RPC; UI no recalcula dinero/tasas, fechas America/Bogota y límites de rango/export del plan; visor de auditoría existente, íntegro y filtrable. |
| [009](../../specs/009-catalog-site-cms/spec.md), FR-001–030, SC-001–010 | Operador/admin editan, agente consulta; ficha completa ES/EN y listas alineadas; imagen obligatoria, JPEG/PNG/WebP hasta 10 MB; slugs únicos e inmutables tras publicar; solo publicado/activo, sin republicación automática al reactivar; agotado visible pero no solicitable; ofertas/alojamientos/yates separados; precio vitrina no modifica tarifa/cotización; imágenes y agencia aisladas; publicación auditada; cambio de fuente bloqueado si falta contenido vigente y continuidad de URLs/precios actuales. |

009 requiere copia real antes del cambio de fuente, pero esa obligación funcional no autoriza extracción ni copia. En local se ensaya con fixtures; la completitud real queda pendiente de acceso y operación expresamente autorizados. Si se detecta contradicción de estados/roles entre spec y contrato, documentar el conflicto y resolverlo, no inventar la regla al probar.

### Medición sin umbrales inventados

Registrar dispositivo, volumen, entorno, método y tiempos observados. Usar los objetivos publicados: 003 SC-001 recepción <2 s y SC-004 bandeja ≤10 s; 004 SC-004 cola <3 clics; 005 SC-001 armado/emisión <3 min; 006 SC-002 voucher <3 s; 008 SC-001 panel <2 s y SC-004 exportación de hasta 10 000 registros <5 s; 009 SC-001 publicación <8 min. Los porcentajes de integridad/coherencia de las specs son resultados funcionales, **no cobertura de código**.

004 SC-002 (<4 horas hábiles de verificación) y resultados operativos de sobreventa requieren observación de negocio: una simulación local no demuestra el promedio real ni resultados futuros. Registrar límite, responsable y validación de aceptación correspondiente. No convertir una medición local en un SLA probado en producción. Los criterios de negocio no observados siguen explícitamente pendientes para el gate que los exige.

## 5. Matriz transversal obligatoria

| Área | Verificación y evidencia |
| --- | --- |
| Negativos de entrada | Campos vacíos/malformados, fechas pasadas, cantidades inválidas, imagen inválida/excesiva, listas bilingües desalineadas, slug duplicado, ficha incompleta; rechazo sin persistencia parcial. |
| Negativos de estado | Solicitud descartada terminal, pre-reserva no verificada/expirada, cotización expirada/rechazada/anulada o snapshot emitido, transición inválida de reserva, publicación inactiva/agotada; documentar respuesta y estado final. |
| RBAC | Matriz anon/agent/operator/admin sobre UI **y** RPC/API/Storage. Probar acceso por URL directa y llamada directa; ocultar un botón no prueba autorización. Incluir cola, publicación/imágenes, excepciones, anonimización, reportes globales y auditoría. |
| RLS/tenant | Dos organizaciones sintéticas; intentos de lectura/escritura/export y acceso a objetos de la otra organización; no fuga por ID/slug/token o agregados. Separar lectura pública autorizada de endpoints privados. |
| Idempotencia/concurrencia | Doble submit, repetición de mensajes, confirmación duplicada y referencias/localizadores; coherencia de efectos persistidos. Reintentos de prueba solo en entorno autorizado. |
| Redacción/minimización | API pública, vista cotización, voucher, órdenes por proveedor, CSV, logs, auditoría, errores, capturas y trazas: sin secretos/service role/JWT/cookies ni PII fuera del alcance del actor. Usar datos sintéticos y redactar antes de guardar evidencia. |
| Consola | Capturar consola durante todo el recorrido; clasificar errores/warnings. Ningún error inesperado queda sin investigar; registrar defectos y resolver o tramitar aceptación explícita según su impacto. |
| Red | Registrar método/ruta sanitizada, destino, status y timing; diferenciar fallos esperados de negativos de 4xx/5xx inesperados; revisar CORS, solicitudes duplicadas, endpoints reales accidentales y payloads expuestos. No guardar HAR sin redacción. |
| Auditoría | Actor, organización, fecha/hora y motivo en cambios críticos; consulta según rol e intentos de modificación no autorizada rechazados; conciliar eventos con acciones realizadas. |
| Regresión | Ejecutar suites existentes pertinentes a la revisión, incluyendo fixes 056/057 cuando se identifiquen; comandos y exit codes reales. Test omitido o herramienta ausente se informa como no verificado. |

## 6. Evidencia admisible y auditoría

Toda afirmación de cumplimiento necesita: `run_id`, fecha/hora real con zona, repositorio/revisión/estado de trabajo, entorno/destino, requisito, caso, esperado, observado, comando o acción, exit code cuando aplique y artefacto redactado. Conservar manifiesto y hashes bajo `docs/orchestration/evidence/<run_id>/<fase>/`.

El auditor revisa trazabilidad, frescura, integridad, correspondencia entre candidato y entorno, negativos, aceptación de negocio y autorizaciones. Puede pedir repetición al ejecutor; no modifica el objeto auditado ni produce evidencia mutante. Un reporte histórico, una casilla marcada, un test listado sin salida o un modelo listado sin invocación no prueban ejecución nueva.

Dictamen con alcance explícito, criterios verificados/no verificados, referencias de evidencia, defectos, riesgos y condiciones. El padre lo persiste literalmente y registra la transición del gate por separado. Sin evidencia suficiente, el dictamen es `NO VERIFICABLE` y el gate queda `Bloqueada`.
