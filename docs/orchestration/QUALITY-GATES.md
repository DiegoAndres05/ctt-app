# Gates de calidad

Restauración: **2026-11-13**. Ningún gate queda aprobado por este documento.

## Fundamento

[Constitución](../../.specify/memory/constitution.md) §13 exige trazabilidad desde especificaciones, verificación basada en riesgo, revisión independiente, automatización, comprobación manual, aceptación de negocio y validación operativa. Tests técnicos no sustituyen aceptación. Quality Gates de §15:

| Gate constitucional | Evidencia exigida |
| --- | --- |
| 11 — Verification | Revisión, validación, pruebas y aceptación vinculadas a requisitos/candidato. |
| 12 — Testing | Automatización proporcional al riesgo, suites existentes sin regresión. **Sin porcentajes de cobertura inventados.** |
| 13 — Documentation | Documentos y contratos sincronizados con implementación/procedimientos reales. |
| 14 — Operational Readiness | Configuración, monitorización, logs y procedimientos de despliegue/recuperación completos, sin pasos ocultos. |
| 15 — Review & Approval | Revisión requerida y aprobación basada en evidencia; incidencias críticas resueltas o aceptación explícita por autoridad competente. |

Una aceptación de riesgo no demuestra que un test pasó ni permite a un agente dispensar requisitos obligatorios. Conflictos requieren resolución por gobernanza; no ocultarlos como observaciones. Los demás gates constitucionales aplicables siguen vigentes.

## Estados, dictámenes y avance

Estados: **No iniciada / En ejecución / Bloqueada / Rechazada / Aprobada con observaciones / Aprobada**.

| Dictamen del auditor | Estado | Regla |
| --- | --- | --- |
| APROBADO | Aprobada | Habilita dependencia solo en alcance/revisión auditados; no autoriza operaciones. |
| APROBADO CON OBSERVACIONES | Aprobada con observaciones | Solo observaciones no bloqueantes, con responsable/plazo y aceptación explícita del responsable; ningún requisito obligatorio sin verificar. |
| RECHAZADO | Rechazada | Incumplimiento demostrado; corregir y reauditar. |
| NO VERIFICABLE | Bloqueada | Falta evidencia/prerrequisito verificable; no avanzar. |

Sin respuesta del auditor, error CLI o cuota agotada: registrar **sin dictamen**, gate `Bloqueada`; no fabricar `NO VERIFICABLE` como si el auditor lo hubiera emitido. Las dos situaciones bloquean, pero su procedencia es distinta.

Flujo: No iniciada → En ejecución → estado según auditoría; un prerrequisito ausente puede bloquear antes de ejecutar. Tras subsanar, nueva ejecución/revisión. Cambios de revisión, entorno, configuración relevante o alcance invalidan la aprobación afectada y sus dependientes hasta revalidar. Informes históricos, permisos disponibles, silencio o evidencia omitida no habilitan avance: **fail-closed**.

## G0 — Prerrequisitos de ejecución local

**Objetivo:** demostrar que la orquestación restaurada puede iniciar fase 2 de forma trazable, acotada y autorizada. **No exige ejecutar G2, tener el informe local aprobado ni demostrar resultados de las pruebas funcionales.** Tampoco requiere repo Next.js ni infraestructura staging para autorizar solo el alcance local.

Entrada y criterios obligatorios:

1. Identificar HEAD completo actual, rama, diff/untracked y propietarios; proteger cambios concurrentes. Contrastar baseline `2844c6fc7a361ee821d9b118abf4d34fdb4f7868`.
2. Los cuatro documentos restaurados y seis agentes persistentes existen y son consistentes. El padre dispone de estado/locks y registra los bloqueos conocidos.
3. Tras reiniciar, verificar versión/configuración efectiva V1, carga de los seis agentes, modelo heredado, selección del primario y delegación a especialistas/auditor dentro de permisos. Registrar comprobaciones actuales: smoke histórico 5/5 no basta.
4. Verificar límites efectivos del auditor de solo lectura y del ejecutor; permisos no son sandbox. No exponer secretos en evidencia.
5. Identificar herramientas/dependencias necesarias, contexto Docker local y destinos/configuración del futuro entorno. Planificar nombres nuevos `ctt-release-qa...` sin colisiones, datos sintéticos y separación de Supabase existente. G0 no requiere crear ese entorno ni ejecutar migraciones.
6. Registrar autorización actual del usuario para recursos Docker nuevos, protocolo de operaciones concretas, locks, plan de 18 pasos, suites previstas y rutas de evidencia/informe.
7. Obtener auditoría independiente de estos prerrequisitos sobre la revisión/configuración actuales; padre persiste texto literal y decisión. Ante 429 u otro fallo sin dictamen, mantener bloqueo hasta nueva auditoría completada.

Salida: evidencia actual de prerrequisitos y dictamen habilitante. Solo entonces iniciar G2. Las tareas de restauración, lectura y verificación necesarias para G0 no dependen de G2; no existe ciclo G0↔G2.

## Gates posteriores

| Gate | Criterios de salida y evidencia |
| --- | --- |
| G2 — Local | G0 habilitante; entorno nuevo autorizado; 18 pasos frescos; suites pertinentes existentes SQL/frontend/build y regresión de estabilización/lint; negativos/RBAC/RLS/redacción/consola/red; informe local, matriz requisito-caso-resultado y auditoría independiente. |
| G3 — Integración | G2 habilitante; ruta Next.js autorizada y revisiones de ambos repos; contratos 003/009 conectados al consumidor real, pruebas de ambos extremos y navegador; informe y auditoría. |
| G4 — Staging | G3 habilitante; infraestructura/identidad verificadas y operaciones autorizadas; candidato reproducible desplegado, recorrido integrado, regresión, configuración, rendimiento de specs, observabilidad y recuperación; informe y auditoría. |
| G5A — Candidato | G4 habilitante; revisiones/artefactos congelados, plan operativo, aceptación de negocio, riesgos, backup/recuperación y continuidad de catálogo documentados; dictamen limitado a preparación, sin producción. |
| G5B — Producción | G5A habilitante y autorizaciones humanas por operación; precondiciones/respaldo verificados; efectos reales y comprobaciones posteriores autorizadas, monitorización y recuperación si corresponde; auditoría final. |

Estado de referencia al restaurar: última auditoría G0 fallida por 429 sin dictamen; G0 bloqueado y G2 no habilitado. Ruta Next.js e infraestructura staging desconocidas. Fases 3–5 no se ejecutan en inicialización. El padre mantiene el estado vivo en RELEASE-STATUS.md.

## Criterios funcionales trazables

| Fuente | Mínimos de verificación |
| --- | --- |
| [003](../../specs/003-customer-requests-channels/spec.md), FR-001–010 y SC | Captura por organización/ficha, cliente/canal, solicitud no es reserva; deduplicación de 2 minutos/idempotency key; email antes de teléfono, completar solo vacíos y marcar conflictos; WhatsApp simulado idempotente/anexado a abierta, real inactivo sin credenciales; estados y descarte con motivo, conversión solo por 004; primera gestión/bandeja; anonimización solo admin e historia preservada. |
| [004](../../specs/004-prereservation-availability/spec.md), FR-001–007 y escenarios | Pre-reserva pendiente con líneas; cola operator/admin; actor/contacto/tiempos/límite por verificación humana; consolidación, no disponibilidad, expiración; cotización bloqueada si no elegible salvo excepción admin auditada según contrato. |
| [005](../../specs/005-quotation-proposals/spec.md), FR-001–008 y SC | Cálculo servidor coherente, moneda/desglose/descuentos; referencia/versionado; términos y vigencia limitada por proveedor; snapshot al emitir, historia al versionar, vista móvil/resumen WhatsApp; rechazo de aceptación expirada y cambios indebidos sobre emitida. |
| [006](../../specs/006-reservation-lifecycle/spec.md), FR-001–008 y SC | Confirmación desde aceptada vigente con depósito; rechazo de expirada/rechazada; localizador único, pasajeros/servicios, voucher; transiciones/cancelación/modificación/contingencia auditadas; órdenes sin precios finales/datos de otros proveedores; cancelación en ejecución exige admin e informe. |
| [008](../../specs/008-analytics-reporting/spec.md) y [plan](../../specs/008-analytics-reporting/plan.md) | Embudo por fechas/canal, tiempos/alertas, ranking, reconciliación monetaria/cancelaciones y CSV; vacío sin división por cero; agente solo estadísticas propias, supervisión para finanzas/auditoría, tenant en RPC; UI sin recalcular dinero/tasas; America/Bogota, rango máximo 366 días y export hasta 10 000 según plan; visor existente íntegro/filtrable. |
| [009](../../specs/009-catalog-site-cms/spec.md), FR-001–030 y SC | Edición operator/admin, agente consulta; ES/EN completo/listas alineadas; imagen obligatoria JPEG/PNG/WebP hasta 10 MB; slug único/inmutable; publicado/activo y sin republicación automática; agotado visible no solicitable; secciones separadas, vitrina independiente de tarifas/cotizaciones; aislamiento de imágenes/agencia y auditoría; continuidad de URLs/contenido/precios y bloqueo de cambio de fuente si falta ficha vigente. |

Consultar contratos y escenarios completos; ante ambigüedad/conflicto de estados o roles, resolver documentalmente, no inventar comportamiento. La obligación 009 de copiar catálogo antes del cambio de fuente no autoriza copiar datos reales. Fixtures locales no prueban completitud de catálogo real; acceso e inventario real quedan pendientes hasta autorización.

Medir con método, entorno y volumen registrados: 003 recepción <2 s y bandeja ≤10 s; 004 cola <3 clics; 005 emisión estándar <3 min; 006 voucher <3 s; 008 panel <2 s y export hasta 10 000 filas <5 s; 009 publicar <8 min. Son objetivos de specs, no cobertura de código. El promedio operativo 004 <4 horas hábiles y resultados reales de sobreventa requieren validación de negocio: una simulación no los acredita. Lo no observado sigue pendiente para el gate aplicable.

## Matriz transversal obligatoria de G2 y regresión posterior

- **Entrada/estado negativos:** campos inválidos, fechas pasadas, cantidades, imágenes, bilingüismo, slugs, publicación incompleta, descartada terminal, pre-reserva no elegible, cotización expirada/rechazada/anulada, snapshot emitido y transición inválida de reserva. Comprobar rechazo y ausencia de persistencia parcial.
- **RBAC:** anon/agent/operator/admin sobre UI, URL directa, API/RPC y Storage; cola, publicación, excepciones, anonimización, finanzas y auditoría. Ocultar controles no prueba autorización.
- **RLS:** dos organizaciones; intentos cruzados de lectura/escritura/export/objetos/agregados; distinguir lectura pública permitida de datos privados. Probar IDs/slugs/tokens manipulados.
- **Idempotencia/concurrencia:** doble submit, mensaje repetido, confirmación duplicada y unicidad de referencias; comprobar efectos persistidos.
- **Redacción:** vistas públicas, voucher, órdenes, CSV, logs, auditoría, errores y evidencias sin secretos/service role/JWT/cookies ni PII fuera del alcance del actor; datos sintéticos y sanitización antes de persistir.
- **Consola/red:** capturar recorrido completo; clasificar errores/warnings y 4xx/5xx esperados frente a inesperados, CORS, duplicaciones, destinos y payloads. Registrar método/ruta sanitizada/status/tiempo; no guardar HAR sin redactar. Investigar todo error inesperado.
- **Auditoría/regresión:** actor, organización, tiempo y motivo en acciones críticas; consulta autorizada y modificación indebida rechazada. Suites pertinentes actuales, con comandos y exit codes; omitido/ausente no equivale a aprobado.

## Evidencia admisible

Cada afirmación necesita run_id, fecha/hora real con zona, revisión/estado de trabajo, entorno/destino, requisito/caso, esperado/observado, acción/comando, exit code si aplica y artefacto redactado. Conservar manifiesto/hashes en `docs/orchestration/evidence/<run_id>/<fase>/`. El auditor trabaja sobre snapshot identificado y devuelve texto que el padre persiste literalmente. Los 143 unitarios/45 SQL de `84375d3` y el smoke 5/5 son históricos, no evidencia fresca ni aprobaciones actuales.
